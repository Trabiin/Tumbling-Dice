# Dice at the Inn (Godot 4 prototype)

Tabletop-style dice for a dice-collecting roguelike, thrown into a dice tray on a wooden table in a
candlelit inn. Every die's shape, rounded edges, marbled material, numbers, and the whole room are
generated in GDScript and shader code. The project contains no models, textures or image files. The only
asset is the free Cinzel font (SIL Open Font License, see `fonts/OFL.txt`).

![throw](media/result_dragon.png)

All surfaces are shaders that compute colour and surface relief per pixel (wood pores and knots, chiselled
stone, velvet fibres, embossed coins, swirls suspended inside the resin dice), so there is no texture
resolution to run out of: detail stays sharp at 4K or with the camera right up against a die.

## Run it

1. Download **Godot 4.7** (standard build, not .NET) from https://godotengine.org/download. It is a single
   executable with no installer. Tested on 4.7.1.
2. Open Godot, click **Import**, pick this folder's `project.godot`, then press **F5** (or the ▶ button).
   The first import takes a few seconds while Godot reads the fonts.

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
