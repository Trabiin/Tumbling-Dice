## Odds check: shown odds vs. 20,000 simulated throws

| Dice | Slot | Shown (F/M/S/T) | Simulated (F/M/S/T) |
|---|---|---|---|
| oak_might, dragon_d10, oak_lore | might 13 | 32/31/36/2 | 32/30/36/2 |
| jade_d8, oak_lore, bone_d4 | lore 11 | 20/37/30/13 | 20/37/30/13 |
| loaded_d6, amethyst_d6, oak_guile | guile 13 | 1/11/58/30 | 1/11/59/29 |
| brass_d8, oak_ward | ward 9 | 4/25/63/8 | 4/25/63/8 |

## Mire Wolf (bot, balanced Pouch, 400 fights)

Wins 100%, 2.0 rounds, 3.0 Grit lost on average.

## Standard test (target 13), best 3 of a 5-die Hand, 20,000 throws

| Hand | Fail | Mixed | Success | Triumph |
|---|---|---|---|---|
| balanced Pouch, lore | 63% | 21% | 10% | 6% |
| balanced Pouch, might | 79% | 16% | 4% | 0% |
| jade_d8, jade_d10, oak_lore vs Lore 13 | 1% | 11% | 46% | 42% |
| oak_might, oak_guile, oak_grace vs Lore 13 | 100% | 0% | 0% | 0% |

The Teller's Mood, The Drowned Bell non-defeat at Mood 0 / 3 / 5: 75% / 70% / 60%

## The practice table, played by the bot (15 runs)

| Kind | Fail | Mixed | Success | Triumph |
|---|---|---|---|---|
| test | 26% | 49% | 19% | 7% |
| contest | 20% | 17% | 47% | 17% |
| combat | 9% | 0% | 36% | 55% |
| trial | 8% | 25% | 47% | 20% |

## The Drowned Bell, played by bots (60 runs per Pouch, random choices)

| Pouch | Non-defeat | Endings | Grit at the climax (median) | Throws | Scenes | Tier mix |
|---|---|---|---|---|---|---|
| balanced | 73% | silence 31, drowned 16, rest 8, bargain 4, greed 1 | 11 | 8.5 | 8.6 | 6/6/67/20 |
| bruiser | 73% | greed 4, silence 30, drowned 16, bargain 9, rest 1 | 11 | 8.3 | 9.1 | 7/3/64/27 |
| sage | 78% | silence 28, rest 10, drowned 13, bargain 7, greed 2 | 11 | 7.5 | 8.8 | 5/7/55/34 |
| swindler | 68% | silence 27, rest 7, drowned 19, bargain 4, greed 3 | 11 | 9.3 | 8.6 | 7/8/63/23 |

Every ending reached: silence, drowned, rest, bargain, greed

### Outcome tiers per challenge (all Pouches)

| Challenge | Plays | Fail | Mixed | Success | Triumph | Caught |
|---|---|---|---|---|---|---|
| arrival.lamb | 87 | 2% | 0% | 46% | 52% | 0% |
| arrival.row | 75 | 0% | 8% | 73% | 19% | 0% |
| arrival.shore | 78 | 0% | 6% | 78% | 15% | 0% |
| chamber.answer | 15 | 0% | 40% | 40% | 20% | 0% |
| chamber.fight | 152 | 15% | 2% | 55% | 28% | 0% |
| chamber.name | 11 | 0% | 18% | 36% | 45% | 0% |
| chamber.salvage | 24 | 0% | 4% | 83% | 13% | 0% |
| dive.dive | 48 | 6% | 15% | 65% | 15% | 0% |
| kettle.haggle | 12 | 0% | 0% | 83% | 17% | 0% |
| kettle.share | 10 | 0% | 0% | 40% | 60% | 0% |
| kettle.threaten | 21 | 19% | 0% | 62% | 19% | 0% |
| scriptorium.pray | 35 | 0% | 6% | 74% | 20% | 0% |
| scriptorium.read | 24 | 4% | 17% | 67% | 13% | 0% |
| tolls.fight | 60 | 22% | 2% | 42% | 35% | 0% |
| tolls.follow | 60 | 0% | 12% | 67% | 22% | 0% |
| tolls.hide | 45 | 2% | 2% | 78% | 18% | 0% |

Choices under random play are uniform by construction; real pick rates need playtest telemetry.

## A year of play, by bots (10 years)

| Tale | Told | Endings |
|---|---|---|
| The Last Watch | 12 | banner 6, letter 4, fallen 2 |
| The Pretender's Road | 11 | held 1, joined 6, exposed 1, burned 1, fallen 2 |
| Siege of Holloway | 4 | fallen 3, won 1 |
| The Dicewright's Debt | 11 | deal 4, quenched 4, burned 3 |
| The Card Sharps' Moon | 6 | hollis 3, tell 1, moon 2 |
| The Long Con | 11 | empty 1, fair 6, river 3, caught 1 |
| The Duke's Ledger | 17 | thrown 7, crown 1, kettle 4, memory 2, burned 3 |
| The Gilded Ruin | 15 | taken 1, retire 3, drowned 5, partners 2, city 4 |
| The Stranger's Throw | 10 | found 10 |
| The Witch of Sallow Wood | 11 | given 1, kept 1, carried 3, sworn 3, burned 3 |
| The Hollow Saint | 11 | wood 4, sold 1, priory 5, lost 1 |
| The Teller's Tale | 14 | lost 4, freed 2, taken 4, broken 4 |
| The Drowned Bell | 15 | bargain 4, silence 6, drowned 5 |
| The Bell Market | 10 | beaten 5, fallen 1, rest 3, fled 1 |
| The Tide Court | 12 | stilled 4, fallen 3, peace 4, judged 1 |

## Builds over whole campaign years (5 years each)

| Build | Tales told | Brought home | Campaign finished |
|---|---|---|---|
| balanced | 89 | 80% | 5 of 5 |
| bruiser | 78 | 90% | 5 of 5 |
| sage | 79 | 86% | 5 of 5 |
| swindler | 85 | 85% | 5 of 5 |

