extends "res://tests/qa_starter_learning_balance.gd"
## Reuse both native starter policies after the shared growth change.
## This runner writes only its own report/profile; losses remain losses.

const OUTPUT_DIRECTORY: String = "res://tests/profiles/current-fixes/starter-growth"
const OUTPUT_REPORT: String = OUTPUT_DIRECTORY + "/starter_growth_balance.json"
const OBSERVED_SOURCES: Array[String] = [
	"res://native/unit_growth.gd", "res://native/unit_skills.gd",
	"res://native/game.gd", "res://native/ground_combat.gd",
	"res://native/progress.gd", "res://native/units.json", "res://native/main.gd"
]

var balance_failures: Array[String] = []
var source_hashes: Dictionary = {}
var prior_report_hashes: Dictionary = {}
var initial_conditions: Dictionary = {}
var produced_observations: Array = []
var wave_observations: Array = []
var report_complete: bool = false
var process_exit_code: int = -1

func run() -> void:
	started_at = Time.get_ticks_msec()
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower()
	var allowed: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY).replace("\\", "/").to_lower() + "/"
	if not profile.begins_with(allowed) or DisplayServer.get_name() != "headless":
		push_error("Growth balance QA requires its own workspace headless profile")
		quit(2)
		return
	if not OS.get_cmdline_user_args().is_empty():
		push_error("Growth balance QA uses both original correct-answer policies without diagnostic overrides")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY)) != OK:
		push_error("Cannot create the isolated growth QA output directory")
		quit(2)
		return
	learner_policy = "correct"
	learning_probe_radius = 0.0
	learning_probe_hp_growth = -1.0
	source_hashes = current_source_hashes()
	prior_report_hashes = existing_learning_report_hashes()
	check(starter_policies.size() == 2, "The two original starter policies are retained")
	for policy in starter_policies:
		active_policy = policy
		var before_checks: int = checks
		var before_failures: int = failures.size()
		var result: Dictionary = await play_learning_policy()
		# The ancestor carries metadata from its old radius/HP diagnostic. These
		# constants are not measurements of today's production and are omitted.
		result.erase("intrusionRadius")
		result.erase("hpGrowthFromWave3")
		result.erase("hpGrowthOverride")
		result["initialConditions"] = initial_conditions.duplicate(true)
		result["productionObservations"] = produced_observations.duplicate(true)
		result["waveObservations"] = wave_observations.duplicate(true)
		result["functionalChecks"] = checks - before_checks
		result["functionalFailures"] = failures.slice(before_failures)
		result["balanceOutcome"] = "victory" if bool(result.victory) else "defeat"
		outcomes.append(result)
		if not bool(result.victory):
			balance_failures.append("%s: actual defeat at %.2f combat seconds; no forced survival or balance override" % [str(policy.name), float(result.seconds)])
		print("STARTER_GROWTH_BATTLE ", JSON.stringify({"policy":result.policy,"victory":result.victory,"seconds":result.seconds,"hp":result.hp,"kills":result.kills,"gold":result.gold,"answers":result.answers.size(),"learningGold":result.learningGold,"ordered":result.ordered,"born":result.born,"casualties":result.casualties,"upgrades":result.upgrades,"functionalFailures":result.functionalFailures}))
		write_learning_report()
	check(outcomes.size() == 2, "Both policies execute independently even when the first one wins")
	check(current_source_hashes() == source_hashes, "Observed growth and combat production sources remain stable during this run")
	check(existing_learning_report_hashes() == prior_report_hashes, "Existing starter learning reports are not overwritten")
	report_complete = true
	# A losing policy fails its balance criterion even when all system checks pass.
	process_exit_code = 0 if failures.is_empty() and balance_failures.is_empty() else 1
	write_learning_report()
	print("STARTER_GROWTH_QA checks=", checks, " functionalFailures=", failures.size(), " balanceFailures=", balance_failures.size(), " strategies=", outcomes.size(), " exitCode=", process_exit_code)
	quit(process_exit_code)

