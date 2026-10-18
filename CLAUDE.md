# Planar Wars: notes for Claude

A real-time strategy game in **Godot 4.3** (GDScript, GL Compatibility renderer), inspired by Age of
Empires and StarCraft, with the races Phyrexia, Dominaria, Ravnica and Avishkar. It is Petr's
project; he describes features in plain language and expects them built, tested and shown with
screenshots. `README.md` is the player-facing guide and must stay accurate when gameplay changes.
`docs/HISTORY.md` has every request Petr made and what was built. Sister projects:
`PJPT1989/aether-drift`, `PJPT1989/defense-of-the-planes` and `PJPT1989/ashen-depths` (same
tooling). The web build is published on Petr's shop (`PJPT1989/tomano-collection-shop`,
`hry-planar-wars.html`, imported with its `tools/game_import.py`).

## Running and testing (cloud or Linux)
- `tools/setup_godot.sh` installs Godot 4.3 as `~/.local/bin/godot` and imports the project (the
  SessionStart hook in `.claude/settings.json` runs it in cloud sessions).
- Always run Godot with `timeout`: a script error can leave it hanging.
- `godot --headless --path . -- --simtest [--map=N --players=N --level=0..2 --minutes=N --seed=N]`
  plays AI-only matches on every map without drawing (about a minute per map) and prints the
  winner, the length, the worst step time and per-player numbers. Run it after any change to the
  rules, data or AI; every map should end with a winner well inside 40 game minutes.
- `tools/smoke_test.sh [dir]` runs `scripts/autotest.gd` under `xvfb-run` (a few minutes): menus,
  codex, a match on every map (selection, building, a fast-forwarded battle), pause, results.
  Look at the PNGs (default `/tmp/pw-shots`). A good run ends with `AUTOTEST done` and has no
  `SCRIPT ERROR`. ALSA errors, leaked RIDs and tween warnings are normal.
- `tools/net_test.sh [dir]` runs a host and a guest (ENet, headless) in one online match with bots;
  both `NETTEST t=...` lines must be identical.
- `tools/export_web.sh` builds `build/web/` (no-threads template). Test it in headless Chromium
  (Playwright is preinstalled; launch with `--use-gl=angle --use-angle=swiftshader
  --enable-unsafe-swiftshader`, plus `--disable-features=WebRtcHideLocalIpsWithMdns` for two-tab
  online tests on `index.html?pwnet=host=CODE,start=2,bot` and `?pwnet=join=CODE,bot`).
- In `--headless` runs the portraits are skipped (no frames are drawn there).

## Design
- Lore: the four planes as the sides of a war. Plane and place names are kept; unit names,
  characters, models and text are original. Never copy card art, card text, character names or
  Wizards assets.
- The template is the core idea Petr asked for: `Data.UNITS`, `Data.BUILDINGS`, `Data.TECHS` are
  shared; each race in `Data.RACES` has names for them, `missing` (what it lacks), `mods`, a bonus
  and a unique technology. Keep every race lacking a few things and keep the Codex in sync.
- `Sim` is the whole match without drawing, stepped at 10 Hz (`Sim.STEP`); everything changes it
  through `Sim.command(player, cmd)` (local player, AI and guests alike). `View` interpolates.
  Grid of 80x80 cells of 2 m, `AStarGrid2D` paths, buildings occupy cells.
- Online (`scripts/net.gd`, autoload `Net`): the host runs the Sim and the AI; guests have a
  mirror Sim (`sim.mirror`) filled from compressed binary snapshots (`Net.pack/apply`, ten a
  second) and send commands by RPC. New fields that the view or HUD read on a guest must be added
  to the snapshot. Signalling in the browser: `tools/web/planar-net.js` (rooms "pw-CODE" on the
  shop's `window.AetherSignal`, else a BroadcastChannel). Desktop uses ENet on port 24690.
- Everything visual is generated from code: `MeshKit` with vertex colours; units and buildings use
  `Game.mat_unit`/`mat_unit_gloss` (`shaders/unit.gdshader`), where magenta marker colours become
  the team colour from the MultiMesh custom data. In the Compatibility renderer a MultiMesh with
  custom data must also use instance colours (set to white) or COLOR comes out black.
- Ground vertex colours are sRGB (the ground shader squares them).
- Quality (`Game.quality`, L key, `user://settings.cfg`): as in the sister games.

## Code conventions
- GDScript with tabs, static types where the surrounding code has them, `##` doc comment at the top
  of each script. Data in `const` dictionaries near the top of the script that owns it. Nodes are
  built in code; `scenes/main.tscn` only holds `Main`.
- Web fonts have no fallback: use plain ASCII in titles and buttons.
