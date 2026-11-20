extends RefCounted
## Collection, Pouch, Saddlebag, Hand. The Pouch behaves like a deck: dice are drawn at random
## into the Hand, thrown dice go to the discard, and when the Pouch runs dry the discard is
## shuffled back in and you gain 1 Fatigue (Hand size -1 per 2 Fatigue until you rest).

signal fatigued(total: int)

const BASE_HAND := 5
const MIN_HAND := 2

var collection: Array = []     # every die you own (the shelf behind the bar)
var pouch: Array = []          # dice carried into the tale
var saddlebag: Array = []      # filled at the tavern; swap with the Pouch at Waystones
var weight_limit := 12
var saddle_limit := 4

# During a tale
var draw_pile: Array = []
var discard: Array = []
var hand: Array = []
var exhausted: Array = []      # set aside until the next Waystone (a Mixed cost)
var fatigue := 0
var hand_penalty := 0          # from Wounds
var swaps_left := 0            # at a Waystone


# ------------------------------------------------------------------ building the Pouch

static func weight_of(dice: Array) -> int:
	var w := 0
	for d in dice:
		w += int(d.weight)
	return w


func weight() -> int:
	return weight_of(pouch)


func can_add(die: Dictionary) -> bool:
	return not pouch.has(die) and weight() + int(die.weight) <= weight_limit


func add(die: Dictionary) -> bool:
	if not can_add(die):
		return false
	saddlebag.erase(die)
	pouch.append(die)
	return true


func remove(die: Dictionary) -> bool:
	if die.cursed and pouch.has(die):
		return false  # cursed dice cannot leave the Pouch
	pouch.erase(die)
	return true


func can_bag(die: Dictionary) -> bool:
	return not saddlebag.has(die) and not die.cursed and weight_of(saddlebag) + int(die.weight) <= saddle_limit


func bag(die: Dictionary) -> bool:
	if not can_bag(die):
		return false
	pouch.erase(die)
	saddlebag.append(die)
	return true


func unbag(die: Dictionary) -> void:
	saddlebag.erase(die)


func shelf() -> Array:
	return collection.filter(func(d): return not pouch.has(d) and not saddlebag.has(d))


func gain(die: Dictionary, into_pouch := true) -> void:
	if not collection.has(die):
		collection.append(die)
	if into_pouch:
		# New dice go straight into the Pouch for the rest of the tale, weight allowing;
		# otherwise they wait on the shelf. A cursed die forces its way in.
		if die.cursed or weight() + int(die.weight) <= weight_limit:
			pouch.append(die)
			draw_pile.append(die)
			draw_pile.shuffle()


func lose(die: Dictionary) -> void:
	collection.erase(die)
	pouch.erase(die)
	saddlebag.erase(die)
	draw_pile.erase(die)
	discard.erase(die)
	hand.erase(die)
	exhausted.erase(die)


# ------------------------------------------------------------------ during a tale

func start_tale(rng: RandomNumberGenerator) -> void:
	draw_pile = pouch.duplicate()
	_shuffle(draw_pile, rng)
	discard.clear()
	hand.clear()
	exhausted.clear()
	fatigue = 0


func hand_size() -> int:
	return maxi(MIN_HAND, BASE_HAND - fatigue / 2 - hand_penalty)


## Draw up to hand size. Returns the newly drawn dice.
func refill_hand(rng: RandomNumberGenerator) -> Array:
	var drawn: Array = []
	while hand.size() < hand_size():
		if draw_pile.is_empty():
			if discard.is_empty():
				break
			draw_pile = discard.duplicate()
			discard.clear()
			_shuffle(draw_pile, rng)
			fatigue += 1
			fatigued.emit(fatigue)
		var d = draw_pile.pop_back()
		hand.append(d)
		drawn.append(d)
	return drawn


## Thrown dice leave the Hand for the discard.
func spend(dice: Array) -> void:
	for d in dice:
		hand.erase(d)
		if pouch.has(d) and not discard.has(d) and not exhausted.has(d):
			discard.append(d)


## At the end of a challenge the dice you held back go back into the Pouch.
func return_hand(rng: RandomNumberGenerator) -> void:
	for d in hand:
		draw_pile.append(d)
	hand.clear()
	_shuffle(draw_pile, rng)


func exhaust(die: Dictionary) -> void:
	draw_pile.erase(die)
	discard.erase(die)
	hand.erase(die)
	if not exhausted.has(die):
		exhausted.append(die)


## A Waystone: Fatigue clears, exhausted dice come back, everything is reshuffled.
func rest(rng: RandomNumberGenerator, swaps := 2) -> void:
	fatigue = 0
	exhausted.clear()
	hand.clear()
	discard.clear()
	draw_pile = pouch.duplicate()
	_shuffle(draw_pile, rng)
	swaps_left = swaps


## The per-tale part of the Pouch, for a mid-tale save (the collection is saved by the campaign).
func tale_to_dict() -> Dictionary:
	var ids := func(arr): return arr.map(func(d): return d.id)
	return {"draw_pile": ids.call(draw_pile), "discard": ids.call(discard), "hand": ids.call(hand),
		"exhausted": ids.call(exhausted), "fatigue": fatigue, "hand_penalty": hand_penalty, "swaps_left": swaps_left}


func tale_from_dict(d: Dictionary) -> void:
	var by_id := {}
	for die in collection:
		by_id[die.id] = die
	var dice := func(arr): return arr.filter(func(id): return by_id.has(id)).map(func(id): return by_id[id])
	draw_pile = dice.call(d.get("draw_pile", []))
	discard = dice.call(d.get("discard", []))
	hand = dice.call(d.get("hand", []))
	exhausted = dice.call(d.get("exhausted", []))
	fatigue = int(d.get("fatigue", 0))
	hand_penalty = int(d.get("hand_penalty", 0))
	swaps_left = int(d.get("swaps_left", 0))


## Swap one die between Pouch and Saddlebag at a Waystone (each move counts as one swap).
func waystone_swap(die: Dictionary) -> bool:
	if swaps_left <= 0:
		return false
	if pouch.has(die):
		if die.cursed:
			return false
		pouch.erase(die)
		draw_pile.erase(die)
		saddlebag.append(die)
	elif saddlebag.has(die):
		if weight() + int(die.weight) > weight_limit:
			return false
		saddlebag.erase(die)
		pouch.append(die)
		draw_pile.append(die)
	else:
		return false
	swaps_left -= 1
	return true


func dice_left() -> int:
	return draw_pile.size()


func has_aspect(aspect: String) -> bool:
	for d in pouch:
		if d.aspect == aspect:
			return true
	return false


func has_material(mat: String) -> bool:
	for d in pouch:
		if d.material == mat:
			return true
	return false


## End of the tale: lent dice go home.
func end_tale() -> Array:
	var gone: Array = []
	for d in collection.duplicate():
		if d.ally:
			gone.append(d)
			lose(d)
	hand.clear()
	discard.clear()
	draw_pile.clear()
	exhausted.clear()
	fatigue = 0
	return gone


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