func prepare_geometry(game: Node2D, strategy: int) -> void:
	produced_observations.clear()
	wave_observations.clear()
	var levels: Dictionary = {}
	for definition in store.unit_catalog:
		var unit_id: String = str(definition.id)
		levels[unit_id] = store.army_level(unit_id)
		check(int(levels[unit_id]) == 1, "Fresh account retains permanent level one: " + unit_id)
	check(int(store.data.army.currency) == 180, "Actual initial permanent army funds are 180")
	check(store.data.maps.is_empty() and store.unlocked_units() == ["archer", "spear"], "No prior clear or extra unlock funds the starter policy")
	check(str(game.config.id) == "basic-forest" and int(game.config.stageNumber) == 1, "Played config is the actual first authored map")
	var authored_config: Dictionary = game.config.duplicate(true)
	# Native Main attaches the matching story for presentation after selection.
	# Compare the authored gameplay dictionary while retaining that native flow.
	authored_config.erase("story")
	check(authored_config == maps[0] and game.config == app.current_map, "Actual Main uses the unmodified selected first-map dictionary with its native story attachment")
	check(int(game.config.initialGold) == 280 and game.gold == 280, "Actual first-map combat funds are 280")
	check(int(game.config.unitLimit) == 14 and game.paths.size() == 2, "Current first-map unit cap and lane count are retained")
	check(int(game.config.totalWaves) == 10 and int(game.config.tierIndex) == 0 and int(game.config.level) == 1 and is_equal_approx(float(game.config.difficulty), 1.0), "Current first-map authored wave and difficulty numbers are retained")
	check(objective_health(game) == 26, "Current first-map objective starts with its authored 26 HP")
	check(game.battle_minutes == 5 and is_equal_approx(float(game.snapshot().battleTargetSeconds), 300.0), "The observed battle uses the actual five-minute target")
	initial_conditions = {"mapId":str(game.config.id),"stageNumber":int(game.config.stageNumber),"title":str(game.config.title),"armyCurrency":int(store.data.army.currency),"permanentLevels":levels,"unlocked":store.unlocked_units().duplicate(),"combatGold":game.gold,"objectiveHP":objective_health(game),"unitLimit":int(game.config.unitLimit),"paths":game.paths.size(),"sourceWaves":int(game.config.totalWaves),"difficulty":float(game.config.difficulty),"firstMapConfig":game.config.duplicate(true)}
	super.prepare_geometry(game, strategy)

func capture_learning_event(game: Node2D, event: Dictionary) -> void:
	super.capture_learning_event(game, event)
	if str(event.type) in ["placed", "recruited"]:
		for actor_id in event.get("actorIds", [int(event.actorId)]):
			var actor: Dictionary = game.ground_combat._unit(int(actor_id))
			check(not actor.is_empty(), "Completed production creates an actual actor")
			if actor.is_empty(): continue
			var stats: Dictionary = game._stats(actor)
			var public_state: Dictionary = game._unit_public(actor)
			check(int(actor.campaignLevel) == 1 and str(actor.type) in ["archer", "spear"], "Completed starter production retains genuine unlock and campaign level")
			produced_observations.append({"time":float(event.time),"unitId":int(actor.id),"type":str(actor.type),"jobId":int(event.get("jobId",-1)),"pathIndex":int(event.get("pathIndex",-1)),"campaignLevel":int(actor.campaignLevel),"hp":float(actor.hp),"maxHp":float(actor.maxHp),"armor":float(stats.armor),"damage":float(stats.damage),"interval":float(stats.interval),"range":float(stats.range),"skillIds":public_state.get("skillIds",[]).duplicate()})
	if str(event.type) == "waveend":
		wave_observations.append({"time":float(event.time),"wave":int(event.wave),"objectiveHP":objective_health(game),"gold":game.gold,"kills":game.kills,"living":game.units.size(),"producing":game.recruitment_queue.size(),"activeEnemies":game.enemies.size()})

func current_source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for source_path in OBSERVED_SOURCES:
		result[source_path] = FileAccess.get_sha256(source_path)
	return result

func existing_learning_report_hashes() -> Dictionary:
	var result: Dictionary = {}
	for file_name in DirAccess.get_files_at("res://tests"):
		if str(file_name).begins_with("qa_starter_learning_balance_") and str(file_name).ends_with(".json"):
			result[str(file_name)] = FileAccess.get_sha256("res://tests/" + str(file_name))
	return result

func write_learning_report() -> void:
	var output: FileAccess = FileAccess.open(OUTPUT_REPORT, FileAccess.WRITE)
	if output == null:
		push_error("Cannot write the isolated starter growth report")
		return
	output.store_string(JSON.stringify({"complete":report_complete,"checks":checks,"functionalPassed":failures.is_empty(),"functionalFailures":failures,"balancePassed":balance_failures.is_empty() and outcomes.size() == 2,"balanceFailures":balance_failures,"processExitCode":process_exit_code,"wallSeconds":float(Time.get_ticks_msec()-started_at)/1000.0,"sourceSHA256":source_hashes,"existingReportSHA256":prior_report_hashes,"results":outcomes,"scope":"CPU actual Main first authored map, 5-minute mode only. Fresh 180 permanent funds, all permanent levels one, archer/spear unlocks and native 280 combat gold. The two existing deterministic formations use real parallel production, upgrades, casualties and correct native task rewards. No survival, money, HP, geometry, unlock or production override. No conclusion about monk support, higher campaign levels, human learning ability or enjoyment. Scripted placement may differ from beginner play. Other authored maps may change independently; only the played first-map dictionary and numeric conditions are checked."}, "\t"))
	output.close()
