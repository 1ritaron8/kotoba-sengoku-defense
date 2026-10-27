extends SceneTree
## Profile data contract only: historical scenario selection, supported enemy
## recipes, finite local raids and reachable/offscreen station requirements.
const Profiles = preload("res://native/enemy_mode_profiles.gd")
const Scenarios = preload("res://native/campaign_scenarios.gd")
var failures: Array[String] = []
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition: failures.append(message)

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var geometry: Dictionary = {
		"id":"basic-forest","stageNumber":1,"mode":"ambush","theme":"forest",
		"initialGold":280,"recruitCost":60,"difficulty":1.0,"totalWaves":10,
		"paths":[{"points":[{"x":1.07,"y":-.05},{"x":.255,"y":.79}]}],
		"historicalBattlefield":{"learningSupportAnchors":{"archer":{"x":.28,"y":.76}}},
	}
	var original: String = JSON.stringify(geometry)
	var recipes: Dictionary = {}
	var patterns: Dictionary = {}
	for authored in Scenarios.catalog().get("stages",[]):
		# Copying geometry is a pure data fixture; this does not register 40 maps.
		var source: Dictionary = geometry.duplicate(true)
		source.merge({"id":str(authored.stageId),"stageNumber":int(authored.stageNumber),"combatMode":"siege"},true)
		var before: String = JSON.stringify(source)
		var runtime: Dictionary = Scenarios.apply(source)
		var id: String = str(authored.stageId)
		var profile: Dictionary = runtime.enemyModeProfile
		check(JSON.stringify(source)==before,"Input stage mutated: "+id)
		check(runtime.paths==source.paths and runtime.historicalBattlefield==source.historicalBattlefield,"Geometry or learning changed: "+id)
		for key in ["initialGold","recruitCost","difficulty","totalWaves"]:
			check(runtime[key]==source[key],"Economy or difficulty changed: "+id+"/"+key)
		check(str(profile.id)==str(authored.enemyProfile),"Story enemy profile not authoritative: "+id)
		check(not runtime.has("combatMode"),"Player mode selection metadata survived: "+id)
		check(bool(profile.combatEnabled)==bool(authored.combatEnabled),"Noncombat story gate missing: "+id)
		var roster: Array = []
		var cycle: Array = []
		for wave_number in range(1,11):
			var pattern: String = Profiles.attack_pattern(runtime,wave_number)
			cycle.append(pattern)
			check(pattern in Profiles.PATTERNS,"Unsupported attack pattern: "+id)
			for ordinal in range(12):
				var kind: String = Profiles.original_kind(runtime,wave_number,ordinal,"raider")
				roster.append(kind)
				check(kind in Profiles.BASE_KINDS,"Unsupported main enemy kind: "+kind)
				check(wave_number>=int(Profiles.MIN_KIND_WAVES.get(kind,1)),"Early main enemy kind: "+kind)
		recipes[id]=roster
		patterns[id]=cycle
		var assault: Dictionary = Profiles.assault_settings(runtime)
		check(int(assault.groupSize)==2 and not bool(assault.appendLateMembers),"Raid must stay a finite committed group: "+id)
		check(bool(assault.enabled)==bool(authored.combatEnabled),"Noncombat raid gate: "+id)
		check(str(profile.mainPressure)==("continuous" if bool(authored.combatEnabled) else "disabled"),"Main-pressure contract: "+id)
		check(bool(assault.allRangedZones),"Multi-emplacement contract: "+id)
		for member in range(2):
			check(Profiles.assault_kind(runtime,member,3) in Profiles.ASSAULT_KINDS,"Unsupported raid type: "+id)
		var tower: Dictionary = Profiles.fortification_settings(runtime)
		check(bool(tower.requireOffscreenIngress) and bool(tower.requiresReachableStation),"Tower physical arrival contract: "+id)
		check(bool(tower.enabled)==bool(authored.enemySettings.fortification.enabled),"Authored stationary-target gate: "+id)
		check(int(tower.maxPerWave)==1,"Unlimited stationary structure group: "+id)
		check(Profiles.apply(runtime)==runtime,"Profile apply not idempotent: "+id)
	check(recipes["basic-farm"]!=recipes["basic-town"],"Fast advance and siege have identical recipes")
	check(patterns["basic-farm"]!=patterns["basic-town"],"Fast advance and siege have identical attack patterns")
	var first: Dictionary = Scenarios.apply(geometry)
	check(bool(first.enemyModeProfile.preserveOpeningRoster),"First learning stage lost original opening roster")
	check(not bool(Profiles.fortification_settings(first).enabled),"First straight learning map gained a stationary structure")
	check(JSON.stringify(geometry)==original,"Base stage mutated through nested profile data")
	print(JSON.stringify({"suite":"enemy-mode-profiles","checks":checks,"failures":failures,"engineEvidence":"40 scenario/profile data only; no 40-map or mission-arrival implementation claim"}))
	quit(0 if failures.is_empty() else 1)
