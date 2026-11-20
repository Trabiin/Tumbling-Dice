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

## The Drowned Bell, played by bots (200 runs per Pouch, random choices)

| Pouch | Non-defeat | Endings | Grit at the climax (median) | Throws | Scenes | Tier mix |
|---|---|---|---|---|---|---|
| balanced | 87% | silence 113, bargain 24, drowned 27, rest 27, greed 9 | 20 | 10.9 | 9.0 | 14/16/57/13 |
| bruiser | 93% | rest 21, silence 126, drowned 15, greed 15, bargain 23 | 20 | 9.8 | 9.3 | 11/13/58/19 |
| sage | 92% | silence 122, rest 37, drowned 17, bargain 15, greed 9 | 20 | 9.5 | 9.1 | 12/15/58/15 |
| swindler | 87% | silence 115, drowned 27, rest 21, greed 10, bargain 27 | 20 | 11.7 | 9.0 | 16/16/52/17 |

Every ending reached: silence, bargain, drowned, rest, greed

### Outcome tiers per challenge (all Pouches)

| Challenge | Plays | Fail | Mixed | Success | Triumph | Caught |
|---|---|---|---|---|---|---|
| arrival.lamb | 266 | 4% | 0% | 60% | 36% | 0% |
| arrival.row | 282 | 14% | 19% | 50% | 17% | 0% |
| arrival.shore | 252 | 17% | 20% | 54% | 10% | 0% |
| chamber.answer | 68 | 0% | 78% | 18% | 4% | 0% |
| chamber.break | 19 | 0% | 74% | 26% | 0% | 0% |
| chamber.fight | 586 | 15% | 1% | 77% | 7% | 0% |
| chamber.name | 38 | 0% | 39% | 45% | 16% | 0% |
| chamber.salvage | 89 | 0% | 16% | 60% | 25% | 0% |
| dive.dive | 182 | 21% | 21% | 41% | 16% | 0% |
| kettle.haggle | 44 | 23% | 0% | 59% | 18% | 0% |
| kettle.share | 65 | 8% | 23% | 52% | 17% | 0% |
| kettle.threaten | 45 | 53% | 0% | 36% | 11% | 0% |
| scriptorium.pray | 98 | 15% | 30% | 47% | 8% | 0% |
| scriptorium.read | 84 | 23% | 21% | 40% | 15% | 0% |
| tolls.fight | 174 | 2% | 0% | 61% | 36% | 0% |
| tolls.follow | 181 | 18% | 34% | 41% | 7% | 0% |
| tolls.hide | 163 | 9% | 14% | 60% | 17% | 0% |

Choices under random play are uniform by construction; real pick rates need playtest telemetry.

