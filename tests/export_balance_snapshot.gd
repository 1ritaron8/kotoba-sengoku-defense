extends SceneTree
## Read-only export of current runtime calculations; never reads or writes a player save.
const Battle = preload("res://native/game.gd")
const ProgressStore = preload("res://native/progress.gd")
const Duration = preload("res://native/battle_duration.gd")
const Skills = preload("res://native/unit_skills.gd")
const SNAPSHOT_ROOT = "res://tests/profiles/combat-growth-removal-20261007/source-snapshot/"
const OUTPUT_PATH = "res://tests/profiles/combat-growth-removal-20261007/runtime_balance.json"
var checks: int = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func read_json(name: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT_ROOT+name))

func unit_template(definition: Dictionary, level: int, id: int = 1) -> Dictionary:
	var evolution: int = 2 if level>=8 else 1 if level>=4 else 0
	return {"id":id,"type":definition.id,"definition":definition.duplicate(true),"campaignLevel":level,"evolution":evolution,"elevation":0,"position":Vector2(.5,.5),"hp":1.0,"maxHp":1.0,"aim":Vector2.LEFT}

func friendly_row(game: Node2D, definition: Dictionary, level: int) -> Dictionary:
	var unit: Dictionary = unit_template(definition,level)
	var stats: Dictionary = game._stats(unit)
	var hp: float = game.ground_combat.max_health(unit)
	var base_armor: float = .24 if str(definition.id)=="samurai" else .18 if str(definition.id) in ["spear","commander"] else .10
	var defense: Dictionary = game.unit_skills.modify_incoming(unit,100.0,base_armor)
	return {"id":definition.id,"permanentLevel":level,"damage":stats.damage,"range":stats.range,"interval":stats.interval,"nominalDps":float(stats.damage)/float(stats.interval),"health":hp,"armor":defense.armor,"capacity":game.ground_combat.capacity(unit),"contactReach":game.ground_combat.reach(unit),"recruitQuantity":game.unit_skills.recruit_quantity(str(definition.id),level),"skillIds":game.unit_skills.skill_ids(unit),"evolutionStage":unit.evolution,"healAmount":stats.healAmount,"healInterval":stats.healInterval,"supportStats":stats.supportStats}

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if DisplayServer.get_name()!="headless" or not profile.begins_with("c:/jp_df/tests/profiles/combat-growth-removal-20261007/"):
		push_error("Balance export requires an isolated headless workspace profile")
		quit(2)
		return
	var manifest: Dictionary = read_json("snapshot_manifest.json")
	# Data files can be changing for the separately authorised terrain task.
	# All runtime formulas must still match the captured source version.
	for entry in manifest.files:
		if str(entry.file).ends_with(".gd"):
			verify(FileAccess.get_sha256("res://native/"+str(entry.file))==str(entry.sha256),"Formula source matches snapshot: "+str(entry.file))
	var maps: Array = read_json("maps.json")
	var catalog: Array = read_json("units.json").units
	var store = ProgressStore.new()
	var game: Node2D = Battle.new()
	game.configure_roster(catalog,catalog.map(func(item: Dictionary): return str(item.id)),{})
	game.ground_combat.bind(game)
	game.unit_skills.bind(game)
	game.set_seed(680406)
	var report: Dictionary = {"snapshot":manifest,"unitDefinitions":catalog,"friendlyLevels":[],"permanentUpgradeCosts":[],"stages":[],"checks":0,"failures":[]}
	for definition in catalog:
		for level in range(1,11):
			var row: Dictionary = friendly_row(game,definition,level)
			var displayed: Dictionary = store.army_stats(str(definition.id),level)
			verify(is_equal_approx(float(row.damage),float(displayed.damage)),"Runtime and barracks friendly damage: %s Lv%d" % [definition.id,level])
			verify(is_equal_approx(float(row.range),float(displayed.range)),"Runtime and barracks friendly range: %s Lv%d" % [definition.id,level])
			verify(is_equal_approx(float(row.interval),float(displayed.interval)),"Runtime and barracks friendly interval: %s Lv%d" % [definition.id,level])
			verify(is_equal_approx(float(row.health),float(displayed.health)) and is_equal_approx(float(row.armor),float(displayed.armor)) and is_equal_approx(float(row.healAmount),float(displayed.healAmount)),"Runtime and barracks HP armor healing: %s Lv%d" % [definition.id,level])
			verify(float(row.health)>0 and float(row.interval)>0 and float(row.armor)>=0 and float(row.armor)<1,"Valid friendly stats: %s Lv%d" % [definition.id,level])
			report.friendlyLevels.append(row)
	for level in range(1,10):
		store.data.army.levels.archer=level
		report.permanentUpgradeCosts.append({"from":level,"to":level+1,"cost":store.army_upgrade_cost("archer")})
	for stage in maps:
		var row: Dictionary = {"stageNumber":stage.stageNumber,"stageId":stage.id,"config":stage,"friendlyLevels":[],"enemyTemplates":[],"modes":{}}
		game.load_map(stage,10)
		for definition in catalog:
			for level in [1,3,4,5,8,10]: row.friendlyLevels.append(friendly_row(game,definition,level))
		var variants: Array = [{"kind":"raider","origin":"raider"},{"kind":"runner","origin":"runner"},{"kind":"shield","origin":"shield"},{"kind":"heavy","origin":"heavy"},{"kind":"commander","origin":"commander"},{"kind":"enemy_archer","origin":"raider"},{"kind":"enemy_gunner","origin":"shield"},{"kind":"enemy_gunner","origin":"heavy"},{"kind":"enemy_cavalry","origin":"runner"},{"kind":"enemy_samurai","origin":"heavy"}]
		for variant in variants:
			for source_wave in range(1,int(stage.totalWaves)+1):
				game.enemies.clear()
				var enemy: Dictionary = game._spawn_enemy(str(variant.kind),source_wave,{"originKind":variant.origin,"pathIndex":0})
				verify(not enemy.is_empty() and float(enemy.maxHp)>0 and float(enemy.speed)>0,"Valid enemy stats: %s %s/%s s%d" % [stage.id,variant.kind,variant.origin,source_wave])
				row.enemyTemplates.append({"kind":variant.kind,"originKind":variant.origin,"sourceWave":source_wave,"health":enemy.maxHp,"baseMoveSpeed":enemy.speed,"armor":enemy.armor,"objectiveDamage":enemy.damage,"reward":enemy.reward,"attackDamage":(4.0+float(source_wave)*.6)*float(enemy.damage),"meleeInterval":1.1 if str(variant.origin) in ["heavy","commander"] else .95,"attackRange":enemy.get("attackRange",0),"rangedInterval":enemy.get("attackInterval",0)})
		for minutes in [10,20]:
			game.load_map(stage,minutes)
			var mode: Dictionary={"minutes":minutes,"targetSeconds":game.battle_plan.targetSeconds,"totalWaves":game.total_waves,"baseTotalWaves":game.battle_plan.baseTotalWaves,"waves":[]}
			for number in range(1,game.total_waves+1):
				game.wave=number-1
				game.enemies.clear()
				game.spawn_queue.clear()
				game.spawn_source_waves.clear()
				game.spawn_metadata.clear()
				game.elapsed=float(game.battle_plan.waves[number-1].startSeconds)
				game._begin_wave()
				var plan: Dictionary=game._timed_wave()
				var wave: Dictionary={"wave":number,"startSeconds":plan.startSeconds,"endSeconds":plan.endSeconds,"planBaseIndex":plan.baseIndex,"planSourceWave":plan.sourceWave,"activeCap":plan.activeCap,"refillCount":plan.refillCount,"refillThreshold":plan.refillThreshold,"initialScheduledCount":game.spawn_queue.size(),"spawnDelay":game._spawn_delay(),"spawnInterval":game._spawn_interval(),"approachFactor":game._approach_march_factor(),"formationPattern":game.attack_pattern,"entries":[],"composition":{},"stipend":40+number*3,"traitSupply":0}
				var supply: Dictionary=game._trait().get("waveGold",{})
				if not supply.is_empty() and number%maxi(1,int(supply.get("every",1)))==0: wave.traitSupply=maxi(0,int(supply.get("amount",0)))
				for index in range(game.spawn_queue.size()):
					var metadata: Dictionary=game.spawn_metadata[index]
					var kind: String=str(game.spawn_queue[index])
					var source_wave: int=int(game.spawn_source_waves[index])
					var enemy: Dictionary=game._spawn_enemy(kind,source_wave,metadata)
					var item: Dictionary={"kind":kind,"originKind":metadata.originKind,"sourceWave":source_wave,"health":enemy.maxHp,"baseMoveSpeed":enemy.speed,"armor":enemy.armor,"objectiveDamage":enemy.damage,"reward":enemy.reward,"attackDamage":(4.0+float(source_wave)*.6)*float(enemy.damage),"fortificationRequested":bool(metadata.get("fortification",false)),"fortificationPossibleInProbe":bool(enemy.get("fortification",false))}
					wave.entries.append(item)
					wave.composition[kind]=int(wave.composition.get(kind,0))+1
					verify(int(enemy.sourceWave)==source_wave and int(enemy.counterWave)==source_wave,"Timed enemy HP and counterattack share source wave")
				verify(wave.entries.size()==int(wave.initialScheduledCount),"Exact scheduled roster count")
				mode.waves.append(wave)
			verify(is_equal_approx(float(mode.waves[-1].endSeconds),float(minutes)*60.0),"Timed deadline matches chosen duration")
			row.modes[str(minutes)]=mode
		report.stages.append(row)
	verify(report.friendlyLevels.size()==80,"All eight friendly classes and ten levels exported")
	verify(report.stages.size()==40,"All forty campaign stages exported")
	var stage_ids: Dictionary={}
	for row in report.stages:
		verify(not stage_ids.has(str(row.stageId)),"Unique stage id")
		stage_ids[str(row.stageId)]=true
	report.checks=checks
	report.failures=failures
	var output: FileAccess=FileAccess.open(OUTPUT_PATH,FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	game.free()
	print("BALANCE_RUNTIME_EXPORT checks=",checks," failures=",failures.size()," units=",report.friendlyLevels.size()," stages=",report.stages.size()," output=",OUTPUT_PATH)
	for failure in failures: push_error(str(failure))
	quit(0 if failures.is_empty() else 1)
