## Odds check: shown odds vs. 20,000 simulated throws

| Dice | Slot | Shown (F/M/S/T) | Simulated (F/M/S/T) |
|---|---|---|---|
| oak_might, dragon_d10, oak_lore | might 13 | 32/31/36/2 | 32/30/36/2 |
| jade_d8, oak_lore, bone_d4 | lore 11 | 20/37/30/13 | 20/37/30/13 |
| loaded_d6, amethyst_d6, oak_guile | guile 13 | 1/11/58/30 | 1/11/59/29 |
| brass_d8, oak_ward | ward 9 | 4/25/63/8 | 4/25/63/8 |

## Mire Wolf (bot, balanced Pouch, 400 fights)

Wins 99%, 3.5 rounds, 4.2 Grit lost on average.

## Standard test (target 13), best 3 of a 5-die Hand, 20,000 throws

| Hand | Fail | Mixed | Success | Triumph |
|---|---|---|---|---|
| balanced Pouch, lore | 63% | 21% | 10% | 6% |
| balanced Pouch, might | 79% | 16% | 4% | 0% |
| jade_d8, jade_d10, oak_lore vs Lore 13 | 1% | 11% | 46% | 42% |
| oak_might, oak_guile, oak_grace vs Lore 13 | 100% | 0% | 0% | 0% |

## The practice table, played by the bot (50 runs)

| Kind | Fail | Mixed | Success | Triumph |
|---|---|---|---|---|
| test | 33% | 46% | 17% | 4% |
| contest | 17% | 14% | 48% | 22% |
| combat | 20% | 0% | 46% | 34% |
| trial | 7% | 33% | 49% | 12% |

## The Drowned Bell, played by bots (200 runs per Pouch, random choices)

| Pouch | Non-defeat | Endings | Grit at the climax (median) | Throws | Scenes | Tier mix |
|---|---|---|---|---|---|---|
| balanced | 88% | silence 117, bargain 24, drowned 25, rest 25, greed 9 | 20 | 10.9 | 9.0 | 13/15/58/14 |
| bruiser | 93% | rest 21, silence 126, drowned 15, greed 15, bargain 23 | 20 | 9.7 | 9.3 | 11/13/57/19 |
| sage | 92% | silence 121, rest 37, drowned 17, bargain 15, greed 10 | 20 | 9.5 | 9.1 | 12/15/59/15 |
| swindler | 86% | silence 112, drowned 29, rest 21, greed 10, bargain 28 | 20 | 11.7 | 9.0 | 15/17/52/16 |

Every ending reached: silence, bargain, drowned, rest, greed

### Outcome tiers per challenge (all Pouches)

| Challenge | Plays | Fail | Mixed | Success | Triumph | Caught |
|---|---|---|---|---|---|---|
| arrival.lamb | 266 | 4% | 0% | 60% | 36% | 0% |
| arrival.row | 282 | 14% | 19% | 50% | 17% | 0% |
| arrival.shore | 252 | 16% | 20% | 54% | 10% | 0% |
| chamber.answer | 65 | 0% | 77% | 18% | 5% | 0% |
| chamber.break | 19 | 0% | 74% | 26% | 0% | 0% |
| chamber.fight | 587 | 15% | 1% | 77% | 7% | 0% |
| chamber.name | 39 | 0% | 41% | 44% | 15% | 0% |
| chamber.salvage | 90 | 0% | 16% | 61% | 23% | 0% |
| dive.dive | 181 | 20% | 23% | 40% | 17% | 0% |
| kettle.haggle | 44 | 23% | 0% | 57% | 20% | 0% |
| kettle.share | 65 | 8% | 28% | 51% | 14% | 0% |
| kettle.threaten | 46 | 52% | 0% | 37% | 11% | 0% |
| scriptorium.pray | 97 | 15% | 29% | 47% | 8% | 0% |
| scriptorium.read | 85 | 20% | 22% | 45% | 13% | 0% |
| tolls.fight | 173 | 2% | 0% | 62% | 36% | 0% |
| tolls.follow | 181 | 18% | 34% | 43% | 6% | 0% |
| tolls.hide | 164 | 9% | 14% | 59% | 18% | 0% |

Choices under random play are uniform by construction; real pick rates need playtest telemetry.

