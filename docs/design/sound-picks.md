# Sound Picks

The shared sound library (`SfxConfig.library`, played with `Sfx.play("<name>")`). For each sound:
three Creator Store search terms (Toolbox > Audio, or create.roblox.com > Marketplace > Audio), what
it should sound like, and the chosen id. Audition candidates in Studio, then paste the id into
`src/shared/SfxConfig.luau` and this table. Prefer Roblox-owned or free-to-use audio; avoid anything
named after a show or character. An empty id plays nothing (silently).

Signature sounds of single units (`SfxConfig.units`, at most 2 per tier 3+ unit) get a row at the
bottom when a unit's build adds one.

| Library sound | Search terms | Should sound like | Chosen id |
|---|---|---|---|
| whooshLight | "sword swing whoosh", "fast swish", "blade swoosh" | sharp, bright, ~0.2 s, no impact in it | 74419593834838 |
| whooshHeavy | "heavy swing whoosh", "large weapon swing", "deep whoosh" | deep and full, ~0.4 s, no impact | |
| windGust | "wind gust", "air rush", "whoosh wind burst" | soft attack, ~0.6 s rush of air, fades out | |
| impactLight | "sword hit", "slash impact", "punch hit anime" | short, punchy slice-and-thud, ~0.15 s | 101309544882556 |
| impactHeavy | "heavy impact boom", "big hit boom", "cinematic hit" | deep heavy boom with a tail, ~0.8 s, the loudest | 138533090376585 |
| slashMetal | "metal slash", "sword clash", "blade cut ring" | bright metallic cut with a short ring, ~0.3 s | |
| punchRush | "punch barrage", "rapid punches", "fast hits flurry" | ~1 s of fast thuds, no single big hit | |
| groundSlam | "ground slam", "heavy thud", "stomp impact" | low thud with a crunch, ~0.5 s | |
| rockDebris | "rock debris", "rubble falling", "stones crumble" | ~0.8 s of tumbling stones, not a crash | |
| fireBurst | "fire burst", "flame whoosh", "fireball ignite" | soft "fwoomp" with crackle, ~0.6 s, not an explosion | 96009794895457 |
| fireCrackle | "fire crackle", "finger snap spark", "match strike" | small crackle or snap with a spark, ~0.4 s | |
| explosion | "explosion", "blast boom", "cartoon explosion" | punchy blast, short rumble, ~1 s | |
| lightningCrack | "thunder crack", "lightning strike", "electric zap" | sharp, dry crack with an electric snap, ~0.5 s, no long rumble | |
| electricBuzz | "electric buzz", "electricity crackle", "chirping electricity" | crackling buzz or chirp, ~0.6 s | |
| waterSplash | "water splash", "mud splash", "big splash" | splash, ~0.6 s | |
| energyCharge | "energy charge", "power up rising", "charge up" | short rising tone or scrape, ~0.4-0.8 s, ends on a held breath, no impact | |
| energyRelease | "energy release", "power blast", "magic release" | bright release with a whoosh of power, ~0.5 s | |
| magicChime | "magic chime", "bell chime", "spell cast chime" | clear tone with a soft tail, ~1 s (pitched down: a deep bell) | |
| healTwinkle | "heal sparkle", "twinkle", "magic sparkle" | soft sparkles, ~0.6 s | |
| sheathe | "sword sheathe", "blade sheath click", "katana sheathe" | blade sliding home ending on a crisp click, ~0.4 s | |

Candidate ids: none listed yet. The Studio MCP server (with audio search) was not connected when this
file was written; audition from the search terms above.

## Signature sounds

| Unit sound | Search terms | Should sound like | Chosen id |
|---|---|---|---|
| (none yet) | | | |
