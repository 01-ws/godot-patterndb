class_name enums
extends RefCounted

## Default combat/idle behaviour for an enemy.
enum AIBehavior {
	PASSIVE = 0,
	DEFENSIVE = 1,
	AGGRESSIVE = 2,
	PATROL = 3,
	AMBUSH = 4,
	CASTER = 5
}

## Material class of armor; affects weight and resist.
enum ArmorMaterial {
	CLOTH = 0,
	LEATHER = 1,
	MAIL = 2,
	PLATE = 3,
	DRAGONSCALE = 4
}

## Environmental theme of a zone.
enum Biome {
	FOREST = 0,
	DESERT = 1,
	TUNDRA = 2,
	VOLCANO = 3,
	DUNGEON = 4,
	SWAMP = 5,
	CAVERN = 6,
	CITY = 7,
	COAST = 8
}

## Playable and NPC archetypes.
enum CharacterClass {
	WARRIOR = 0,
	MAGE = 1,
	ROGUE = 2,
	CLERIC = 3,
	RANGER = 4,
	DRUID = 5,
	NECROMANCER = 6
}

## Elemental and physical damage schools.
enum DamageType {
	PHYSICAL = 0,
	FIRE = 1,
	FROST = 2,
	LIGHTNING = 3,
	SHADOW = 4,
	HOLY = 5,
	ARCANE = 6,
	POISON = 7,
	TRUE = 8
}

## Where a piece of gear is worn.
enum EquipSlot {
	WEAPON = 0,
	OFFHAND = 1,
	HEAD = 2,
	CHEST = 3,
	HANDS = 4,
	LEGS = 5,
	FEET = 6,
	RING = 7,
	AMULET = 8,
	BACK = 9
}

## Allegiance groups used for reputation and hostility.
enum Faction {
	ALLIANCE = 0,
	HORDE = 1,
	NEUTRAL = 2,
	BANDIT = 3,
	MONSTER = 4,
	MERCHANT_GUILD = 5,
	ARCANE_ORDER = 6
}

## Rarity tiers driving drop chance, tint, and value.
enum ItemRarity {
	COMMON = 0,
	UNCOMMON = 1,
	RARE = 2,
	EPIC = 3,
	LEGENDARY = 4,
	MYTHIC = 5
}

## What a vendor stocks and buys.
enum MerchantType {
	GENERAL = 0,
	BLACKSMITH = 1,
	ALCHEMIST = 2,
	JEWELER = 3,
	FENCE = 4
}

## Categorises quests for the journal.
enum QuestType {
	MAIN = 0,
	SIDE = 1,
	BOUNTY = 2,
	REPEATABLE = 3,
	EVENT = 4
}

## Branch of the skill tree a node belongs to.
enum SkillCategory {
	OFFENSE = 0,
	DEFENSE = 1,
	UTILITY = 2,
	PASSIVE = 3
}

## Buffs and debuffs applied in combat.
enum StatusEffect {
	NONE = 0,
	BURNING = 1,
	FROZEN = 2,
	POISONED = 3,
	STUNNED = 4,
	BLESSED = 5,
	REGEN = 6,
	SHIELDED = 7,
	SILENCED = 8,
	HASTED = 9,
	SLOWED = 10
}

## Ambient time bracket that gates events and spawns.
enum TimeOfDay {
	DAWN = 0,
	DAY = 1,
	DUSK = 2,
	NIGHT = 3
}

## Physical form of a weapon; drives animations.
enum WeaponType {
	SWORD = 0,
	AXE = 1,
	MACE = 2,
	DAGGER = 3,
	SPEAR = 4,
	BOW = 5,
	CROSSBOW = 6,
	STAFF = 7,
	WAND = 8
}
