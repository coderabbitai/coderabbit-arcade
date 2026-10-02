# Asset licenses

The [MIT License](LICENSE) covers the source code. The tables below list the license that applies to each bundled asset. CodeRabbit names and the Hoppy mascot are covered by [TRADEMARKS.md](TRADEMARKS.md).

Paths are relative to `hoppys-adventure-arcade/Assets/`. Every new asset needs a row here; see [CONTRIBUTING.md](CONTRIBUTING.md#assets).

Status key: ✅ verified · ⚠️ **must be verified before public release**

## Third-party

| Asset | Path | Creator | License | Used by | Status |
|---|---|---|---|---|---|
| The Essential Retro Video Game Sound Effects Collection | `Audio/The Essential Retro Video Game Sound Effects Collection [512 sounds] By Juhani Junkala/` | Juhani Junkala | CC0 (`INFO.txt`) | SFX | ✅ |
| Sunny Land forest (art, demo SFX) | `Backgrounds/Sunny-land-forest-files/` | Luis Zuno (@ansimuz); music by Pascal Belisle | Art: public domain. Music: free with credit (`public-license.txt`). The bundled `demo/phaser.min.js` is MIT. | Platformer jump/hurt SFX | ✅ |
| Parallax forest | `Backgrounds/parallax_forest_pack/` | Luis Zuno (@ansimuz) | CC0 (`license.txt`) | Main menu preview | ✅ |
| Space background | `Backgrounds/space_background_pack/` | Luis Zuno (@ansimuz) | CC0 (`license.txt`) | Main menu preview | ✅ |
| City skyline | `Backgrounds/background_city_skyline/` | Fábio | CC0 (`Read.txt`) | Not referenced | ✅ |
| Cyberpunk Street (layers + BGM) | `Backgrounds/cyberpunk-street-files/` | Luis Zuno (@ansimuz) | CC0 (`public-license.pdf`). The PDF doesn't name the music's composer. | Main menu preview, runner BGM | ⚠️ confirm the music license on the source page |
| City background layers | `Backgrounds/CityBackground/` | Unknown | Unknown (no license file) | Main menu preview | ⚠️ find the source, or replace it |
| Main menu theme | `Audio/Main Menu/happy_adveture.mp3` | Unknown | Unknown | Main menu | ⚠️ |
| Bay Area Blitz music | `Audio/Platformer/Bay Area Blitz/Summer Sunday.wav`, `c64_uptempo_chiptune.ogg` | Unknown | Unknown | Bay Area Blitz | ⚠️ |
| Orbital Ops music | `Audio/Platformer/Obital Ops/Valor of Heroes.mp3`, `tipa16.mp3` | Unknown | Unknown | Orbital Ops | ⚠️ |
| Enchanted Repo music | `Audio/Platformer/The Enchanted Repo/04 - Silent Forest.mp3`, `05 - Battle 1.mp3` | Unknown | Unknown | Enchanted Repo | ⚠️ |

## Project-original

These assets were made for this project, either by hand, by procedure, or with image generation (prompts are recorded in each pack's `PROMPTS.md` / `generation.json`). They are distributed under the [project asset terms — TODO: legal to choose, e.g. CC BY 4.0]. The Hoppy character remains a CodeRabbit trademark.

| Asset | Path | Notes | Status |
|---|---|---|---|
| Hoppy 2D sprite pack | `Character/Hoppy/2D/hoppy-sprite-pack/` | Generated from internal comic references | ⚠️ brand sign-off |
| Hoppy 3D mascot | `runner/hoppy/` | Built by `tools/blender/build_hoppy.py` | ⚠️ brand sign-off |
| Runner props, previews and procedural assets | `runner/` | See [`runner/LICENSES.md`](hoppys-adventure-arcade/Assets/runner/LICENSES.md) | ✅ |
| Bay Area Blitz pack | `bay-area-blitz-assets-only/` | Image generation | ⚠️ confirm the generator's terms allow redistribution |
| Orbital Ops pack | `orbital-ops-assets-only/` | Image generation | ⚠️ same |
| Enchanted Repo pack | `enchanted-repo-assets-only/` | Image generation | ⚠️ same |
| Code City Brawl pack | `code-city-brawl-assets-only/` | Image generation | ⚠️ same |

## Removed before public release

These packs were removed because their licenses forbid redistribution or couldn't be verified. None of them was referenced by the game:
- Free Pixel Art Forest (no redistribution)
- `Forest_layer_full.psd`
- `city_parallax_background_with_buildings_pixel_art`
- `Forest - Backgrounds`
- `free-scrolling-city-backgrounds-pixel-art`
- `Color Palletes`
- the nested `SynthCitiesGodot` demo project
