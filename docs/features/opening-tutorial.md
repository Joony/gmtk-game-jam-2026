# Opening tutorial — the first fault teaches the loop

The run already opens on a fault that is broken before the player is awake. The tutorial is
that fault. Find it, and the ship's computer tells you the two ways to fix anything on board:

> "You're gonna need a spare part to fix that thingamajig there. It should be around here
> somewhere. Or you can use that hammer to patch it temporarily. You'll figure it out."
>
> — `CD_Thingamajig`, already recorded

One line, and it covers the spare-part route, the hammer patch, and the tool. That is the whole
repair economy. There is no tutorial mode, no text box and no separate first level.

## The cue is arriving in the room, not the fault firing

Three moments were available and only one of them works.

**Told from inside the pod**, the instruction is abstract: there is no thingamajig in front of
you, no hammer, nothing to look at. It is a sentence about a mechanic rather than a thing to do.

**Told on a timer**, it fires whether the player found the room or not — so the one player who
wandered the wrong way gets the explanation with nothing in view, and the one who walked
straight there gets it before or after the moment it would have landed.

**Told on arrival**, the thing being described is in the room. That is the version that is
built.

There is also nothing else it could hang off. `RunState.start()` calls `break_now()` on a
`starts_broken` fault **before** connecting the `alarm` signal — deliberately, so the cold open
is silent and the fault is simply already true when the player wakes. An opening fault never
announces itself, so there is no alarm event to trigger a line from, and no second voice to
suppress either.

## RoomVoice

`scripts/game/room_voice.gd`. A `room id -> voice line` table; walk into a room for the first
time and it says that room's line, once per run.

**It is not an `Area3D`.** The rooms are authored in code and built at runtime by `RoomBuilder`,
so there is no editor-time box to attach a trigger to, and a hand-placed trigger volume would
have to be re-synced by hand every time the ship drawing is redrawn. Instead it asks
`RoomBuilder.room_at(position)` which room a world point is in — reading the same rects the
geometry itself was built from, so it cannot drift.

Two details that are load-bearing:

- **A doorway margin (0.6 m).** A doorway sits *on* the shared wall line between two rooms.
  Without a margin, a player loitering in one flips between the two rooms every frame and burns
  the cue on a near-miss. A room only counts as entered once you are properly inside it.
- **The computer is resolved by node path**, not through the `Audio` global. A `-s` test script
  loads its dependencies before the autoloads register, so a compile-time `Audio` reference
  fails with "Identifier not found" the moment a suite does `RoomVoice.new()` — even though the
  same reference is fine in `game.gd`, which is loaded later as part of a scene.

It emits two signals, and the difference matters for testing: `room_changed` fires on every
crossing, `spoke` only when a line is actually said. A test that listens to the first one counts
walks rather than utterances and can never catch a cue repeating.

## The cue follows the fault, and no code names a room

`Game._wire_room_voice()` builds the `RoomVoice` in code and aims it by **looking up whichever
`Malfunction` carries `starts_broken`** and asking which room that fault is in.

This was originally a workaround — `scenes/game.tscn` was locked for editing elsewhere, so the
opening fault could not be moved to where the tutorial wants it — but it is the right design
regardless. Moving the fault in the scene moves the lesson with it, with no code change and
nothing to keep in sync. If nothing starts broken there is no tutorial and the table is empty,
which is better than a line said in an arbitrary room.

The `RoomVoice` node itself is built in code for the same reason, and stays that way: it has
nothing to configure that is not derived at runtime.

## Tests

| Suite | What it owns |
| --- | --- |
| `tests/smoke_room_voice.gd` | The **trigger**. Builds its own two-room ship rather than loading `game.tscn`, so a test about a trigger is never decided by whatever furniture is in the scene this week. Point-to-room lookup, an untagged room stays silent, loitering in a doorway does not burn the cue, entering speaks, re-entering does not repeat, `reset()` re-arms. |
| `tests/smoke_tutorial_cue.gd` | The **aim**, against the real scene. Something starts broken; it is inside a room; the one cue is on *that* room whatever room it is; the cold open and the wake stay silent; walking in says it; it never repeats. |

`smoke_tutorial_cue` deliberately does not name a room. Hard-coding `bridge` would turn a suite
about the tutorial into a suite about where the fault currently sits, and it would go red the
moment the fault moves — which is precisely the change the wiring exists to survive.

Both are mutation-tested: dropping the once-only guard, zeroing the doorway margin, never
building the `RoomVoice`, and nailing the cue to a fixed room id each fail the suites.

### Gotcha found while testing

A repair panel is mounted flush on a wall, so **the fault's own position is only a few
centimetres inside its room** — inside the doorway margin, and correctly not counted as having
entered anything. In play this never bites: the player walks into the room and then up to the
panel, never standing inside the wall it is bolted to. But a test that teleports to the fault's
exact coordinates sees no cue and looks like a broken trigger. `smoke_tutorial_cue` stands in
the room's centre instead.

## Outstanding

The placement half is a `scenes/game.tscn` edit and is parked in TODO 18d: move the opening
fault to the bridge (NAV ARRAY, which is currently sitting in the cryo bay), put the hammer on
the floor beside it, and rehome the `need_oil` line to the cargo-bay crawlers.

The bridge is the right room for it — it is the hub, so every trip out of the pod passes through
it, and it is ~16.5 m from the pod against the engine room's 63.5 m. And the hammer beside it is
the **same** hammer, not a second one: picking it up there is how you learn the tool exists, and
thereafter it lives wherever you last put it down, which keeps the cost the janitor's-closet
placement was for.
