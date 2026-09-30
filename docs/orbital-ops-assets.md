# Orbital Ops — asset pass

Created September 30, 2026 from the GDD's Platformer Game and Main Menu sections, the technical baseline, Agent Context, and existing Bay Area style reference.

The pack is in `hoppys-adventure-arcade/Assets/orbital-ops-assets-only/`. Start with its `README.md`, `ASSET_GUIDE.md`, `preview.html`, and rendered `orbital-ops-preview.png`.

Delivered: 88 new frames, 56 named states in five SpriteFrames resources, two separated background plates, individual frames, GIF previews, manifests and generation prompts. The station kit includes the foreground strut and independent ring for menu parallax. The Deprecated API has art for a cannon, stalled slam, glitch dash, exposed-core recovery, hurt and defeat. These moves and timing proposals await gameplay implementation.

All resources passed `tests/orbital_assets.gd` in Godot 4.7.1. Run with `--headless` for validation or without it to regenerate the staging render; use `--log-file /tmp/orbital-assets.log` in restricted environments. Mechanical pack rebuild uses `tools/build_orbital_asset_pack.py` with Pillow and NumPy.

No existing gameplay/menu routes were changed. Orbital Ops remains unavailable to play until its level and gameplay are implemented. Shared Hoppy, pickups, HUD and MERGE exit remain in the Bay Area pack. This session did not change approved game mechanics or the baseline's open decisions.
