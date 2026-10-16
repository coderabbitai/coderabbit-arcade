# Asset licenses

The [MIT License](LICENSE) covers the source code. The tables below list the license that applies to each bundled asset. CodeRabbit names and the Hoppy mascot are covered by [TRADEMARKS.md](TRADEMARKS.md).

Paths are relative to `hoppys-adventure-arcade/Assets/`. Every new asset needs a row here; see [CONTRIBUTING.md](CONTRIBUTING.md#assets).

Status key: ✅ verified · ⚠️ needs sign-off · ❌ **blocks public release**

## Third-party

| Asset | Path | Creator | License | Used by | Status |
|---|---|---|---|---|---|
| The Essential Retro Video Game Sound Effects Collection | `Audio/The Essential Retro Video Game Sound Effects Collection [512 sounds] By Juhani Junkala/` | Juhani Junkala | CC0 (`INFO.txt`) | SFX | ✅ |
| Sunny Land forest (art, demo SFX) | `Backgrounds/Sunny-land-forest-files/` | Luis Zuno (@ansimuz); music by Pascal Belisle | Art: public domain. Music: free with credit (`public-license.txt`). The bundled `demo/phaser.min.js` is MIT. | Platformer jump/hurt SFX | ✅ |
| Parallax forest | `Backgrounds/parallax_forest_pack/` | Luis Zuno (@ansimuz) | CC0 (`license.txt`) | Main menu preview | ✅ |
| Space background | `Backgrounds/space_background_pack/` | Luis Zuno (@ansimuz) | CC0 (`license.txt`) | Main menu preview | ✅ |
| City skyline | `Backgrounds/background_city_skyline/` | Fábio | CC0 (`Read.txt`) | Not referenced | ✅ |
| Cyberpunk Street (layers + BGM) | `Backgrounds/cyberpunk-street-files/` | Luis Zuno ([ansimuz.com](https://ansimuz.itch.io/cyberpunk-street-environment)); music composer not credited | CC0 (bundled `public-license.pdf` covers the whole package, music included). An older OpenGameArt listing says CC BY 3.0, so we credit "ansimuz.com" anyway. | Main menu preview, runner BGM | ✅ |
| Parallax City Night | `Backgrounds/CityBackground/` | FisherG (@TheFish523); "Ghost (Vibrant)" palette by PixelCod | CC0 ([OpenGameArt](https://opengameart.org/content/parallax-city-night-4-colors), byte-identical) | Main menu preview | ✅ |
| MERGE SUCCESSFUL jingle and victory loop | `Audio/Beat'em Up/code_city_victory_jingle.wav`, `code_city_victory_loop.wav` | Original project compositions and square-wave synthesis; no third-party samples | CC0 1.0. The project dedicates these compositions and recordings to the public domain under the [CC0 1.0 Universal dedication](https://creativecommons.org/publicdomain/zero/1.0/). Deterministic source: `tools/build_code_city_victory_music.py`; build and playback notes: `docs/soundtrack.md`. | Code City Brawl: celebration, ending pages and results | ✅ |
| Hero Immortal | `Audio/Beat'em Up/Hero vs Villian/Hero Immortal.mp3` | Trevor Lentz | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) ([OpenGameArt](https://opengameart.org/content/hero-immortal), byte-identical). Credit: "Hero Immortal" by Trevor Lentz. Preserve ShareAlike terms for adaptations. | Heroes vs. Villains: Generation Floor | ⚠️ source verified; license-policy sign-off |
| 8-bit - Slay The Evil | `Audio/Beat'em Up/Hero vs Villian/8-bit_slay_the_evil.ogg` | HydroGene | CC0 ([OpenGameArt](https://opengameart.org/content/8-bit-slay-the-evil), byte-identical). Attribution optional. | Heroes vs. Villains: AI SLOP | ✅ |
| Frivolous Hero | `Audio/Beat'em Up/Hero vs Villian/frivolous_hero.ogg` | Alexandr Zhelanov | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) ([OpenGameArt](https://opengameart.org/content/frivolous-hero), byte-identical). Credit: "Frivolous Hero" by Alexandr Zhelanov; retain the supplied [creator link](https://www.youtube.com/channel/UCxmng6_DMIayDwkiWGVzVRQ?view_as=subscriber) and contact totalnomus@gmail.com. | Heroes vs. Villains: Review Gauntlet | ✅ |
| Dramatic Boss Encounter (Heavy Concept A Bass Master) | `Audio/Beat'em Up/Hero vs Villian/Heavy Concept A Bass Master.wav` | cynicmusic | CC0 ([OpenGameArt](https://opengameart.org/content/dramatic-boss-encounter), byte-identical). Supplied credit links: [cynicmusic.com](http://cynicmusic.com), [pixelsphere.org](http://pixelsphere.org). | Heroes vs. Villains: Coding Agent Army / PR | ✅ |
| synthwave type remixed (synth_type_mix2) | `Audio/Beat'em Up/Hero vs Villian/synth_type_mix2.ogg` | glitchart; source tracks by G_P, tricksntraps and vitalezz | CC0 for this version ([OpenGameArt](https://opengameart.org/content/synthwave-type-remixed-gp-vs-vitalezzz-vs-tricksntraps-vs-zodik), byte-identical). The author explicitly permits CC0 for the original mix without Zodik's "Low Pridox"; the page-wide CC BY 3.0 applies to the added Low Pridox version. | Heroes vs. Villains: Agentic Core | ✅ |
| Lord of Zorg I | `Audio/Beat'em Up/Hero vs Villian/Zodik - Lord of Zorg I.ogg` | Zodik | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) ([OpenGameArt](https://opengameart.org/content/zodik-lord-of-zorg-i), byte-identical). Credit: "Lord of Zorg I" by Zodik. | Heroes vs. Villains: AI-Augmented Hacker | ⚠️ source verified; license-policy sign-off |

### Audio verification — 2026-10-09

Checked all 12 supplied OpenGameArt pages and compared the corresponding downloads with the local files using SHA-256; all 12 are byte-identical. Also located and checksum-matched `tipa16.mp3` to **moon chime** (CC0), resolving its previous unknown-source blocker. `Boss Fight 2.mp3` was missing from this table and is now listed. Runtime references place **Valor of Heroes** in Orbital Ops, not Code City Brawl; **Boss Fight 2** now plays during Code City Brawl's Stack Overflow and Zero-Day district-boss fights via `Catalog.MINI_BOSS_MUSIC`.

The audio inventory is covered by the individual tracks and pack rows above, plus the eight project-original Heroes vs. Villains cues below. No additional unidentified audio files were found. Existing pack verifications are retained; this pass does not re-establish their earlier byte-match claims.

Remaining follow-up:

- **License-policy sign-off:** [CONTRIBUTING.md](CONTRIBUTING.md#assets) accepts CC0 or CC BY 4.0. Lord of Zorg I uses CC BY 3.0; Hero Immortal uses CC BY-SA. Their sources are verified, but those two tracks need an explicit policy exception or replacement before release. Future Travel, The Final and Angel Eyes (Vision II) were replaced by original music for Code City Brawl, and Valor of Heroes by original music for Orbital Ops.
- **Redistribution blockers:** `04 - Silent Forest.mp3` and `05 - Battle 1.mp3` were removed from the current tree, and The Enchanted Repo now plays original music listed under [Project-original](#project-original). Earlier commits still contain both files, so the history needs rewriting before a public release.
- **Notices and release credits:** ✅ verifies source/license, not completion of release packaging. The newly verified music has no adjacent upstream license files in the checkout. Preserve the applicable upstream notices/license copies next to the assets per CONTRIBUTING.md, including the synth mix's version-specific CC0 grant, and ship the required author/title, source and license links with distributions. Record any later modifications; the 13 checksum-matched files were unmodified at this check. For ShareAlike tracks, preserve the applicable license for adaptations and review the intended game distribution before sign-off; this pass does not change the MIT source-code license.

## Project-original

These assets were made for this project, either by hand, by procedure, or with image generation (prompts are recorded in each pack's `PROMPTS.md` / `generation.json`). They are distributed under the [project asset terms — TODO: legal to choose, e.g. CC BY 4.0]. The Hoppy character remains a CodeRabbit trademark.

| Asset | Path | Notes | Status |
|---|---|---|---|
| Hoppy 2D sprite pack | `Character/Hoppy/2D/hoppy-sprite-pack/` | Generated from internal comic references | ⚠️ brand sign-off |
| Hoppy brawler combat supplement | `code-city-brawl-player/` | Image generation; exact combat and victory prompts in `PROMPT.md`, untouched masters `source.png` and `victory-source.png`, reproducible atlas packing in `tools/build_hoppy_brawler.py` | ⚠️ brand sign-off and project asset terms |
| Hoppy armed supplement | `hoppy-armed/` | Built-in image generation; exact prompts in each mode's `PROMPTS.md` / `refinements.json`, untouched masters in `sources/`, deterministic packing in `tools/build_hoppy_armed.py`. See its [`README.md`](hoppys-adventure-arcade/Assets/hoppy-armed/README.md). | ⚠️ brand sign-off and project asset terms |
| Beat'em-up story illustrations | `beatemup-story/` | Built-in image generation; exact prompts and regeneration history in `refinements.json`, untouched masters in `sources/`, deterministic packing in `tools/build_story_scenes.py`. | ⚠️ brand sign-off and project asset terms |
| "Send in the Rabbit" theme | `Audio/Main Menu/` | Music by Erik Thorelli, made with Suno v6 for this game. Erik holds the rights and grants their use in the game and in this repository. Lyrics, prompts, Suno song ID, stems used, loop points and delivery steps in `PROMPTS.md`. | ✅ |
| The Enchanted Repo music | `Audio/Platformer/The Enchanted Repo/` | Music by Erik Thorelli, made with Suno v6 for this game. Erik holds the rights and grants their use in the game and in this repository. Prompts, Suno song IDs, loop points and delivery steps in `PROMPTS.md`. | ✅ |
| Code City Brawl music | `Audio/Beat'em Up/code_city_*.ogg` | Music by Erik Thorelli, made with Suno v6 for this game. Erik holds the rights and grants their use in the game and in this repository. Prompts, Suno song IDs, loop points and delivery steps in `Audio/Beat'em Up/PROMPTS.md`. | ✅ |
| Bay Area Blitz music | `Audio/Platformer/Bay Area Blitz/` | Music by Erik Thorelli, made with Suno v6 for this game. Erik holds the rights and grants their use in the game and in this repository. Prompts, Suno song IDs, loop points and delivery steps in `PROMPTS.md`. | ✅ |
| Orbital Ops music | `Audio/Platformer/Obital Ops/` | Music by Erik Thorelli, made with Suno v6 for this game. Erik holds the rights and grants their use in the game and in this repository. Prompts, Suno song IDs, loop points and delivery steps in `PROMPTS.md`. | ✅ |
| Hoppy 3D mascot | `runner/hoppy/` | Built by `tools/blender/build_hoppy.py` | ⚠️ brand sign-off |
| Platformer stage-clear stinger | `Audio/Platformer/stinger_stage_clear.ogg` | Music by Erik Thorelli, made with Suno v6 for this game. Erik holds the rights and grants their use in the game and in this repository. Prompt, Suno song ID and edit in `Audio/Platformer/PROMPTS.md`. | ✅ |
| Runner props, previews and procedural assets | `runner/` | See [`runner/LICENSES.md`](hoppys-adventure-arcade/Assets/runner/LICENSES.md) | ✅ |
| Bay Area Blitz pack | `bay-area-blitz-assets-only/` | Image generation | ⚠️ confirm the generator's terms allow redistribution |
| Orbital Ops pack | `orbital-ops-assets-only/` | Image generation | ⚠️ same |
| Enchanted Repo pack | `enchanted-repo-assets-only/` | Image generation | ⚠️ same |
| Code City Brawl pack | `code-city-brawl-assets-only/` | Image generation | ⚠️ same |
| Heroes vs. Villains pack | `heroes-vs-villains-assets-only/` | Built-in image generation; exact prompts and masters included. Locomotion supplement prompts in `LOCOMOTION.md`, packed by `tools/build_heroes_villains_locomotion.py`. Eight original synthesized cues generated by `tools/build_heroes_villains_sfx.py`; no third-party samples. | ⚠️ brand sign-off and project asset terms |

## Removed before public release

These packs were removed because their licenses forbid redistribution or couldn't be verified. None of them was referenced by the game:
- Free Pixel Art Forest (no redistribution)
- `Forest_layer_full.psd`
- `city_parallax_background_with_buildings_pixel_art`
- `Forest - Backgrounds`
- `free-scrolling-city-backgrounds-pixel-art`
- `Color Palletes`
- the nested `SynthCitiesGodot` demo project
