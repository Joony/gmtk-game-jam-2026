# The low-air vignette

**Status:** done, verified (two mutations killed)
**Suite:** `tests/smoke_air_vignette.gd`

Red creep at the edges of the screen as the air runs out, pulsing faster the lower it gets. It
works peripherally — the player feels it while looking at the panel they are repairing rather
than at the gauge — and the RATE is the signal.

## It was flashing too fast, and it was worse than that

Reported as "the flashing is too fast". Two separate things were true.

**The rates were high.** 0.6 Hz at the warning threshold rising to 2.4 Hz at empty. At 2.4 Hz
the thing at the edge of vision reads as a strobe, which is the wrong feeling for suffocating —
panic rather than dread. Now **0.3 to 1.0**, close to the breathing sound's own pacing
(`AudioController` spaces breaths 3.4s down to 1.05s, about 0.3–0.95 Hz), so the two escalate in
the same register. Not synchronised to it; just the same register.

**But it was never actually pulsing at 2.4 Hz.** The phase was computed as
`sin(TAU * hz * _pulse)`, where `_pulse` is elapsed time and `hz` *rises as the air drains*.
Multiplying a changing frequency by total elapsed time means every change to `hz` moves the
whole phase term by `TAU · Δhz · _pulse`. A few minutes into a run `_pulse` is in the hundreds,
so a hz change of 0.001 between two frames throws the phase about a third of a cycle — every
frame, as the oxygen ticks down.

Measured with the old arithmetic restored: **23 peaks in 90 frames**, and frame-to-frame alpha
steps of 0.221 on a range of ~0.55. It was not a pulse at all. It was noise, and it looked like
fast flashing.

Phase is accumulated now — `_air_phase += TAU * hz * delta` — which is what smoothly frequency-
modulates a sine. The same trap applies anywhere a rate is a signal; `LightingController` and
`StatusMap` both pulse, and both should be checked against this if they ever look wrong.

## Two mistakes in the test, both instructive

**A frame count is not a clock.** The first rate assertion counted peaks over 90 frames and
assumed 60fps. Headless runs the loop flat out, so that measured nothing — and the old 0.6..2.4
rates **passed it**. It now measures peaks against accumulated `delta` and reports actual Hz;
the old rates fail at 2.50 Hz.

**Pinning the oxygen at 2% ended the run**, which stops `HUD._process` — and therefore the clock
the measurement runs against — so the sampling loop spun until the watchdog fired. It holds at
5% and re-pins every frame, because the run drains air on its own.

## Mutations killed

- phase back to `TAU * hz * _pulse` — smoothness and peak count both fail, naming 0.221 and 23.
- rates back to 0.6..2.4 — the measured rate check fails at 2.50 Hz.
