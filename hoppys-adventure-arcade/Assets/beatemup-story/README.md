# Beat'em-up story illustrations

Six painted 16-bit cinematic scenes used by the Code City Brawl and Heroes versus Villains intros. The runtime uses the packed 1600 × 900 PNGs for a slow pan and zoom; key action is intentionally composed in the central 80 percent of each frame.

| Mode | Scenes |
|---|---|
| Code City Brawl | `code_city/under_siege.png`, `code_city/pipeline_breached.png`, `code_city/hoppy_clocks_in.png` |
| Heroes versus Villains | `heroes/situation.png`, `heroes/complication.png`, `heroes/send_in_the_rabbit.png` |

## Provenance

The untouched generated masters live under each mode's `sources/` directory. `refinements.json` holds exactly one complete record per scene: selected and retained master paths, every exact generation prompt, regeneration count and the reason for any refinement. `PROMPTS.md` is rendered from that record by the builder and must not be edited by hand.

The scenes were made with built-in image generation and need brand sign-off plus the project asset terms. Source masters are excluded from game exports. Licensing is recorded in the repository's `ASSETS_LICENSES.md`.

## Rebuild

```sh
uvx --with pillow python tools/build_story_scenes.py
```

The builder validates all six provenance records before writing anything. It center cover-crops and scales only the selected masters, then atomically replaces the six runtime PNGs, `preview.png`, `PROMPTS.md`, and this README. Re-running it from the same sources produces byte-identical output.

`preview.png` is the text-free contact sheet, in story order: Code City on the top row, Heroes versus Villains on the bottom row.
