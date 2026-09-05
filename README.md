# Kick Rotation

Shows the group's current kick-rotation number in a red box above every
raid-marked nameplate. The number advances when a cast on a marked mob ends
early, and resets when you leave combat.

## Install

Grab the zip from the releases page and drop the `KickRotation` folder into

```
World of Warcraft/_retail_/Interface/AddOns/
```

The folder must be named exactly `KickRotation`. A "Download ZIP" straight from
GitHub produces `wow-kick-rotation-main`, which WoW will not load at all — use a
release zip, or rename the folder yourself.

## Use

Mark mobs with any raid marker. Which marker does not matter and cannot matter:
the marker index is a secret value under Midnight's addon restrictions, so the
addon can only tell that a mob is marked, never which icon it carries.

- `/kickrot 4` — set the number of kickers (default 3)
- `/kickrot mode global` — one shared number on every marked mob
- `/kickrot mode mob` — one counter per marked mob (default)
- `/kickrot reset` — start over
- Keybind under Key Bindings → AddOns → Kick Rotation

In per-mob mode each newly marked mob is handed the next start number, so two
marked mobs never open on the same kicker. They can still converge once they
start advancing — with three kickers and four marked mobs, overlap is
unavoidable. A mob's counter lives only as long as its nameplate: leave its
range and it starts over, because the nameplate token is a slot rather than a
mob and nothing more stable is readable.

Everyone who wants to see the numbers needs the addon; it sends nothing over the
wire, each client derives the same count from the same events. A client that
misses an event stays one behind until the next pull, which is why the counter
resets when combat ends.

## Troubleshooting

WoW hides Lua errors by default, so a broken command looks like nothing
happening. Run `/console scriptErrors 1` before reporting a problem.

## License

MIT
