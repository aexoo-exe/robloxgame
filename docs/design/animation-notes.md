# Animation Notes

A running list for raising animation quality, the user's top concern. Claude keeps it: anything seen
while judging a replay goes in **Seen**, ideas for the pose system in **System**, and the next
concrete step in **Plan**. Unit ids only.

Tick an item when it's done; add the commit next to it.

## How bodies move today

Units are anchored parts placed every frame from pose channels (`PoseAnimator`, `UnitMotion`,
`Figure.place`), not a Motor6D rig. A pose is a set of channel values (arms forward / out per side,
legs forward per side, lean, twist, tilt, spin, crouch, head pitch / yaw / roll, tremble, plus
`lunge` / `rise` for visual travel), eased key to key. That keeps every unit (catalog avatars,
store models, hand-built looks) on one path, but it limits how expressive a pose can be.

## System (what limits quality)

- [ ] **No elbows, wrists or hands.** Each arm is one straight swing (forward / out). No bent-arm
      guard, no cocked wrist for a flick, no open palm vs fist. Biggest single limit for casters and
      brawlers. Idea: an `elbow` channel per arm (bend at the forearm), and a hand pose (open / fist /
      point) where the avatar's parts allow it.
- [ ] **No knees.** Legs swing as one piece: crouches read as "squatting on stilts", kicks and
      landings can't fold. Idea: a `knee` channel per leg, driven by `crouch` by default.
- [ ] **One torso piece.** `lean` / `twist` bend the whole upper body at the hips; there's no chest
      vs hips split, so wind-ups can't twist the shoulders against the hips (the core of a strong
      throw, punch or swing). Idea: `chestTwist` / `chestLean` on top of the hip ones.
- [ ] **No overlap / follow-through for free.** Every channel in a key arrives at the same moment,
      so motion looks stiff and robotic unless each module staggers keys by hand. Idea: per-channel
      lag in PoseAnimator (head and arms trail the torso by 0.03-0.06 s, settling with a small
      overshoot), on by default.
- [ ] **No secondary motion.** Hair, coats, capes, tails and weapons don't swing or settle after a
      big move. Idea: a spring on accessory / prop parts driven by the root's acceleration.
- [ ] **No squash and stretch or smear frames.** Snaps (0.06 s) jump from pose to pose; at 60 fps
      that's 3-4 frames with nothing selling the speed. Idea: a one-frame stretch along the motion
      on the snap, or a smear trail (kitSmear exists) on the fastest limb.
- [ ] **Straight-line interpolation in channel space.** Fine for single arm swings, but a hand
      travelling from the hip to over the head doesn't follow a clean arc. Idea: an optional arc
      (overshoot curve) on big arm moves.
- [ ] **Weight and contact.** Feet don't plant: `lunge` slides the whole figure, so dashes and
      recoveries read as gliding. Idea: step keys (one leg forward, then the other) during lunges,
      and a heel-plant pose on landings.
- [ ] **Idle and hit reactions are generic.** The same idle and stagger for every unit. Personality
      per unit (a bored slouch, a fighter's bounce) would sell character before any ultimate.

## Seen (per unit)

- **infinite_collapse** (2026-10-27): no mid-ultimate frames captured yet (see Tooling). What the
  module asks for that the rig can't show: a cocked wrist on the load and a snapping wrist on the
  flick (no wrist channel); hands slamming together at the merge read only as two arms crossing in
  front (no elbows).

## Tooling (to judge animation at all)

- [ ] **Frame-accurate captures through the MCP.** At 1x the screenshot round trip (~2-4 s) misses
      every beat, and two captures timed out mid-effects. Freezing with O works for the effects, but
      the slice camera's real-time "leave" timer fires while frozen and the view goes black. Fix in
      DevLineup: a QA call `sliceAt(designTime)` that plays the slice to that design time and holds
      it (the stage clock, the effects and the slice camera's timers all paused), so each beat can be
      captured on purpose.
- [ ] **Pose-only replay.** A key that plays the ultimate's poses with effects off (V hides kit
      textures only), to judge the body without the VFX covering it.

## Plan

1. DevLineup `sliceAt(designTime)` (Tooling, first item): without it Claude can't judge animation
   in Studio.
2. PoseAnimator per-channel lag (overlap) with a default per channel: the cheapest broad win, every
   ultimate gets it.
3. Elbow and knee channels in UnitMotion / Figure (check which avatar parts can bend: catalog
   avatars are R15-like parts, so a forearm / shin split is possible; store models may not be).
4. Re-pose cinder_arc, flashline and infinite_collapse with the new channels as the reference set,
   then update the playbook's pose rules.
