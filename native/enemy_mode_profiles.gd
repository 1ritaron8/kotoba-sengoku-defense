extends RefCounted
## Enemy arrival recipes only. This does not change terrain, costs, troop stats,
## learning anchors, campaign progression or the existing victory conditions.

const BASE_KINDS: Array[String] = ["raider","runner","shield","heavy"]
const ASSAULT_KINDS: Array[String] = ["enemy_archer","enemy_gunner"]
const PATTERNS: Array[String] = ["skirmish","formation","mounted_vanguard","rush"]
const MIN_KIND_WAVES: Dictionary = {"raider":1,"runner":2,"shield":3,"heavy":6}
const NINJA_STAGE: int = 15
const GUNNER_STAGE: int = 6

const PROFILES: Dictionary = {
	"defense":{
		"nameKo":"방어전 · 보병 전선과 정기 진지 습격",
		"recipe":["raider","shield","raider","runner","raider","heavy","shield","raider"],
		"patterns":["formation","mounted_vanguard","rush"],"assaultEvery":3,"rangedKinds":["enemy_archer"],"fortifications":true,
	},
	"onslaught":{
		"nameKo":"난전 · 빠른 보병과 동시 진지 압박",
		"recipe":["runner","raider","runner","shield","raider","runner","heavy","shield"],
		"patterns":["rush","mounted_vanguard","rush","formation"],"assaultEvery":2,"rangedKinds":["enemy_archer","enemy_gunner"],"fortifications":false,
	},
	"woodland":{
		"nameKo":"숲 접근 · 분산 보병과 측면 습격",
		"recipe":["raider","runner","raider","shield","raider","runner","heavy","raider"],
		"patterns":["rush","skirmish","formation"],"assaultEvery":3,"rangedKinds":["enemy_archer"],"fortifications":false,
	},
	"field":{
		"nameKo":"야전 · 보병 대형과 기마 선행",
		"recipe":["shield","raider","runner","raider","shield","runner","heavy","raider"],
		"patterns":["formation","mounted_vanguard","formation","rush"],"assaultEvery":3,"rangedKinds":["enemy_archer","enemy_gunner"],"fortifications":false,
	},
	"urban":{
		"nameKo":"성하 · 중장 보병과 조총 지원",
		"recipe":["shield","raider","heavy","raider","shield","raider","runner","heavy"],
		"patterns":["formation","skirmish","rush"],"assaultEvery":3,"rangedKinds":["enemy_gunner","enemy_archer"],"fortifications":false,
	},
	"crossing":{
		"nameKo":"도하 · 방패 선두와 후속 돌파",
		"recipe":["shield","raider","raider","runner","shield","heavy","raider","runner"],
		"patterns":["formation","rush","formation"],"assaultEvery":3,"rangedKinds":["enemy_archer"],"fortifications":false,
	},
	"landing":{
		"nameKo":"상륙 · 빠른 선발과 보병 후속",
		"recipe":["runner","raider","runner","shield","raider","heavy","raider","shield"],
		"patterns":["rush","formation","skirmish"],"assaultEvery":3,"rangedKinds":["enemy_archer","enemy_gunner"],"fortifications":false,
	},
	"escort":{
		"nameKo":"호송 · 추격병과 진지 압박",
		"recipe":["runner","raider","runner","shield","runner","heavy","raider","shield"],
		"patterns":["mounted_vanguard","rush","skirmish"],"assaultEvery":2,"rangedKinds":["enemy_archer"],"fortifications":false,
	},
	"mountain":{
		"nameKo":"산악 · 중장 대형과 소규모 접근",
		"recipe":["shield","raider","heavy","shield","raider","runner","heavy","raider"],
		"patterns":["formation","skirmish","formation"],"assaultEvery":3,"rangedKinds":["enemy_archer"],"fortifications":false,
	},
	"pass":{
		"nameKo":"고개 · 중장 선두와 빠른 후속",
		"recipe":["shield","heavy","raider","runner","shield","raider","runner","heavy"],
		"patterns":["formation","rush","mounted_vanguard"],"assaultEvery":3,"rangedKinds":["enemy_gunner","enemy_archer"],"fortifications":false,
	},
	"siege":{
		"nameKo":"공성 · 방패 보병과 고정 사격 진지",
		"recipe":["shield","raider","heavy","shield","raider","heavy","runner","shield"],
		"patterns":["formation","skirmish","formation","rush"],"assaultEvery":2,"rangedKinds":["enemy_gunner","enemy_archer"],"fortifications":true,
	},
	"interception":{
		"nameKo":"추격 차단 · 빠른 선봉과 후속 보병",
		"recipe":["runner","raider","runner","shield","runner","raider","heavy","runner"],
		"patterns":["mounted_vanguard","rush","mounted_vanguard","formation"],"assaultEvery":3,"rangedKinds":["enemy_archer","enemy_gunner"],"fortifications":false,
	},
}

