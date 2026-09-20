# Bay Area Blitz — assets only

This package matches the Hoppy sprite pack format. It contains no Godot project, scenes, scripts or editor caches.

## Add to your existing Godot project

1. Extract the ZIP.
2. Open coderabbit-arcade in Godot.
3. Copy the `bay_area` folder into your existing project’s asset folder using Finder, or drag it into the Godot FileSystem dock. Wait for the PNG imports to finish.
4. Assign a `.tres` file to an AnimatedSprite2D’s **Sprite Frames** property. Set **Texture Filter** to **Nearest**.

Keep each `.tres` next to its PNG; the animation resources use relative paths. These `.tres` files are assets, not a separate project.

## Contents

- `bay_area/`: game-ready transparent PNG sheets, SpriteFrames resources, frame manifest, and reused Hoppy platformer assets. This is the folder to copy into your project.
- `frames/`: all 108 new individual sprite frames.
- `individual/`: first-frame PNGs for each named clip/state.
- `animations/`: animated GIF previews.
- `sources/`: original generated sheets.
- `preview.html`: standalone offline animation preview.
- `bay-area-preview.png`: staged art preview.
- `ASSET_GUIDE.md`: coverage, frame sizes, pivots, animation names and integration notes.
- `PROMPTS.md`: original artwork generation prompts.

The artwork and animation timing are unchanged from the original Bay Area Blitz pack. Only packaging and import documentation were corrected.
