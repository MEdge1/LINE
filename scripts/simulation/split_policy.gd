class_name SplitPolicy
extends RefCounted

# Deterministic split of an offered quantity between two Splitter branches.
# Shares are equal. For an odd quantity the extra unit goes to branch B when `extra_to_b` is
# true, otherwise to branch A; the caller alternates `extra_to_b` after each odd offer.
# A branch without room receives nothing and its share moves to the other branch.
# If both branches are full, nothing is taken and the offer stays queued upstream.


static func split(quantity: int, room_a: int, room_b: int, extra_to_b: bool) -> Vector2i:
	var free_a := maxi(room_a, 0)
	var free_b := maxi(room_b, 0)
	var share_a := quantity / 2
	var share_b := quantity / 2
	if quantity % 2 == 1:
		if extra_to_b:
			share_b += 1
		else:
			share_a += 1

	var take_a := mini(share_a, free_a)
	var take_b := mini(share_b, free_b)
	var spill := quantity - take_a - take_b

	var extra_a := mini(spill, free_a - take_a)
	take_a += extra_a
	spill -= extra_a
	take_b += mini(spill, free_b - take_b)
	return Vector2i(take_a, take_b)
