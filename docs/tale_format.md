# The .tale format

Tales are plain text files in `tales/`. The game parses them when it starts, the linter checks them,
and the text preview plays them without dice. `tales/drowned_bell.tale` is the full example; `tales/tide_court.tale` shows a tale that reads earlier ones.

A tale is a header, then scenes. Each scene has narration, then options. Options that need dice have
outcomes, one per tier.

```
title: The Drowned Bell
id: drowned_bell
patron: Wren
start: plea

## plea: Wren's Plea
act: 1

[i]Pull your stool closer to the fire. This one is cold.[/i]
A girl in a fisherman's oilskin stands at your table, dripping on the boards.
? seen:drowned_before :: [i]They say a traveller tried this before you.[/i]

* promise: "I'll find your father. I promise you that."
  temper: duty +1
  do: flag promised_wren; regard 1
  goto: wager
  reply: Wren looks at you for a long moment, then nods once.

* shore: Walk the shore alone at dusk.
  challenge: kind=test difficulty=standard tries=2 title="Reading the shore"
  mod: tide_lore => progress=-4
  approach lore: Read the carved stones half-sunk along the waterline.
  approach grace [progress=19]: Climb out along the broken causeway.
  > triumph: The stones speak plainly.
    do: flag stones_read; fate 1
    goto: tolls
  > success: You learn enough.
    goto: tolls
  > mixed: You learn it, but the cold gets into you.
    goto: tolls
    cost: Lose 3 Grit :: grit -3
    cost: Lose a die to the lake :: lose_lowest
  > fail: The lake shows you nothing.
    goto: tolls
```

## Lines

What a line is depends on how it starts. Indentation is only for reading.

| Line | Meaning |
|---|---|
| `## id: Title` | A new scene. The id is one word, and other scenes `goto:` it. |
| `* id: Text` | An option in the current scene. The text is what the player clicks. |
| `> tier: Text` | An outcome of the current option: `fail`, `mixed`, `success`, `triumph`, or `caught` (a card sharp spotted a loaded die). Extra lines of plain text after it continue the outcome's text. |
| `+ id: Title` | An ending, in a scene with `type: ending`. The first ending whose `if:` holds is the one told. |
| `? condition :: text` | Narration that only shows when the condition holds. It works in scenes and endings. |
| `key: value` | A property of whatever came last: the scene, the option, the outcome or the ending. |
| any other line | Narration for the current scene or ending. |
| `// note` | A comment for writers. The game ignores it. |
| `\text` | A leading backslash forces narration, for a line that would otherwise read as a marker or a key. |

Option properties go before the option's first `>`. After a `>`, `do:` and `goto:` belong to that outcome.

## Properties

**Tale header** (before the first scene): `title:`, `id:`, `patron:`, `start:` (the first scene's id).

A tale that belongs to a patron's arc also says who offers it, and when (M5 campaign):

```
arc: wren                 the patron's arc (wren, ashgrove); the tale appears at their table
order: 2                  its place in the arc: a patron offers the earliest tale that is on offer
pitch: The bell of Marrowmere is for sale in the river market.
offer: ended:drowned_bell and not season==winter
expires: winter           the tale goes by without you when this season begins
missed: Holloway fell in the first snow, without you.
teller: triumph :: They'll talk about that on the river until the ice comes.
```

- `pitch:` is required in an arc. It is what the patron says at their table.
- `offer:` is a condition (see below), read every night in the tavern. Empty means always.
- `expires:` must be a season, and needs a `missed:` line, which goes in the Chronicle.
- `teller: event :: line` adds a line to the Teller's pool for this tale only (events: `triumph`,
  `mixed`, `fail`, `loaded_caught`, `rest` and the rest of `teller.gd`). Keep place names out of the
  generic pool: they belong here.

**Scene:**
- `act: 1`
- `type:` can be `choice` (the default), `encounter`, `challenge`, `prepare`, `waystone` or `ending`.
  - `encounter` and `challenge` play exactly like `choice`. The name is a note for the writer.
  - `prepare` opens the Pouch screen and needs a `goto:`.
  - `waystone` lets the player swap dice with the Saddlebag.
- `goto: id`
- `on enter: effects`
- `tile: icon` puts the scene on the tale board as a painted tile. Icons: `inn`, `village`, `shore`,
  `drowned`, `jetty`, `abbey`, `cove`, `camp`, `dive`, `chest`, `shrine`, `bell`, `tower`, `forest`,
  `cave`, `bridge`, `market`, `keep`, `road`, `place`. Scenes without a tile (the wager, packing the Pouch, the ending) are not
  places: roads run straight through them.
- `at: x, y` places the tile, in grid steps: x to the right, y toward the player. Leave it out and the
  tile goes in a column by its distance from the start.
- `token: condition => icon "label"` leaves a token on this scene's tile whenever the condition holds,
  for example `token: gold_taken => coins "The bell's gold, taken"`. Tokens: `chest`, `coins`, `grave`,
  `lamp`, `beacon`, `flag`, `knife`, `rune`, `boat`, `footprints`, `handbell`, `candle`, `broken_bell`,
  `wave`, `dove`, `foe`, `skull`, `fire`, `seal`. The label shows when the mouse is over the token.
  Every fight you win also leaves the beaten foe's figurine, toppled, on the tile where you fought.

**Option:**
- `if: condition`: the option only shows when this holds.
- `temper: duty +1, mercy -1`
- `do: effects`, `goto: id`, `reply: text`. These are for options with no dice.
- One of the following, as key=value pairs:
  - `challenge: kind=test|trial difficulty=easy|standard|hard|heroic tries=2 title="..."`. A trial uses `progress=17 danger=3 danger_text="..."`. Add `second.aspect=ward second.target=6` for a second slot.
  - `contest: opponent=odile title="..."`
  - `combat: foe=drowned_pair`
