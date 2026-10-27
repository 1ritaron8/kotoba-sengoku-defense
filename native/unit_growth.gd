extends RefCounted
## One growth rule for combat, healing, defense and the barracks preview.
const BASE_HEALTH: Dictionary = {"archer":105.0,"spear":38.0,"samurai":175.0,"naginata":135.0,"monk":125.0,"ninja":160.0,"commander":210.0,"gunner":105.0}
const BASE_ARMOR: Dictionary = {"archer":.10,"spear":0.0,"samurai":.24,"naginata":.10,"monk":.10,"ninja":.10,"commander":.18,"gunner":.10}
const LEVEL_ARMOR_GAIN: float = .006
const MAX_ARMOR: float = .65
const SQUAD_DAMAGE_GAIN: float = .02
const SQUAD_HEALTH_GAIN: float = .015
const DEFAULT_RECRUITMENT_STAGES: Dictionary = {
	"archer":[{"level":1,"quantity":1},{"level":5,"quantity":2}],
	"spear":[{"level":1,"quantity":1},{"level":4,"quantity":3},{"level":8,"quantity":5}]
}

static func recruit_cost(definition: Dictionary, _permanent_level: int) -> int:
	return int(definition.get("cost",65))

static func recruit_quantity(type_name: String, permanent_level: int, definition: Dictionary = {}) -> int:
	var level: int = clampi(permanent_level,1,10)
	var quantity: int = 1
	var matched_level: int = 0
	for stage in definition.get("recruitmentStages",DEFAULT_RECRUITMENT_STAGES.get(type_name,[])):
		var stage_level: int = int(stage.get("level",1))
		if level>=stage_level and stage_level>=matched_level:
			quantity=maxi(1,int(stage.get("quantity",1)))
			matched_level=stage_level
	return quantity

static func _uses_squad_growth(type_name: String) -> bool:
	return type_name in ["archer","spear"]

static func _level_armor_bonus(unit: Dictionary) -> float:
	if _uses_squad_growth(str(unit.get("type",""))): return 0.0
	return LEVEL_ARMOR_GAIN*(clampi(int(unit.get("campaignLevel",1)),1,10)-1)

static func evolution(definition: Dictionary, permanent_level: int) -> Dictionary:
	var result: Dictionary = {"stage":0,"level":1,"damageMultiplier":1.0,"rangeMultiplier":1.0,"intervalMultiplier":1.0,"jp":definition.get("jp",""),"reading":definition.get("reading",""),"name":definition.get("name","")}
	for candidate in definition.get("evolutions",[]):
		if permanent_level>=int(candidate.get("level",99)): result=candidate.duplicate(true)
	return result

static func factors(unit: Dictionary, definition: Dictionary) -> Dictionary:
	var permanent_level: int = clampi(int(unit.get("campaignLevel",1)),1,10)
	var evolved: Dictionary = evolution(definition,permanent_level)
	# These units grow primarily by fielding more independent soldiers. Their
	# equipment evolution does not multiply every member's combat statistics.
	if _uses_squad_growth(str(unit.get("type",definition.get("id","")))):
		return {
			"damage":1.0+SQUAD_DAMAGE_GAIN*(permanent_level-1),
			"health":1.0+SQUAD_HEALTH_GAIN*(permanent_level-1),
			"range":1.0+.12*int(unit.get("elevation",0)),
			"interval":1.0,
			"healing":1.0,
			"supportResource":1.0,
			"armorBonus":0.0,
			"evolutionStage":int(evolved.stage)
		}
	var permanent_power: float = (1.0+.08*(permanent_level-1))*float(evolved.damageMultiplier)
	return {
		"damage":permanent_power,
		"health":(1.0+.05*(permanent_level-1))*(1.25 if int(evolved.stage)>=2 else 1.12 if int(evolved.stage)==1 else 1.0),
		"range":(1.0+.12*int(unit.get("elevation",0)))*(1.0+.012*(permanent_level-1))*float(evolved.rangeMultiplier),
		"interval":float(evolved.intervalMultiplier)/(1.0+.015*(permanent_level-1)),
		"healing":permanent_power,
		"supportResource":permanent_power,
		"armorBonus":_level_armor_bonus(unit),
		"evolutionStage":int(evolved.stage)
	}

static func max_health(unit: Dictionary, definition: Dictionary) -> float:
	return float(definition.get("hp",BASE_HEALTH.get(str(unit.get("type","")),105.0)))*float(factors(unit,definition).health)

static func base_armor(type_name: String) -> float:
	return float(BASE_ARMOR.get(type_name,.10))

static func armor(unit: Dictionary, has_armor_skill: bool = false) -> float:
	var bonus: float = _level_armor_bonus(unit)
	return clampf(base_armor(str(unit.get("type","")))+bonus+(.12 if has_armor_skill else 0.0),0.0,MAX_ARMOR)
