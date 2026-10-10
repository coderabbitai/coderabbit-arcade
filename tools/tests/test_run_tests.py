"""Unit tests for run_tests.py's discovery, configuration checks and failure detection."""
import re
import unittest

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
