class_name consts
extends RefCounted

## String-valued build metadata.
class BuildInfo:
	const channel = "beta"
	const codename = "Emberfall"
	const version = "1.0.0"

## Camera defaults.
class CameraRig:
	const distance = 8.0
	const fov = 68.0
	const pitch_max = 20.0
	const pitch_min = -40.0

## Armor, dodge and block formulas.
class CombatTuning:
	const armor_k = 0.06
	const block_value = 0.25
	const dodge_cap = 0.4

## Percent chance per rarity band.
class DropRates:
	const common = 55.0
	const epic = 4.0
	const legendary = 1.0
	const rare = 12.0
	const uncommon = 28.0

## Gold, vendor and repair economy.
class Economy:
	const repair_cost_per_point = 2
	const starting_gold = 50
	const vendor_markup = 1.5

## Core level/health/mana tuning.
class GameBalance:
	const base_health = 100
	const base_mana = 50
	const crit_multiplier = 2.0
	const exp_curve_base = 1.15
	const level_cap = 60

## Named UI colors (Color-valued constants).
class UITheme:
	const accent = Color(0.36000001430511, 0.62000000476837, 1.0, 1.0)
	const danger = Color(0.85000002384186, 0.23999999463558, 0.23999999463558, 1.0)
	const gold = Color(0.94999998807907, 0.77999997138977, 0.25, 1.0)

## World tuning constants.
class WorldSettings:
	const day_length_sec = 1200.0
	const gravity = -9.8
	const tile_size = 64
