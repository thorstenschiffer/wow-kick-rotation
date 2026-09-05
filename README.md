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
- `/kickrot me 2` — your own position in the rotation
- `/kickrot spell Mind Freeze` — your interrupt, by name or ID
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

## Setup: none

At a ready check every client with the addon announces itself, all of them sort
the same names, and each derives the same assignment — positions 1..N and the
kicker count — without anyone typing anything. The chat list also shows who does
*not* have it, which is easier to notice before the pull than during it.

The ready check has to happen before the key is started: addon messaging is
locked down while a run is underway, and the addon says so rather than failing
quietly.

Your interrupt is found from a per-class candidate table, filtered through
`C_SpellBook.IsSpellKnown` so only a spell you actually have can match. Someone
with the addon but no interrupt — a healer, say — is listed but gets no number
and is not counted.

If the table misses a spell, that player falls back to learning it: a cast of
theirs coinciding with a mob's cast ending is a candidate, and two sightings
lock it in. So a wrong or missing ID costs a little time, not correctness.
`/kickrot me` and `/kickrot spell` remain as manual overrides.

## Personal feedback

The box on a mob whose number is yours turns green when your interrupt is ready and grey with a cooldown sweep
when it is not, and its border flashes when your interrupt lands.

Your own cooldown is readable even inside a key: `isActive` on
`C_Spell.GetSpellCooldown` is flagged NeverSecret, so ready-or-not is a decision
the addon is allowed to make. The remaining numbers may be secret, but
`Cooldown:SetCooldown` accepts secrets, so the sweep still draws.

Nobody else's cooldown can be shown. Theirs is secret, and asking them over
addon comms is not possible either — messaging is locked down while a key is
underway.

## Troubleshooting

WoW hides Lua errors by default, so a broken command looks like nothing
happening. Run `/console scriptErrors 1` before reporting a problem.

## License

MIT
