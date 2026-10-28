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

- **infinite_collapse** (2026-10-27, 5 held beats from the default slice camera, behind him):
  - The "arms spread far apart" set read as both hands together in front: 90 forward + 85 out only
    rolls a forward arm (`Figure.luau` turns `Out` about the front axis outside the forward raise).
    Fixed to 15 / 85; now a playbook rule. Every older ultimate with big forward + big out on the
    same arm likely has the same bug: worth a sweep (grep the modules for both > 60).
  - Orbs too small to read at the slice camera (0.25-0.75 studs); raised to 0.4-1.1.
  - The flying sphere and the hit core read as plain white, not violet: neon light colors wash out.
    Use the saturated color for neon cores, the light tint only for halos.
  - The game's own shield bubble plus an added shimmer hid him at the erasure and through the
    recovery; the shimmer is gone, but the bubble (CombatPlayback) still covers him for its whole
    duration: a system-level look item (thinner, more transparent, or a rim only).
  - At the erasure every target flashes plain white (the generic hit flash and stun): the cast's
    color loses to it. System idea: tint the hit flash with the attacker's color.
  - The flick reads (arm whipped out at the targets). The hand-in-pocket recovery doesn't: no
    elbow, so it's just an arm hanging down.
  - Not seen: the wrist cock on the load and the wrist snap on the flick (no wrist channel); the
    hands slamming together at the merge (no elbows).

- **flashline** (2026-10-28, held at the draw +0.03 from front34 and side): the dash's lightning
  bolts are huge camera-facing sprites (taller than the frame from the side, a yellow haze over a
  quarter of it from the front), covering ~40% of the screen. Breaks the quality bar; fix before
  judging its draw pose, which is hidden under them. front34 is the wrong view for dashers (they
  dash toward that camera).
  Fixed in `VfxRecipe.kitBolts` (all lightning units): a path longer than 3 studs is a zigzag chain
  of short, narrower bolts. Seen in Studio: a row of crisp gold strands along the dash, nothing
  covering the screen. Leftover: each strand stands across the path (the bolt art's orientation,
  as before), not along it.
- **starless_burst** (2026-10-28): the staff thrust reads (the head tips forward at the target).
  The upright circle never read from the match camera (edge-on) and the first beam was a white bar:
  fixed (ground circle, thin beam), not re-captured.

## Tooling (to judge animation at all)

- [x] **Hold the slice at one beat.** DevLineup QA `hold(beat, offset?, mode?)` replays the slice
      slowed and stops it the moment the ultimate reaches a plan beat or design time; the slice
      camera's leave timer now counts stage seconds and waits out freezes (`feature/devlineup-hold`,
      859ee5c). Held exactly on the beat in Studio (asked "red +0.2", held at -0.831 s).
- [x] **Black screenshots.** Not the freeze: Studio was minimized, and a minimized window draws
      nothing. Before a capture session, check the window (`IsIconic`) and restore it without focus
      (`ShowWindow(handle, 4)`, SW_SHOWNOACTIVATE); the user approved doing this (2026-10-27).
- [x] **A side / front camera for holds.** `hold(beat, offset, "side" | "front34" | "back34")`
      (`feature/hold-views`). Front 3/4 confirmed infinite_collapse's spread fix in Studio: facing
      the camera, arms wide, an orb at each hand.
- [ ] **Pose-only replay.** A key that plays the ultimate's poses with effects off (V hides kit
      textures only), to judge the body without the VFX covering it.

## Plan

1. Sweep cinder_arc and flashline for the forward + out arm bug (judge with `hold` from front34).
   Candidates (forward >= 60 and |out| >= 50 on one arm): cinder_arc STRIKE1 right (95 / -80),
   STRIKE2 right (160 / 85), FOLLOW2 right (170 / 100), FINISH left (95 / 75); flashline DRAW right
   (95 / 110: meant "swept wide to the right", likely points forward), FOLLOW right (70 / 130). For
   a sword the roll also turns the blade, so judge each in Studio before changing it (cinder_arc is
   the approved template).
2. PoseAnimator per-channel lag (overlap) with a default per channel: the cheapest broad win, every
   ultimate gets it.
3. Elbow and knee channels in UnitMotion / Figure (check which avatar parts can bend: catalog
   avatars are R15-like parts, so a forearm / shin split is possible; store models may not be).
4. Re-pose cinder_arc, flashline and infinite_collapse with the new channels as the reference set,
   then update the playbook's pose rules.