const THEME_PROFILES: Dictionary = {
	"forest":"woodland","farm":"field","town":"urban","river":"crossing",
	"harbor":"landing","convoy":"escort","temple":"mountain","snow":"pass","siege":"siege",
}
const MODE_PROFILES: Dictionary = {
	"ambush":"woodland","siege":"siege","encirclement":"siege","advance":"siege","assault":"siege",
	"escort":"escort","convoy":"escort","retreat":"escort","withdrawal":"escort","rearguard":"escort",
	"interception":"interception","pursuit":"interception","landing":"landing","crossing":"crossing",
}
const REVISION: String = "enemy-mode-profiles-3-road-ranged"

static func _first_stage(stage: Dictionary) -> bool:
	return str(stage.get("id",""))=="basic-forest" and int(stage.get("stageNumber",1))==1

static func _profile_id(stage: Dictionary) -> String:
	var scenario: Dictionary = stage.get("scenario",{})
	var authored: String = str(scenario.get("enemyProfile",""))
	if PROFILES.has(authored): return authored
	var mode: String = str(stage.get("mode","")).to_lower()
	if MODE_PROFILES.has(mode): return str(MODE_PROFILES[mode])
	var historical: Dictionary = stage.get("historicalBattlefield",{})
	var theme: String = str(historical.get("legacyEncounterTheme",stage.get("theme","forest"))).to_lower()
	return str(THEME_PROFILES.get(theme,"field"))

static func _build_profile(stage: Dictionary) -> Dictionary:
	var id: String = _profile_id(stage)
	var source: Dictionary = PROFILES[id]
	var opening: bool = _first_stage(stage) and id not in ["onslaught","siege"]
	var ranged_kinds: Array = source.rangedKinds.duplicate()
	if opening:
		# Stage01 retains its existing opening roster, commander triggers and
		# two-member local assaults. New geometry and lessons remain independent.
		ranged_kinds=["enemy_archer"]
	var scenario: Dictionary = stage.get("scenario",{})
	var settings: Dictionary = scenario.get("enemySettings",{})
	var combat_enabled: bool = bool(scenario.get("combatEnabled",true))
	var result: Dictionary = {
		"revision":REVISION,"id":id,"nameKo":str(source.nameKo),
		"recipe":source.recipe.duplicate(),"patterns":source.patterns.duplicate(),
		"preserveOpeningRoster":opening,"mainPressure":"continuous" if combat_enabled else "disabled","combatEnabled":combat_enabled,
		"scenarioId":str(scenario.get("stageId","")),"missionMode":str(scenario.get("missionMode","")),
		"firstSpawn":"existing_offscreen_route_entry","stats":"existing_origin_kind",
		"assault":{"enabled":combat_enabled,"startWave":3,"everyWaves":3 if opening else int(source.assaultEvery),"groupSize":2,"rangedKinds":ranged_kinds,"allRangedZones":true,"appendLateMembers":false,"mainIngressOnly":true,"movement":"road_only","targets":"nearby_friendly_emplacement_troops"},
		"fortification":{"enabled":bool(source.fortifications) and not opening,"minStage":1 if id=="siege" else NINJA_STAGE,"startWave":3,"everyWaves":2,"maxPerWave":1,"kinds":["enemy_archer","enemy_gunner"],"requireOffscreenIngress":true,"requiresReachableStation":true,"targetContract":"same_enemy_id_hp_stationary_fortification"},
		"changesMissionConditions":false,"changesTerrain":false,"changesUnitStats":false,
	}
	if opening: result.patterns=["formation","mounted_vanguard","rush"]
	var authored_patterns: Array = settings.get("patterns",[])
	if not authored_patterns.is_empty() and not opening:
		var supported: Array[String] = []
		for value in authored_patterns:
			if str(value) in PATTERNS: supported.append(str(value))
		if not supported.is_empty(): result.patterns=supported
	var authored_assault: Dictionary = settings.get("assault",{})
	var assault: Dictionary = result.assault
	assault.enabled=combat_enabled and bool(authored_assault.get("enabled",true))
	if not opening:
		assault.startWave=maxi(3,int(authored_assault.get("startWave",assault.startWave)))
		assault.everyWaves=maxi(2,int(authored_assault.get("everyWaves",assault.everyWaves)))
	# Cohort size and target acquisition remain the existing finite two-member
	# local raid contract. Scenario data cannot append reinforcements or alter it.
	var authored_fort: Dictionary = settings.get("fortification",{})
	var fort: Dictionary = result.fortification
	fort.enabled=combat_enabled and not opening and bool(authored_fort.get("enabled",fort.enabled))
	fort.minStage=maxi(1,int(authored_fort.get("minStage",fort.minStage)))
	fort.startWave=maxi(3,int(authored_fort.get("startWave",fort.startWave)))
	fort.everyWaves=maxi(2,int(authored_fort.get("everyWaves",fort.everyWaves)))
	return result

