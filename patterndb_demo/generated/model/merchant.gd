## A vendor NPC.
class_name Merchant
extends Resource


@export_group("Basic")
@export var name: String
@export var merchant_type: enums.MerchantType
@export var faction: enums.Faction

@export_group("Stock")
@export var inventory: Array[StringName] = []
## Item id -> fixed price (nested dict).
@export var price_overrides: Dictionary

@export_group("Schedule")
@export var open_hour: int = 8
@export var close_hour: int = 20

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
