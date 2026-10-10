# Beat'em-up story illustrations

Twelve painted 16-bit cinematic scenes used by the Code City Brawl and Heroes versus Villains intros and endings. The runtime uses the packed 1600 × 900 PNGs for a slow pan and zoom; key action is intentionally composed in the central 80 percent of each frame.

| Mode | Scenes |
|---|---|
| Code City Brawl, intro | `code_city/under_siege.png`, `code_city/pipeline_breached.png`, `code_city/hoppy_clocks_in.png` |
| Code City Brawl, ending | `code_city/merge_resolved.png`, `code_city/city_back_online.png`, `code_city/hoppy_ships_it.png` |
| Heroes versus Villains, intro | `heroes/situation.png`, `heroes/complication.png`, `heroes/send_in_the_rabbit.png` |
| Heroes versus Villains, ending | `heroes/hacker_falls.png`, `heroes/trust_restored.png`, `heroes/rabbit_stands.png` |

## Provenance

The untouched generated masters live under each mode's `sources/` directory. `refinements.json` holds exactly one complete record per scene: selected and retained master paths, every exact generation prompt, regeneration count and the reason for any refinement. `PROMPTS.md` is rendered from that record by the builder and must not be edited by hand.

The scenes were made with built-in image generation and need brand sign-off plus the project asset terms. Source masters are excluded from game exports. Licensing is recorded in the repository's `ASSETS_LICENSES.md`.

## Rebuild

```sh
uvx --with pillow python tools/build_story_scenes.py
```

The builder validates all twelve provenance records before writing anything. It center cover-crops and scales only the selected masters, then atomically replaces the twelve runtime PNGs, `preview.png`, `PROMPTS.md`, and this README. Re-running it from the same sources produces byte-identical output.

`preview.png` is the text-free 3-column by 4-row contact sheet, in story order: Code City intro, Code City ending, Heroes versus Villains intro, Heroes versus Villains ending.
