# Tales of the Tumbling Dice (Godot 4)

A dice-collecting RPG told at a tavern table. An unseen storyteller, the Teller, tells you a tale, and every
deed in it is decided by real dice you own, pack and throw into a physical tray. Your Pouch of dice is your
character: no stats, no classes, only the dice you carry and what they have been through.

This build covers **milestone M1** (the rules core and The Drowned Bell, playable start to finish),
**milestone M2: dice on the table** (throwing by hand, picking dice in the tray, and the Practice Table
for the M2 playtest), **milestone M3: the tale runner** (tales as plain-text `.tale` files with a
parser and linter, a text preview for writers, mid-tale saves and the Chronicle), plus graphics presets,
and **milestone M4: the vertical slice staged** (the tale board with your figurine, carved foe figurines,
and a minimal tavern with Hollis's shelf and Brannoc the Dicewright), and **milestone M5: the campaign
skeleton** (a year of nights and seasons, two patron arcs of six tales, Renown, Standing, Rumours,
Wounds carried between tales, Sister Maud, materials, loading, rebinding and curses). Design doc: *Tales of the Tumbling Dice: Game Design* (Claude Doc).

The dice, room, flames, tale board, UI widgets and sounds are generated in GDScript and shader code.
Furniture, clutter, board landmarks and the painted miniatures come from free CC0 kits by
[Quaternius](https://quaternius.com) (Fantasy Props and Stylized Nature MegaKits) and
[Kay Lousberg](https://www.kaylousberg.com) (KayKit Medieval Hexagon, Adventurers and Skeletons),
repainted with our toon shader and ink outlines; credits and how they were imported are in
[assets/kits/README.md](assets/kits/README.md). `-- --kits=off` shows the all-code look. The fonts are
free (SIL Open Font License): Cinzel for headings and dice, and IM Fell English for the Teller's
narration (`fonts/OFL.txt`, `fonts/OFL-IMFellEnglish.txt`).

![throw](media/result_dragon.png)

## Play it

1. Download **Godot 4.7** (standard build, not .NET) from https://godotengine.org/download. Tested on 4.7.1.
2. Open Godot, click **Import**, pick this folder's `project.godot`, then press **F5**.

| Input | Action |
|---|---|
| Click | Choose, pick dice from your Hand, place dice in slots |
| Drag across the tray | Pick up the chosen dice, shake, and let go to throw. A quick flick throws hard; holding still and letting go drops them. Right-click while holding puts them back |
| Click a die in the tray | Select it while placing dice (then click a slot, or use Nudge, Reroll) |
| 1 to 9 | Select a thrown die while placing dice |
| Space | Throw (tossed in from your side of the table) |
| Enter | Confirm / continue |
| F | Fast dice: skip the physics (same odds, results drawn from each die's measured faces) |
| F4 | Show or hide the frame rate and draw calls |
| Esc | Quit |

The campaign (your dice, Coin, Chronicle, endings found) is saved to `user://campaign.json` when a tale
ends. Run with `-- --new` to start fresh. The old dice-tray sandbox is still there: `main.tscn`.

### Graphics quality

**Graphics** on the title screen cycles Low, Medium and High. The choice is saved to `user://settings.cfg`.
The first run picks Low on Android, ChromeOS, and anything using the Compatibility renderer. Everything
else starts on High. **Frame rate** on the title screen (or F4) shows the fps in the corner.

| Preset | Meant for | What changes |
|---|---|---|
| Low | Tablets and Chromebooks (Lenovo Duet class) | 3D at 60% resolution, no MSAA, no screen-space effects, no glow, no dust or embers, no painterly screen pass, cheaper shaders (no per-pixel relief, fewer noise octaves), 2048 shadow map with hard edges, 30 fps cap; the tale board casts no shadows and has thinner mist |
| Medium | A mid laptop | 85% resolution with FSR, 2x MSAA, ambient occlusion, glow, depth of field, painterly pass, 4096 soft shadows, 60 fps cap |
| High | A strong laptop or desktop | The full look: native resolution, 8x MSAA, bounced light, volumetric haze, 8192 soft shadows, no cap |

Physics runs at 120 Hz on every preset. At 60 Hz the dice measurably favour some faces (see
`tests/physics_check.gd`), and a few dice cost little next to rendering. On Android, Godot uses the
Compatibility renderer (`rendering_method.mobile`), and Low has been checked under it.

### The tale board

A parchment map lies on the table left of the dice tray. Every place in the tale is a painted tile, and
your figurine (a little hooded traveller with a lantern) is picked up and set down on the next tile as
the story moves. The camera glides to the map while you choose and back to the tray when you throw.
- Roads are inked in as you walk them. Places one road away are sketched in faint ink, and roads you
  could have taken and didn't stay faded for the rest of the tale. Everything else is under mist, which
  lifts as you arrive.
- Your choices leave tokens on the map: lit lamps in the village you saved, a grave for the fisherman
  the lake took, Kettle's flag at the cove, the bell's gold, Wren's hand-bell at the shrine, and at the
  end a beacon, a broken bell or a wave. Every foe you beat lies toppled on the tile where you fought it.
  Hover a token to read it.
- The map comes back exactly as it was when you Continue a saved tale, and the next time you tell the
  same tale, the places you walked before show washed out instead of under mist.
- Writers place tiles and tokens in the `.tale` file (`tile:`, `at:`, `token:`; see
  [docs/tale_format.md](docs/tale_format.md)). A tale without them still gets a board, laid out
  automatically.

**Foe figurines.** In a fight or a social contest, whoever you face stands behind the far wall of the
tray as a carved wooden figurine: the Mire Wolf, the Drowned, Kettle's knives, Odile, Mother Kettle, the
Drowned Abbess.

### The tavern

**Into the tavern** on the title screen (and **Back to the tavern** after a tale) pulls the camera back
into the room. Under the title is the calendar: a tale takes one night, and the season turns every
six nights (spring, summer, autumn, winter: a year is 24 nights).
- **The patrons' tables.** Wren (a fisherman's daughter) and Captain Ashgrove (a disgraced knight) each
  offer the next tale in their arc, with a line of pitch, and how long it will wait ("Before winter:
  4 nights left"). A tale that runs out goes by without you, and the Chronicle says what happened.
- **Hollis's shelf**: your whole Collection. Buy plain dice for Coin (friends of the Thieves' Guild pay
  less), sell the ones you don't need. In summer the fair brings fine dice.
- **Brannoc's bench**, the Dicewright: **recarve** (8 Coin), **inscribe** a rune from a shard (10 Coin),
  **melt** a die for its runes' shards, **mend** a cracked face (4 Coin). Bring him rare materials to earn
  his trust: at trust 1 he **loads** a d6 (Lead and 15 Coin; the face lands about 3 times in 4, and card
  sharps can tell); at trust 2 he **rebinds** a die to another aspect, once in its life (a binding and
  10 Coin; it forgets half its notches).
- **Sister Maud's corner**: treat a Wound you carried home, for Coin (6, less 2 for each point of Abbey
  standing) and a night, or for two nights' work in the infirmary. She can't lift curses, but she knows
  who can.
- **Sit by the fire tonight** lets one night pass; **Wait for autumn** skips to the next season.
- **The Chronicle**: the calendar, every tale and how it ended, missed tales, Renown, standing, rumours.

**Renown** comes from each ending (1 to 5) and raises your Pouch's weight at 3, 7, 12, 18, 25, 33, 42
and 52 (and the Saddlebag's at the third and sixth step). **Wounds** taken in a tale come home with you
(two at most) and are still on you when the next tale starts; the turning of a season mends one.
**Curses** bite on their own rules (the Bellmetal tolls at Waystones; the Oath die at setting out) and
are lifted in the tale they belong to.

### The two arcs

| Arc | Tales | What carries over |
|---|---|---|
| Wren | The Drowned Bell, The Bell Market, The Tide Court | Whether the Abbess was freed or destroyed, the bell sold or rung, the gold kept (Marrowmere floods in autumn), Ormond Vane dead or escaped. The Tide Court sits in autumn and can lift the Bellmetal's curse. |
| Captain Ashgrove | The Last Watch, The Pretender's Road, Siege of Holloway | Sergeant Brask hanged, spared or taken along, the Oath die taken at the chapel, the letter burned or kept, the bridge held or burned or the captain joining the Pretender (then the siege never comes, and the hill farms empty in autumn). Both expire at winter. |

The bots play a whole year (`--only=year`) and check that every tale gets told and that the later tales
open differently depending on how the earlier ones ended.

### Saves, and the Chronicle

The tale saves itself whenever a scene is waiting for your choice (`user://tale_save.json`). The title
screen then offers **Continue the tale**. The save goes away when the tale ends, and the campaign is
saved then as before. **The Chronicle** on the title screen shows:
- tales told and endings found;
- what the Teller remembers;
- rumours and standing;
- every die you own, with its notches, any grudge, and its history.

### The Practice Table (M2 playtest)

**Practice table: 20 challenges** on the title screen runs twenty challenges with no story stakes: six
tests, four trials, five contests and five fights, the same twenty in the same order for every tester.
Grit, Fate, Wounds and the Pouch are restored before each one, and it never touches your campaign save.

Nothing is pre-picked, so every choice of dice is the player's own. An optional row of reasons on the throw
card ("Best odds", "Right aspect", "Saving dice", "Chasing a combo", "Hunch") lets testers say why they
chose. Every throw is logged with the Hand, the pick, the table's own suggestion, the odds of both, the
reason and the outcome, to `user://playtests/practice-<time>.json`. The end screen sums it up. This is the
data for the M2 gate: *five playtesters each play 20 challenges and can explain why they chose their dice*.

### Throwing by hand

The gesture steers the dice, never the faces. Dice get a uniformly random orientation when picked up and
keep tumbling in the hand, and release spin has a floor, so even a gentle drop rolls. `tests/physics_check.gd`
throws a d6 handful 200 times with drops, rolls and hard flicks: every die lands in the tray, and the faces
pass a chi-square test (6.5 against a 0.001 critical value of 20.5). A die still rocking after 5 seconds
gets one small knock from the table. A die that leaves the tray is put back and thrown again.

### How a tale plays

1. **Wren's plea** at the tavern, then an optional **wager**: stake one of your dice to double the tale's Coin.
2. **Pack the Pouch** from the shelf (weight limit 12) and fill the Saddlebag (weight 4) for the Waystone.
3. **Scenes**: the Teller narrates on the parchment, and you choose what your character does. Options never
   name an aspect or a reward: you decide who you are, then find out how your dice handle it.
4. **Approach**: your Hand of 5 is drawn first, then you pick how to go about it (every option can be done with
   2 or 3 aspects), with the odds for your actual Hand shown on each.
5. **Throw**: pick up to Effort dice (usually 3). Odds per tier update as you pick. The dice tumble in the tray.
   A cocked die can be settled for 1 Fate (free for Bone) or thrown again for free. Echo faces re-throw.
6. **Assign**: put each die in a slot (full value on its own aspect, half elsewhere). Spend Fate to Nudge,
   Reroll or Bump the table. Confirm.
7. **Tier**: Fail, Mixed, Success or Triumph. Mixed lets you choose the price. A Fail earns a Fate token and a
   Grudge on your lowest die, has its own written outcome, and often finds content nothing else reaches.

Challenge kinds: **Tests** (one moment), **Trials** (a Danger clock; throwing your full Effort rushes and ticks
it twice), **social Contests** (they throw first; split your dice between Press and Hold), and **Combat**
(the foe throws first and its dice freeze in the tray; five stances: Strike, Guard, Evade, Trick, Read).

## Writing tales

Tales live in `tales/*.tale`, as plain text. The format is in [docs/tale_format.md](docs/tale_format.md), and
`tales/drowned_bell.tale` is the full example. A scene looks like this:

```
## shore: The Shore at Dusk
? weather==fog :: Fog lies on the water so thick the tower comes and goes.

* walk: Walk the shore alone at dusk.
  challenge: kind=test difficulty=standard tries=2 title="Reading the shore"
  approach lore: Read the carved stones half-sunk along the waterline.
  approach grace: Climb out along the broken causeway.
  > success: You learn enough.
    goto: tolls
  ...
```

**The text preview** plays a tale with no dice:
- At every throw you pick Fail, Mixed, Success, Triumph or Caught, or let the bot roll for real.
- You can jump to any scene, set flags (`flag climax=freed`), and test conditions (`check has:lore`).
- **Reload file** picks up your edits while staying in the same scene.
- It shows the linter's findings with line numbers, and which options and outcomes you haven't seen yet.

Open it from the title screen (**Tale preview**), or in a terminal:

```
godot --headless -s res://tools/preview.gd -- res://tales/drowned_bell.tale             # interactive
godot --headless -s res://tools/preview.gd -- res://tales/drowned_bell.tale --walk=300  # coverage
```

To edit `.tale` files inside the Godot editor (desktop or Android), add `tale` to **Editor Settings >
Docks > FileSystem > TextFile Extensions**. Exporting the game needs `*.tale` in the export preset's
non-resource filter, so the tales are packed.

## The Drowned Bell

14 scenes over three acts, three Act II routes that rejoin at the Waystone and the Bell Chamber, five endings
(Rest, Silence, Greed, The Bargain, Drowned). It shows every system once: all five aspects, Trials, two social
Contests, three fights with non-violent alternatives, a card sharp who spots loaded dice, a cursed temptation
(the Bellmetal d20), companion dice (Hobb's oak d6, the Smuggler's Hook), Teller's variations (weather), and a
bottleneck scene that reads everything you did. A first run sees about 10 scenes and 10 to 12 throws.

## Code layout

The rules never touch the scene tree, so the same code runs in the game, in tests and in the balance bots.

| Path | What it does |
|---|---|
| `scripts/rules/dice.gd` | Dice as data: aspects, faces and runes, materials and traits, every die in the slice, measured face distributions |
| `scripts/rules/pouch.gd` | Collection, Pouch (a deck with weight), Saddlebag, Hand, discard, Fatigue, Waystone swaps |
| `scripts/rules/scoring.gd` | Face values, combos (Pair, Triple, Run, Kinship, High Table), Kin, Grudges, the Teller's pity, on/off-aspect, best assignment, tiers |
| `scripts/rules/challenge.gd` | Tests, Trials and the Last Stand |
| `scripts/rules/contest.gd` | Social Contests, including the card sharp's loaded-dice check |
| `scripts/rules/combat.gd`, `foes.gd` | Combat rounds, stances, foe dice kinds and traits, boss phases; foes as data |
| `scripts/rules/odds.gd` | Odds shown before every throw: exact enumeration for final throws, simulation for the rest |
| `scripts/rules/tale_runner.gd` | Plays a tale: a state machine the table and the bots drive through the same calls |
| `scripts/rules/tale_state.gd`, `campaign.gd` | Per-tale memory (Grit, Fate, Wounds, flags, temperament) and the saved campaign |
| `scripts/rules/teller.gd` | The Teller's reaction lines, keyed to events, with a cooldown |
| `scripts/rules/conditions.gd` | The small condition language tales use (`rumour_smugglers or has:guile`) |
| `scripts/rules/bot.gd` | Balance bots with archetype Pouches |
| `tales/*.tale` | The tales, as text ([format](docs/tale_format.md)): The Drowned Bell and the five M5 tales |
| `scripts/rules/patrons.gd` | The campaign around the tales: who offers what, the calendar, season events, missed tales, Sister Maud |
| `scripts/rules/tale_parser.gd`, `tale_writer.gd` | Read a `.tale` file into the dictionary the runner plays, and write one back |
| `scripts/rules/tale_lint.gd` | The linter: design rules and broken links, reported by file line |
| `scripts/rules/tales.gd` | Finds and caches the shipped tales |
| `scripts/rules/preview.gd` | The writers' text preview (used by the in-game panel and `tools/preview.gd`) |
| `scripts/tale/practice.gd` | The Practice Table: twenty challenges in the same tale format |
| `scripts/game/game.gd` | The playable table: parchment, cards, Hand, Pouch screen, ending, camera views; turns clicks into runner calls |
| `scripts/rules/board.gd` | The tale board as data: tiles, roads (bent around other tiles), what each tile and road shows right now, tokens |
| `scripts/game/tale_board.gd` | The 3D tale board: parchment, painted tiles, inked roads, mist, labels, tokens, the figurine's hop |
| `scripts/figures.gd` | Painted figurines, tiles and tokens from primitives, merged into one vertex-coloured mesh each, with an ink outline shell; with the kits on, KayKit miniatures, hex tiles and buildings take the place of most primitives |
| `scripts/kits.gd` | Loads the CC0 kit models (`assets/kits/`) and repaints them: toon light bands, brush noise, colour washes, the ink outline shell on Low and on the board |
| `tools/vendor_kits.py`, `tools/bake_minis.gd` | Copy kit models in (colour maps only) and bake the KayKit characters into posed static miniatures |
| `scripts/rules/forge.gd` | Hollis's shelf (buy, sell, the fair) and Brannoc's bench (recarve, inscribe, melt, mend, load, rebind, materials and trust) as rules |
| `scripts/game/tavern_hub.gd` | The tavern between tales: the room and the patrons, the shelf, the bench, Maud's corner, passing nights |
| `scripts/game/table.gd` | Physical dice: spawns rules dice as rigid bodies, throws (tossed or held and released by hand), settles with a nudge, recovers strays, reads faces, freezes the foe's dice, finds the die under the cursor |
| `scripts/game/settings.gd` | Graphics presets (Low, Medium, High) |
| `scripts/game/preview_panel.gd` | The text preview on paper, inside the game |
| `scripts/game/practice_log.gd` | The Practice Table's log: picks against the table's suggestion, odds, reasons, outcomes, saved as JSON |
| `scripts/game/ui_kit.gd` | Paper-and-wax UI styles plus code-drawn widgets (die tiles, odds bar, pips) |
| `tests/run_tests.gd` | Unit tests, the tale linter and the balance bots |
| `tests/physics_check.gd` | Real physics: drag throws land in the tray and give fair faces |

## Tests, linter and balance

Physics (real Jolt dice): `godot --headless --fixed-fps 120 -s res://tests/physics_check.gd -- --throws=200`.
UI autoplay through the practice table with simulated mouse drags and tray clicks:
`godot --headless --fixed-fps 60 -- --new --autoplay --practice --drag --quit-at-end`.

```
godot --headless -s res://tests/run_tests.gd                                   # everything, quick bots (about 6 minutes)
godot --headless -s res://tests/run_tests.gd -- --only=year                    # a year of campaign play, by bots
godot --headless -s res://tests/run_tests.gd -- --runs=200 --report=media/balance.md
godot --headless --fixed-fps 60 res://game.tscn -- --new --autoplay --quit-at-end --seed=4
```

The last line has a bot play the whole tale through the real UI with physics dice, headless, in seconds.

The linter checks that every challenge has an outcome for all four tiers (and for being caught cheating where a
card sharp sits), every option can be done with 2 or more aspects, no option names an aspect or previews a
reward, every Mixed offers at least two costs, every flag read is set somewhere, and every scene is reachable.
The odds test compares the odds shown against 20,000 simulated throws. Latest report:
[media/balance.md](media/balance.md).

## Rules decisions made while building M1

Where the design doc left a gap or two rules pulled against each other, this is what the code does:

- **Defeat** comes only from failing the Last Stand in the final fight, or from a third Wound. A Last Stand
  failed earlier costs a Wound and moves the story on. This reconciles "Last Stand fail ends the tale" with
  "one throw can't end a run".
- **Defy** turns a single Fail into a Mixed, but not a fight that was lost over several rounds (the Last Stand is
  the fight's safety net).
- **Glint** (Arcane Amethyst): with free assignment the doc's "swap one even die between slots" did nothing, so
  an even-landing amethyst die counts in full in any slot instead.
- **Trials**: each try ticks the Danger clock once; throwing your full Effort rushes and ticks it twice.
- **Social Contests**: three rounds, your Nerve starts at 10. Triumph if they break in round one or you lose no
  Nerve; Mixed if their Resolve ends within 30% of where it started.
- **Combat tiers**: Triumph if you win losing 5 Grit or less, Success if you win, Mixed if you won after a Last
  Stand or fled, Fail if you lost.
- **Card sharps** spot a loaded die 1 time in 2 when it lands on its favoured face and 1 in 6 otherwise; the odds
  are shown when you pick it up.
- The doc's Mire Wolf worked example misses an option: all three dice in Strike (8 + 2 + 4) kill the wolf
  outright. The bot finds it.
- Standard single-try Tests are harsh with a mixed Pouch (three on-aspect dice are rare), so the slice's
  Standard Tests give two tries with progress carrying over, like the doc's flooded-gate example.

Not built yet (later milestones): Epithets, loading and the rest of forging, patrons and the full tavern hub,
seasons, Standing and Rumours with consequences across tales.

## The dice tray (prototype)

The original sandbox: open `main.tscn` and press **F6**.

| Key | Action |
|---|---|
| Space / left click | Throw all dice |
| 1 to 9 | Throw a single die |
| T | Next dice set |
| E | Add or remove the special dice (loaded d6, combat d6) |
| G | Gallery view (dice laid out, highest face toward you) |
| Esc | Quit |

When the dice stop, each one gets a floating number, the parchment lists all results with the total and
the percentile roll (d% + d10), and a natural 20 or a 1 on the d20 gets a banner. A die resting tilted
against a wall or another die shows `?`.

## Dice sets

Each set is the classic seven-piece tabletop set: d4, d6, d8, d10 (0 to 9), d% (00 to 90), d12, d20.

| Set | Look |
|---|---|
| Dragon's Blood | red and black swirled resin, gold sparkle, gold numbers |
| Ancient Bone | ivory with brown ink |
| Elven Jade | green and white marble, white numbers |
| Dwarven Brass | brushed metal, black engraved numbers |
| Arcane Amethyst | purple with starry glints |

Special dice (press E):
- **Loaded d6**: its centre of mass is shifted toward the 1, so it rolls a 6 about 75% of the time.
  Tune `load` in `dice_catalog.gd` (0 is fair).
- **Combat d6**: words instead of numbers (`MISS, ATK, ATK, DEF, HEAL, CRIT`).

A new set is one dictionary of numbers in `scripts/dice_catalog.gd`:

```gdscript
{"name": "Frost Giant", "a": Color("#bfe6ff"), "b": Color("#2a5a8a"), "swirl": 1.5, "scale": 1.6,
 "rough": 0.2, "sparkle": 0.8, "sparkle_color": Color.WHITE,
 "ink": Color("#0a1a30"), "ink_outline": Color("#6a9ac0")},
```

Any die can also take a `labels` array for custom faces, e.g. `["1", "2", "BURN", "BURN", ...]`.

## What's in it

| File | What it does |
|---|---|
| `scripts/dice_geometry.gd` | Builds the polyhedra (tetrahedron, cube, octahedron, pentagonal trapezohedron, dodecahedron, icosahedron) from maths, and rounds the edges of any convex shape (dice, tray, furniture). |
| `scripts/die.gd` | A `RigidBody3D` that turns a spec into a rounded-edge mesh, numbers and a convex collider, and reads which face is up. |
| `scripts/materials.gd` | Procedural shaders with bump relief: wood planks, stone blocks, velvet, parchment, marbled/metal dice, brass, coins, wax, ale foam, glowing coals. |
| `scripts/props.gd` | Code-built prop shapes: lathed candles with melted rims and wax drips, brass dishes, bent firewood, cartoon flame cards, a tankard with spilling foam, jug, bottles and flasks, barrels with a tap, a coin pouch, curled parchment, hanging lanterns. |
| `scripts/sfx.gd` | Sounds synthesised at startup (no audio files): dice clacks on wood, thumps on felt, die-on-die clicks, and a looping log-fire crackle. |
| `scripts/tavern.gd` | The inn: table, dice tray, fireplace with particle fire, candles, tankard, coins, shelves, barrels, flickering lights. |
| `scripts/dice_catalog.gd` | Data-only dice sets and special dice. |
| `scripts/main.gd` | Camera, throwing, results, parchment UI, banners. |
| `scripts/stats.gd` | Headless fairness test: throws each die thousands of times and runs a chi-squared check. |

**Face-up detection.** Each face's outward normal is stored in the die's local space. After the throw the
die rotates each normal into world space and picks the one closest to straight up. The d4 uses its corners
instead, with numbers printed near each corner like a real d4.

**Rounded edges.** Each face is shrunk toward its centre and the gaps are filled with edge strips and
corner caps whose normals blend between faces. The rounded shape is also the collision hull, so dice roll
a little more freely than sharp ones.

## Art direction: stylized, painterly

Warm hand-painted tabletop look (references: Hearthstone's tavern, Sea of Thieves lighting, Wind Waker fire,
Arcane's brushwork). Three pieces make it:
- **Toon light** (`TOON_LIGHT` in `materials.gd`, spliced into every lit shader): light falls off in soft bands
  with brush-wobbled edges, crisp highlight shapes, a painted rim, and violet ambient shadows against warm fire.
- **Painterly screen pass** (`POST`): a soft Kuwahara filter smears the image into brush patches and dark-brown
  ink lines trace depth and shape edges. Forward+ only. Set `brush_px` to 0 to keep the lines without the smear.
- **Silhouettes from code** (`props.gd`): real shapes instead of plain cylinders, plus cartoon flame cards.

Set `Mats.toon = false` to go back to the smooth, realistic lighting.

Small touches that make the room feel alive: dust motes drift through the lantern light, the background
softens with depth of field, the camera breathes slightly, flames lean when dice slam into the tray, and the
moonlit window cools the warm firelight.

## Sound

Every sound is generated in `sfx.gd` when the game starts: a few decaying sine tones (the ring of a struck
object) plus a short noise burst, written straight into 16-bit audio. Dice pick the sound by what they hit
(velvet, wood, another die) and set the volume by impact speed. The fireplace plays a seamless crackle loop
positioned in 3D.

## Fairness test

```
godot --headless --fixed-fps 120 res://stats.tscn -- --rolls=2000 --out=stats.md
# options: --only=d12   --seed=42
```

About 15 seconds for 2,000 throws of every die. Latest results: [media/stats.md](media/stats.md). All
regular dice pass, and the loaded d6 rolls a 6 about 75% of the time. Around 5% of throws end with a die
leaning on another one; those are counted separately as "cocked".

## Rendering without a window (how the media was made)

Uses Forward+ on the software Vulkan driver (lavapipe), at about 1.5 s per 1080p frame:

```
xvfb-run -s "-screen 0 1920x1080x24" godot --rendering-driver vulkan --resolution 1920x1080 --fixed-fps 30 \
  --write-movie out/f.png res://main.tscn -- --capture --seed=35 --theme=0 --shot=out/result.png
xvfb-run -s "-screen 0 1920x1080x24" godot --rendering-driver vulkan --resolution 1920x1080 --fixed-fps 30 \
  res://main.tscn -- --gallery --theme=3 --shot=out/gallery.png
```

Other options: `--still` renders the room without throwing or UI, `--extras` adds the special dice, `--cam=x,y,z,tx,ty,tz` moves the camera.

## Technical choices

- **Godot 4 over Unity**: free and open source, a 100 MB download with no account, and everything here is
  plain text scripts that are easy to generate and diff. It also runs headless for automated tests and
  renders, which suits a game that is mostly code.
- **Jolt physics** at 120 ticks per second, gravity 25 so the dice tumble at a believable speed for their size.
- **Forward+ renderer** with ambient occlusion, bounced light, soft shadows, volumetric haze and 4x MSAA.
  On a machine without Vulkan, Godot falls back to the Compatibility renderer automatically: it still
  runs, without the haze and contact shadows.
