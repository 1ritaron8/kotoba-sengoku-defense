extends RefCounted
## Historical story selects a scenario. This registry never creates a map,
## unlocks a stage, or changes the existing victory/arrival predicates.

const EnemyProfiles = preload("res://native/enemy_mode_profiles.gd")
const CATALOG_PATH: String = "res://native/campaign_scenarios.json"
const REVISION: String = "campaign-scenarios-1"

static var _loaded: bool = false
static var _catalog: Dictionary = {}
static var _by_id: Dictionary = {}

static func _ensure_loaded() -> void:
	if _loaded: return
	_loaded=true
	if not FileAccess.file_exists(CATALOG_PATH):
		push_error("Campaign scenario registry is missing: "+CATALOG_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary or str(parsed.get("revision",""))!=REVISION:
		push_error("Campaign scenario registry has an unsupported format.")
		return
	_catalog=parsed
	for raw in _catalog.get("stages",[]):
		if not raw is Dictionary: continue
		var id: String = str(raw.get("stageId",""))
		if id.is_empty() or _by_id.has(id):
			push_error("Campaign scenario IDs must be nonempty and unique: "+id)
			continue
		_by_id[id]=raw

static func catalog() -> Dictionary:
	_ensure_loaded()
	return _catalog.duplicate(true)

static func scenario_for(stage_id: String) -> Dictionary:
	_ensure_loaded()
	var source: Dictionary = _by_id.get(stage_id,{})
	return source.duplicate(true)

static func _story_entry(story: Dictionary, stage_id: String) -> Dictionary:
	if str(story.get("stageId",""))==stage_id: return story
	for raw in story.get("stages",[]):
		if raw is Dictionary and str(raw.get("stageId",""))==stage_id: return raw
	return {}

static func apply(base: Dictionary, story: Dictionary = {}) -> Dictionary:
	var stage: Dictionary = base.duplicate(true)
	var id: String = str(stage.get("id",""))
	var scenario: Dictionary = scenario_for(id)
	# Old player-selection metadata must not outrank the authored story.
	stage.erase("combatMode")
	if not scenario.is_empty():
		var source_story: Dictionary = _story_entry(story,id)
		scenario["storyResolved"]=not source_story.is_empty()
		scenario["storyEventMatches"]=source_story.is_empty() or str(source_story.get("battleEventId",""))==str(scenario.get("battleEventId",""))
		stage["scenario"]=scenario
		stage["missionMode"]=str(scenario.missionMode)
		stage["campaignScenarioRevision"]=REVISION
	return EnemyProfiles.apply(stage)
