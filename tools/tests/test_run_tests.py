"""Unit tests for run_tests.py's discovery, configuration checks and failure detection."""
import contextlib
import io
import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import run_tests


class FindProblems(unittest.TestCase):
    def test_clean_log_has_no_problems(self):
        self.assertEqual(run_tests.find_problems("PASS: thing\nAll good\n", 0, []), [])

    def test_engine_and_script_errors_fail(self):
        log = "SCRIPT ERROR: Invalid call\nERROR: Condition failed\nParse Error: bad\n"
        self.assertEqual(len(run_tests.find_problems(log, 0, [])), 3)

    def test_exit_leaks_fail(self):
        log = ("WARNING: 3 ObjectDB instances were leaked at exit (run with `--verbose` for details).\n"
               "ERROR: 1 resources still in use at exit (run with --verbose for details).\n")
        self.assertEqual(len(run_tests.find_problems(log, 0, [])), 2)

    def test_ordinary_warnings_and_file_names_pass(self):
        log = "WARNING: leaderboard schema newer\nStoring File: sfx_sounds_error1.wav\n"
        self.assertEqual(run_tests.find_problems(log, 0, []), [])

    def test_expected_errors_are_allowed_but_must_still_occur(self):
        expected = [re.compile(r"^ERROR: ConfigFile parse error")]
        self.assertEqual(run_tests.find_problems("ERROR: ConfigFile parse error at x\n", 0, expected), [])
        stale = run_tests.find_problems("all fine\n", 0, expected)
        self.assertEqual(len(stale), 1)
        self.assertIn("no longer occurs", stale[0])

    def test_timeout_is_a_problem(self):
        self.assertIn("timed out", run_tests.find_problems("", None, [])[0])


class ClassifyLeaks(unittest.TestCase):
    AUDIO = ("Leaked instance: AudioStreamPlaybackMP3:1 - Reference count: 1\n"
             "Leaked instance: AudioStreamPlaybackPolyphonic:2 - Reference count: 1\n"
             "Resource still in use: res://Assets/Audio/Main Menu/track.mp3 (AudioStreamMP3)\n")

    def test_ogg_internals_count_as_audio(self):
        log = ("Leaked instance: OggPacketSequence:1 - Reference count: 3\n"
               "Leaked instance: OggPacketSequencePlayback:2 - Reference count: 1\n"
               "Leaked instance: AudioStreamOggVorbis:3 - Reference count: 1\n")
        self.assertTrue(run_tests.classify_leaks(log)[0])

    def test_audio_teardown_race_is_recognized(self):
        audio_only, details = run_tests.classify_leaks(self.AUDIO)
        self.assertTrue(audio_only)
        self.assertEqual(len(details), 3)

    def test_any_other_leak_is_not_tolerated(self):
        audio_only, details = run_tests.classify_leaks(self.AUDIO + "Leaked instance: Node3D:9 - Node path:\n")
        self.assertFalse(audio_only)
        self.assertIn("leaked: Node3D", details)
        texture = "Resource still in use: res://a.png (CompressedTexture2D)\n"
        self.assertFalse(run_tests.classify_leaks(self.AUDIO + texture)[0])

    def test_a_leak_without_detail_is_not_tolerated(self):
        self.assertEqual(run_tests.classify_leaks("WARNING: 3 ObjectDB instances were leaked at exit\n"), (False, []))

    def test_an_rid_leak_beside_the_audio_race_is_not_tolerated(self):
        rid = "ERROR: 2 RID allocations of type 'N12MeshStorage4MeshE' were leaked at exit."
        audio_only, details = run_tests.classify_leaks(self.AUDIO + rid + "\n")
        self.assertFalse(audio_only)
        self.assertIn(rid, details)


class RunSuite(unittest.TestCase):
    """run_suite() turns only the audio-teardown race into a note; every other leak still fails."""
    SUMMARY = ("WARNING: 3 ObjectDB instances were leaked at exit (run with `--verbose` for details).\n"
               "ERROR: 1 resources still in use at exit (run with --verbose for details).\n")
    RID = "ERROR: 2 RID allocations of type 'N12MeshStorage4MeshE' were leaked at exit."

    def run_with_log(self, log):
        result = run_tests.Result("fake", 1.0, 0, run_tests.find_problems(log, 0, []), log)
        with mock.patch.object(run_tests, "run_once", return_value=result):
            return run_tests.run_suite("godot", "fake", [])

    def test_the_audio_race_alone_passes_with_a_note(self):
        result = self.run_with_log(self.SUMMARY + ClassifyLeaks.AUDIO)
        self.assertTrue(result.passed, result.problems)
        self.assertIn("audio-teardown race", result.notes[0])

    def test_an_rid_leak_mixed_with_the_audio_race_still_fails(self):
        result = self.run_with_log(self.SUMMARY + self.RID + "\n" + ClassifyLeaks.AUDIO)
        self.assertFalse(result.passed)
        self.assertIn(self.RID, result.problems)
        self.assertEqual(result.notes, [])


class SetupFailures(unittest.TestCase):
    """A run that stops before any suite still writes a results summary saying why."""

    def run_main(self, results, **patches):
        argv = ["run_tests.py", "--godot", "godot", "-k", "runner_logic", "--results", str(results)]
        with mock.patch("sys.argv", argv), contextlib.redirect_stderr(io.StringIO()), \
                contextlib.ExitStack() as stack:
            for name, value in patches.items():
                stack.enter_context(mock.patch.object(run_tests, name, value))
            return run_tests.main()

    def test_an_isolation_failure_writes_the_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            results = Path(tmp, "summary.json")
            code = self.run_main(results, check_isolation=mock.Mock(return_value="user:// resolved to /real"))
            self.assertEqual(code, 2)
            summary = json.loads(results.read_text(encoding="utf-8"))
            self.assertIn("/real", summary["setup_error"])
            self.assertEqual(summary["suites"], [])

    def test_an_import_failure_writes_the_summary(self):
        imported = subprocess.CompletedProcess([], 0, stdout="ERROR: Cannot import x.png\n", stderr="")
        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch.object(run_tests.subprocess, "run", return_value=imported):
            results = Path(tmp, "summary.json")
            code = self.run_main(results, check_isolation=mock.Mock(return_value=None))
            self.assertEqual(code, 1)
            summary = json.loads(results.read_text(encoding="utf-8"))
            self.assertIn("Cannot import x.png", summary["setup_error"])


class LoadConfig(unittest.TestCase):
    def test_unknown_suites_and_missing_reasons_are_errors(self):
        text = ('[skip]\nghost = "gone"\nreal = " "\n[serial]\nspecter = "timing"\nreal = ""\n'
                '[expected_errors]\nphantom = ["x"]\n')
        self.assertEqual(len(run_tests.load_config(["real"], text).errors), 5)

    def test_committed_config_matches_the_suites_on_disk(self):
        self.assertEqual(run_tests.load_config(run_tests.discover()).errors, [])


class Discover(unittest.TestCase):
    def test_finds_top_level_and_nested_suites_but_not_helpers(self):
        suites = run_tests.discover()
        self.assertIn("runner_logic", suites)
        self.assertIn("assets/a1_check", suites)
        self.assertNotIn("support/armed_measure", suites)  # extends RefCounted: a helper, not a suite


if __name__ == "__main__":
    unittest.main()