static func apply(base: Dictionary) -> Dictionary:
	var stage: Dictionary = base.duplicate(true)
	stage["enemyModeProfile"]=_build_profile(stage)
	return stage

static func profile_for(stage: Dictionary) -> Dictionary:
	var recorded: Variant = stage.get("enemyModeProfile",{})
	var scenario: Dictionary = stage.get("scenario",{})
	if recorded is Dictionary and str(recorded.get("revision",""))==REVISION and str(recorded.get("id",""))==_profile_id(stage) and str(recorded.get("scenarioId",""))==str(scenario.get("stageId","")):
		return recorded
	return _build_profile(stage)

static func original_kind(stage: Dictionary, wave_number: int, index: int, fallback: String) -> String:
	var profile: Dictionary = profile_for(stage)
	if bool(profile.preserveOpeningRoster): return fallback
	var recipe: Array = profile.get("recipe",[])
	if recipe.is_empty(): return fallback
	var kind: String = str(recipe[posmod(index+maxi(0,wave_number-1),recipe.size())])
	if kind not in BASE_KINDS: return fallback
	return kind if wave_number>=int(MIN_KIND_WAVES.get(kind,1)) else "raider"

static func attack_pattern(stage: Dictionary, wave_number: int) -> String:
	if wave_number<=2: return "skirmish"
	var cycle: Array = profile_for(stage).get("patterns",[])
	if cycle.is_empty(): return "skirmish"
	var value: String = str(cycle[posmod(wave_number-3,cycle.size())])
	return value if value in PATTERNS else "skirmish"

static func assault_settings(stage: Dictionary) -> Dictionary:
	return profile_for(stage).get("assault",{}).duplicate(true)

static func assault_kind(stage: Dictionary, member: int, wave_number: int) -> String:
	var settings: Dictionary = assault_settings(stage)
	var ranged: Array = settings.get("rangedKinds",["enemy_archer"])
	if ranged.is_empty(): return "enemy_archer"
	var ordinal: int = maxi(0,wave_number-int(settings.get("startWave",3)))/maxi(1,int(settings.get("everyWaves",3)))
	var kind: String = str(ranged[posmod(ordinal+member,ranged.size())])
	if kind=="enemy_gunner" and int(stage.get("stageNumber",1))<GUNNER_STAGE and str(profile_for(stage).id)!="siege": return "enemy_archer"
	return kind if kind in ["enemy_archer","enemy_gunner"] else "enemy_archer"

static func fortification_settings(stage: Dictionary) -> Dictionary:
	return profile_for(stage).get("fortification",{}).duplicate(true)

static func fortification_kind(stage: Dictionary, wave_number: int) -> String:
	var settings: Dictionary = fortification_settings(stage)
	var kinds: Array = settings.get("kinds",["enemy_archer","enemy_gunner"])
	if kinds.is_empty(): return "enemy_archer"
	var ordinal: int = maxi(0,wave_number-int(settings.get("startWave",3)))/maxi(1,int(settings.get("everyWaves",2)))
	var kind: String = str(kinds[posmod(ordinal,kinds.size())])
	return kind if kind in ["enemy_archer","enemy_gunner"] else "enemy_archer"