- `mod: condition => key=value`: changes the challenge when the condition holds, for example `resolve=3`, `progress=-4`, `no_wardens=true` or `bell=true`.
- `approach aspect: text`: one way to go about it. Write two or three per challenge or contest. `approach might [progress=19 danger=2]: text` also changes the challenge for that approach.

**Outcome:** `do: effects`, `goto: id`, `retry: option-id` (offer the named option again, used for "fight instead"), and `cost: label :: effects`. A Mixed outcome offers two or more costs, and the player picks one.

**Ending:** `if: condition`, `do: effects`, `renown: n` (Renown for this ending, 1 to 5; the default is 2 for a win and 0 for a defeat, and a tale with a Triumph in it earns 1 more).

## Effects

Effects are separated by `;`. Words with spaces go in double quotes. Lists go in `[a, b]`.

| Effect | Does |
|---|---|
| `flag name` or `flag name value` | Set a flag (true, a number or a word) |
| `add name n` | Add to a numeric flag |
| `random_flag name [a, b, c]` | Set a flag to one value at random (Teller's variations) |
| `grit n`, `fate n`, `coin n`, `fatigue n` | Change them (negative to lose) |
| `wound "Cracked Ribs"` | Take a named Wound |
| `gain die_id`, `ally die_id` | Gain a die for good, or one lent for this tale |
| `temper track n`, `regard n` | Temperament, and the Teller's opinion of you |
| `standing "Thieves' Guild" n` | Faction standing, -3 to 3. Names or ids: `guild`, `abbey`, `crown`, `holloway`, `marrowmere`, `wood` |
| `rumour id "text"`, `chronicle "text"`, `mark name`, `shard name` | Campaign memory. A rumour with an id can be read by later tales (`rumour:id`) |
| `material id`, `material id n` | Forging materials for Brannoc: `lead`, `binding_<aspect>`, rare `bellmetal`, `heartwood`, `black_iron`, `tide_pearl` |
| `renown n` | Extra Renown, on top of the ending's |
| `heal` | Tend the most recent Wound |
| `lift_curse`, `lift_curse die_id` | Lift the curse on a die (or on every cursed die): it keeps its faces, loses its bane runes, and is renamed "Quiet ..." |
| `give_up die_id` | Part with a die for good, cursed or not (sold, given, left behind) |
| `crack_best` | Crack a face of the best die just thrown (Brannoc can mend it) |
| `exhaust_best`, `lose_lowest` | Lose the use of your best die for the tale, or lose your lowest die |
| `rest n` | Raise Grit to n if it is lower (a rest gets you back on your feet, not back to full), clear Fatigue, allow Saddlebag swaps |
| `toll`, `wager_pick`, `lose_wager`, `return_gold` | Special effects of The Drowned Bell |
| `if condition then effect` | Only when the condition holds |

## Conditions

| Condition | True when |
|---|---|
| `rumour_smugglers` | The flag is set |
| `villagers_saved>=2` | A numeric flag comparison (`>=`, `<=`, `==`, `>`, `<`) |
| `climax==freed` | A word flag comparison |
| `has:guile` | The Pouch holds a die of that aspect |
| `mat:jade` | The Pouch holds a die of that material |
| `temper:mercy>=2` | A temperament track check |
| `wounds>=1` | A Wound count check |
| `seen:drowned_before` | A campaign Chronicle mark exists |
| `rumour:tide_turn` | You hold that rumour, from this tale or an earlier one |
| `told:drowned_bell`, `ended:drowned_bell`, `missed:siege_holloway` | You have told that tale (any ending), ended it without defeat, or let it go by |
| `ending:drowned_bell==rest` | How that tale ended (the last ending that was not a defeat) |
| `standing:guild>=1` | Faction standing (campaign plus anything gained in this tale) |
| `season==winter`, `night>=7` | The calendar: four seasons of six nights; nights count from 1 for the year |
| `renown>=5`, `trust>=1`, `coin>=40` | Renown, Brannoc's trust, Coin |
| `cursed`, `loaded` | Your Pouch holds a cursed die, or a loaded one |
| `defeat` | The tale was lost |
| `not X`, `X and Y`, `X or Y` | Combinations. `and` binds tighter than `or`. There are no parentheses. |

## The tale board

The board is drawn from the tale itself. Each `goto:` between two tiles becomes a road (roads bend
around tiles in their way). While you play:
- tiles you have visited are painted and named, and the roads you walked are inked;
- tiles one road from where you stand are sketched in faint ink;
- roads you could have taken and didn't stay faded for the rest of the tale;
- everything else is under mist, which lifts as you arrive;
- tiles walked in an earlier telling of the same tale show washed out, not in mist.

A tale with no `tile:` lines at all still gets a board: one tile per scene, laid out automatically.

## The linter

The linter checks every tale. Run it with `godot --headless -s res://tests/run_tests.gd -- --only=lint`, or open the text preview in the game.

It reports each problem with the tale's file and line. It checks for:
- missing outcomes;
- a Mixed outcome with fewer than two costs;
- options that name an aspect or preview a reward;
- dice options with fewer than two approaches;
- `goto:` targets that don't exist;
- scenes that can't be reached;
- flags that are read but never set;
- card-sharp contests with no `caught` outcome;
- unknown tile or token icons, and tokens or `at:` on a scene without a tile;
- arc headers: a `pitch:`, an `expires:` that is a season, and a `missed:` line to go with it;
- campaign reads: unknown factions, seasons and condition prefixes, and die ids in `lift_curse` and `give_up`.

Italics, `[i]like this[/i]`, are the Teller's asides.
