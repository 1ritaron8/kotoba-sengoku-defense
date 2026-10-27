extends SceneTree
## Explicit story assignments and truthful implementation boundaries.
const Scenarios = preload("res://native/campaign_scenarios.gd")
const Profiles = preload("res://native/enemy_mode_profiles.gd")
const EXPECTED_MODES: Dictionary = {
	"defense":[9,10,17,31,36],
	"withdrawal":[1,8,11,19,32,35],
	"escort":[6,16,26],
	"advance":[2,3,5,7,12,15,18,20,22,29,30,33,37],
	"interception":[13],
	"encirclement":[21,23,25,38,39,40],
	"handoff":[4,14,24,27,28,34],
}
var checks: int = 0
var failures: Array[String] = []

func _init() -> void: call_deferred("run")

func check(value: bool, note: String) -> void:
	checks+=1
	if not value: failures.append(note)

func run() -> void:
	var catalog: Dictionary = Scenarios.catalog()
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var story_by_id: Dictionary = {}
	var seen_ids: Dictionary = {}
	var seen_numbers: Dictionary = {}
	var registered_ids: Array[String] = []
	for entry in story.get("stages",[]): story_by_id[str(entry.stageId)]=entry
	for map in maps: registered_ids.append(str(map.id))
	check(catalog.get("stages",[]).size()==40,"Scenario catalog is not 40 entries")
	check(story_by_id.size()==40,"Source story is not 40 entries")
	check(not bool(catalog.implementationStatus.newFortyMapsImplemented),"Registry falsely claims 40 maps")
	for entry in catalog.get("stages",[]):
		var id: String = str(entry.stageId)
		var number: int = int(entry.stageNumber)
		var mode: String = str(entry.missionMode)
		check(not seen_ids.has(id) and not seen_numbers.has(number),"Duplicate scenario identity: "+id)
		seen_ids[id]=true; seen_numbers[number]=true
		check(story_by_id.has(id),"Scenario has no historical story: "+id)
		if not story_by_id.has(id): continue
		var historical: Dictionary = story_by_id[id]
		check(number==int(historical.stageNumber),"Story stage number changed: "+id)
		check(str(entry.battleEventId)==str(historical.battleEventId),"Historical event changed: "+id)
		check(str(entry.battleJP)==str(historical.get("battleJP","")),"Japanese proper name changed: "+id)
		check(EXPECTED_MODES.has(mode) and number in EXPECTED_MODES.get(mode,[]),"Mission does not match approved story plan: "+id)
		check(Profiles.PROFILES.has(str(entry.enemyProfile)),"Unsupported enemy recipe: "+id)
		check(not str(entry.localObjectiveKo).is_empty() and not str(entry.phaseBriefKo).is_empty(),"Missing local objective or phase: "+id)
		check(not str(entry.historyOutcomeKo).is_empty() and entry.historySourceURLs.size()>0,"Missing historical result/source: "+id)
		check(bool(entry.historyAndMissionSeparate),"Mission success conflated with historical victory: "+id)
		check(str(entry.objectiveContract.status)=="not_implemented","Actual arrival/capture predicates falsely claimed implemented: "+id)
		check(not bool(entry.objectiveContract.historicalCommanderKillRequired),"Historical commander kill required: "+id)
		check(entry.plannedPhases.size()==3,"Missing planned phase sequence: "+id)
		for phase in entry.plannedPhases:
			check(str(phase.implementationStatus)=="not_implemented","Planned phase claimed implemented: "+id)
		var map_registered: bool = id in registered_ids
		check((str(entry.implementationStatus.map)=="registered_existing_stage01")==map_registered,"Map implementation boundary incorrect: "+id)
		if mode=="handoff":
			check(not bool(entry.combatEnabled) and not bool(entry.enemySettings.assault.enabled) and not bool(entry.enemySettings.fortification.enabled),"Handoff spawns fictional combat: "+id)
		if mode=="encirclement":
			check(bool(entry.objectiveContract.eventCountStartsAtZero) and not bool(entry.objectiveContract.timeElapsedAloneCompletesMission),"Encirclement can complete without events/arrival: "+id)
	for number in range(1,41): check(seen_numbers.has(number),"Missing scenario number "+str(number))
	var cannon: Dictionary = catalog.plannedUnitRoles.cannon_crew
	check(str(cannon.implementationStatus)=="not_implemented" and str(cannon.distinctFrom)=="gunner","Cannon confused with implemented matchlock")
	check(str(cannon.range)=="long" and bool(cannon.noLureMechanic),"Cannon role lost long-range/no-lure contract")
	check(not bool(cannon.historyClaim),"Planned cannon use presented as sourced battle history")
	for id in cannon.intendedStageIds:
		var intended: Dictionary = Scenarios.scenario_for(str(id))
		check(not intended.is_empty() and "cannon_crew" in intended.get("plannedRoles",[]),"Cannon intended-stage references disagree: "+str(id))
		check(str(intended.get("missionMode","")) in ["advance","encirclement"],"Cannon planned in noncombat/retreat mission: "+str(id))
	var input: Dictionary = maps[0].duplicate(true)
	input.merge({"combatMode":"siege","mode":"siege","theme":"siege"},true)
	var before: String = JSON.stringify(input)
	var applied: Dictionary = Scenarios.apply(input,story)
	check(JSON.stringify(input)==before,"Scenario application mutated caller stage")
	check(str(applied.missionMode)=="withdrawal" and str(applied.enemyModeProfile.id)=="woodland","First story lost authority to caller-selected mode/theme")
	check(not applied.has("combatMode"),"Selectable combat-mode metadata retained")
	check(bool(applied.scenario.storyResolved) and bool(applied.scenario.storyEventMatches),"Actual story lookup not resolved")
	check(Scenarios.apply(applied,story)==applied,"Scenario application not idempotent")
	var copied: Dictionary = Scenarios.scenario_for("basic-forest")
	copied.enemySettings.assault.everyWaves=999
	check(int(Scenarios.scenario_for("basic-forest").enemySettings.assault.everyWaves)==3,"Scenario lookup leaked a mutable cached dictionary")
	check(Scenarios.scenario_for("nonexistent-map").is_empty(),"Registry silently invented a map/scenario")
	var art: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/painted-v1/manifest.json"))
	check(art.factions.enemy.frames.has("commander"),"Active first-map enemy boss has no painted role")
	check(str(art.roleAliases.get("enemy_cavalry",""))=="cavalry","Cavalry incorrectly aliases the foot general")
	print(JSON.stringify({"suite":"campaign-scenarios","checks":checks,"failures":failures,"registeredMapCount":maps.size(),"scenarioCount":seen_ids.size(),"scope":"historical scenario/profile data, noncombat metadata and boss asset coverage; no claim of 40 implemented maps or actual mission-arrival predicates"}))
	quit(0 if failures.is_empty() else 1)
