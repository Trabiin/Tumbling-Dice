# The .tale format

Tales are plain text files in `tales/`. The game parses them when it starts, the linter checks them,
and the text preview plays them without dice. `tales/drowned_bell.tale` is the full example.

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

**Scene:**
- `act: 1`
- `type:` can be `choice` (the default), `encounter`, `challenge`, `prepare`, `waystone` or `ending`.
  - `encounter` and `challenge` play exactly like `choice`. The name is a note for the writer.
  - `prepare` opens the Pouch screen and needs a `goto:`.
  - `waystone` lets the player swap dice with the Saddlebag.
- `goto: id`
- `on enter: effects`

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

**Ending:** `if: condition`, `do: effects`.

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
| `standing "Thieves' Guild" n` | Faction standing |
| `rumour "text"`, `chronicle "text"`, `mark name`, `shard name` | Campaign memory |
| `exhaust_best`, `lose_lowest` | Lose the use of your best die for the tale, or lose your lowest die |
| `rest n` | Restore Grit, clear Fatigue, allow Saddlebag swaps |
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
| `defeat` | The tale was lost |
| `not X`, `X and Y`, `X or Y` | Combinations. `and` binds tighter than `or`. There are no parentheses. |

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
- card-sharp contests with no `caught` outcome.

Italics, `[i]like this[/i]`, are the Teller's asides.
