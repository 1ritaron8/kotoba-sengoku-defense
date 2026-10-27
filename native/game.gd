extends Node2D

signal state_changed(state: Dictionary)
signal hud_state_changed(state: Dictionary)
signal game_event(event: Dictionary)
## Native visual/audio subscribers must not mutate authoritative battle state.
## Mutating observers use game_event, whose callbacks invalidate query caches.
signal presentation_event(event: Dictionary)
signal wave_ended(info: Dictionary)
signal wave_started(info: Dictionary)
signal battle_finished(result: Dictionary)

const UNIT_TYPES = [
	{"id":"archer","name":"궁병","jp":"弓兵","reading":"きゅうへい","damage":15.0,"range":0.205,"interval":0.85,"color":"87a48f","weight":40},
	{"id":"spear","name":"창병","jp":"槍兵","reading":"そうへい","damage":4.4,"hp":38.0,"range":0.145,"interval":0.95,"cost":25,"recruitSeconds":1.25,"color":"adb697","weight":32},
	{"id":"samurai","name":"사무라이","jp":"侍","reading":"さむらい","damage":31.0,"range":0.145,"interval":0.76,"color":"bd8064","weight":20},
	{"id":"commander","name":"장수","jp":"武将","reading":"ぶしょう","damage":26.0,"range":0.19,"interval":1.0,"color":"d1b865","weight":8},
]
const ANIMATION_ROWS = {"idle":0,"walk":1,"attack":2,"death":3}
const ANIMATION_FPS = {"idle":5.0,"walk":9.0,"attack":12.0,"death":9.0}
const ANIMATED_UNIT_KEYS = ["archer","spear","samurai","commander","enemy_light","enemy_heavy"]
const ACTOR_COLOR_SHADER = "shader_type canvas_item; render_mode unshaded; uniform float saturation = 0.72; varying vec4 sprite_tint; void vertex() { sprite_tint = COLOR; } void fragment() { vec4 texel = texture(TEXTURE, UV); float grey = dot(texel.rgb, vec3(0.2126, 0.7152, 0.0722)); texel.rgb = mix(vec3(grey), texel.rgb, saturation); COLOR = texel * sprite_tint; }"
const WithdrawalMission = preload("res://native/withdrawal_mission.gd")
const AdvanceMission = preload("res://native/advance_mission.gd")
const GroundCombat = preload("res://native/ground_combat.gd")
const BattleDuration = preload("res://native/battle_duration.gd")
const StandingPortrait = preload("res://native/barracks_portrait.gd")
const UnitSkills = preload("res://native/unit_skills.gd")
const BattleSupport = preload("res://native/battle_support.gd")
const BattlefieldPresentation = preload("res://native/battlefield_presentation.gd")
const RubyText = preload("res://native/ruby_label.gd")
const GameFonts = preload("res://native/game_fonts.gd")
const PaintedBattlefield = preload("res://native/painted_battlefield.gd")
const PaintedActors = preload("res://native/painted_actor_renderer.gd")
const EnemyModeProfiles = preload("res://native/enemy_mode_profiles.gd")
const CampaignScenarios = preload("res://native/campaign_scenarios.gd")
var painted_field = PaintedBattlefield.new()
var painted_actors = PaintedActors.new()
var presentation_mirrored: bool = false
const UnitGrowth = preload("res://native/unit_growth.gd")
const MAX_SIMULATION_STEP: float = .05
const MAX_REALTIME_STEPS: int = 3
const REALTIME_SIMULATION_BUDGET_USEC: int = 8000
const PASSIVE_GOLD_INTERVAL: float = .5
# Gold per half combat second for campaign stages 01 through 40.
# Sequential unlocks raise the budget for actual recruitment costs; later
# stages add replacement income without inventing more expensive units.
const PASSIVE_GOLD_BY_STAGE: Array[int] = [
	2,  # 01: archer (60), spear (25); 4 gold per combat second.
	10, # 02: samurai (85).
	10, # 03.
	12, # 04: gunner (115).
	12, # 05.
	12, # 06.
	12, # 07.
	13, # 08.
	14, # 09: monk (95).
	14, # 10.
	16, # 11: mounted commander (145).
	16, # 12.
	16, # 13.
	16, # 14.
	18, # 15: ninja (110).
	18, # 16.
	18, # 17.
	18, # 18.
	19, # 19.
	20, # 20.
	20, # 21.
	20, # 22.
	21, # 23.
	21, # 24.
	21, # 25.
	21, # 26.
	21, # 27.
	21, # 28.
	22, # 29.
	22, # 30.
	22, # 31.
	22, # 32.
	22, # 33.
	22, # 34.
	23, # 35.
	24, # 36.
	24, # 37.
	24, # 38.
	24, # 39.
	24, # 40.
]
const ENGAGED_MARCH_FACTOR: float = 1.35
const BASE_BATTLE_SPEED: float = 1.25
const ENEMY_FORMATION_LANE_GAP: float = .014
const ENEMY_FORMATION_ROW_GAP: float = .032
# Input tolerance matches the existing field actor pickup radius. Recruitment
# origins have positions, not authored build zones; this does not add terrain.
const MARCH_DEPLOYMENT_PICK_RADIUS: float = .055
const ENEMY_PATH_ROLE: String = "path_assault"
const ENEMY_EMPLACEMENT_ROLE: String = "emplacement_assault"
const EMPLACEMENT_ENEMY_KINDS: Array = ["enemy_archer","enemy_gunner","enemy_samurai"]
const HUNTER_ACQUIRE_RADIUS: float = .23
const HUNTER_RELEASE_RADIUS: float = .31
const HUNTER_LOST_GRACE: float = .75
const FIRST_STAGE_ENEMY_HP_FACTOR: float = 1.10

# Shared presentation only: actor bars and the friendly objective bar.
const HEALTHBAR_HEIGHT: float = 2.0
const HEALTHBAR_ANCHOR_HEIGHT: float = 8.0
const HEALTHBAR_FRIENDLY_COLOR: String = "43c96b"
const HEALTHBAR_HOSTILE_COLOR: String = "ef565b"
const HEALTHBAR_BACKGROUND_COLOR: String = "15232b"

var config: Dictionary = {}
var field_rect: Rect2 = Rect2(300, 100, 960, 600)
var input_enabled: bool = true
var ui_deployment_active: bool = false
var running: bool = false
var paused: bool = false
var between_waves: bool = false
var finished: bool = false
var battle_closed: bool = false
var victory: bool = false
var speed: float = 1.0
var gold: int = 0
var passive_gold_clock: float = 0.0
var passive_gold_per_tick: int = 2
var wave: int = 0
var total_waves: int = 10
var kills: int = 0
var units: Array = []
var enemies: Array = []
var projectiles: Array = []
var effects: Array = []
var death_actors: Array = []
var animated_textures: Dictionary = {}
var animation_manifest: Dictionary = {}
var animation_time: float = 0.0
var objectives: Array = []
var paths: Array = []
var zones: Array = []
var placement_hints: Array = []
var pending: Dictionary = {}
var selected_id: int = -1
var explicit_selection_id: int = -1
var next_id: int = 1
var recruits: int = 0
var spawn_queue: Array = []
var spawn_source_waves: Array = []
var spawn_metadata: Array = []
var spawn_plan_cursor: int = 0
var enemy_approach_states: Dictionary = {}
var enemy_approach_step: Dictionary = {}
var enemy_lane_routes: Dictionary = {}
var attack_pattern: String = "skirmish"
var campaign_story_index: Dictionary = {}
var campaign_story_loaded: bool = false
var friendly_casualties_pending: bool = false
var wave_spawn_schedule: Array = []
var spawn_clock: float = 0.0
var elapsed: float = 0.0
var wave_time: float = 0.0
var state_clock: float = 0.0
var realtime_simulation_pending: float = 0.0
var performance_profiling_enabled: bool = false
var performance_profile: Dictionary = {}

var bridge_index: int = 0
var bridge_cooldown: float = 0.0
var storm_active: bool = false
var storm_clock: float = 0.0
var escort_distance: float = 0.0
var background: Texture2D
var sprite_atlas: Texture2D
var ui_font: Font
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var visual_profiles: Dictionary = {}
var render_sprites: Array = []
var render_sprite_cursor: int = 0
var actor_material: ShaderMaterial
var actor_overlay: Node2D
var three_d_enabled: bool = false
var three_d_actor_scale: float = 1.0
var external_combat_feedback: bool = false
var external_placement_ghost: bool = false
var roster_configured: bool = false
var recruit_catalog: Dictionary = {}
var unlocked_roster: Dictionary = {}
var campaign_levels: Dictionary = {}
var learning_supports: Array[Dictionary] = []
var learning_attempts: Dictionary = {}
var quiz_gold_receipts: Dictionary = {}
var emplacement_body_bounds: Dictionary = {}
var ground_combat = GroundCombat.new()
var structure_placement_clear: Callable
var unit_skills = UnitSkills.new()
var battle_support = BattleSupport.new()
var withdrawal_mission = WithdrawalMission.new()
var advance_mission = AdvanceMission.new()
var last_emplacement_targets: Array = []
var movement_ranges: Dictionary = {}
var next_event_id: int = 1
var battle_minutes: int = 0
var battle_plan: Dictionary = {}
var battle_refill_clock: float = 0.0
var battle_refill_count: int = 0
var battle_refill_cursor: int = 0
var completed_wave: int = 0
var placement_cursor: Vector2 = Vector2(-1,-1)
var placement_cursor_visible: bool = false
var placement_art: Dictionary = {}
var recruitment_queue: Array = []
var render_projection_provider: Control
var circle_floor_faces: Array = []
var field_input_clip: Control
var ambush_warnings: Array=[]
var next_ambush_id: int=1
var next_recruitment_id: int = 1
var battle_generation: int = 0
var friendly_impact_receipts: Dictionary = {}
var floating_label_style: StyleBox

func set_performance_profiling_enabled(value: bool) -> void:
	performance_profiling_enabled=value
	performance_profile.clear()
	ground_combat.crowd.set_profiling_enabled(value)

func performance_snapshot(reset_counts: bool = false) -> Dictionary:
	var result: Dictionary=performance_profile.duplicate(true)
	result["crowd"]=ground_combat.crowd.performance_snapshot(reset_counts)
	if reset_counts: performance_profile.clear()
	return result

func _profile_elapsed(key: String, started_usec: int, count: int = 1) -> void:
	if not performance_profiling_enabled: return
	var record: Dictionary=performance_profile.get(key,{"calls":0,"usec":0,"items":0})
	record.calls=int(record.calls)+1
	record.usec=int(record.usec)+Time.get_ticks_usec()-started_usec
	record.items=int(record.items)+count
	performance_profile[key]=record

func configure_roster(catalog: Array, unlocked: Array, levels: Dictionary) -> void:
	unit_skills.invalidate_roster_index()
	roster_configured = true
	recruit_catalog.clear()
	unlocked_roster.clear()
	campaign_levels = levels.duplicate(true)
	for definition in catalog:
		if definition is Dictionary and not str(definition.get("id","")).is_empty():
			recruit_catalog[str(definition.id)] = definition.duplicate(true)
	for id in unlocked:
		if recruit_catalog.has(str(id)) and bool(recruit_catalog[str(id)].get("active",true)):
			unlocked_roster[str(id)] = true
	if not config.is_empty():
		_emit_state()

func emplacement_protection_active() -> bool:
	# Local marching reinforcements protect emplacements from the first stage.
	# Difficulty is authored by assault groups, never by a roster-based immunity.
	return false

func can_enemy_target_unit(unit: Dictionary) -> bool:
	if unit.is_empty() or float(unit.get("hp",0))<=0 or bool(unit.get("consumed",false)): return false
	return not emplacement_protection_active() or str(unit.get("type","")) not in ["archer","gunner","monk","naginata"]

func can_friendly_target_enemy(source: Dictionary, enemy: Dictionary) -> bool:
	if enemy.is_empty() or float(enemy.get("hp",0))<=0 or bool(enemy.get("escaped",false)): return false
	var fixed: bool=str(source.get("type","")) in ["archer","gunner"]
	var raider: bool=str(enemy.get("combatRole",""))==ENEMY_EMPLACEMENT_ROLE and not bool(enemy.get("fortification",false)) and not bool(enemy.get("stationaryEnemy",false))
	var ranged_raider: bool=raider and str(enemy.get("kind","")) in ["enemy_archer","enemy_gunner"]
	return not (fixed and ranged_raider and not bool(enemy.get("roadRanged",false)))

func shooting_position_snapshot() -> Array:
	var records: Array=[]
	for zone in zones:
		if str(zone.get("placementRole",""))!="ranged" or not deployment_zone_active(zone): continue
		var slots: Array=[]
		var occupied: int=0
		var reserved: int=0
		for slot in _shooting_slots(zone):
			if int(slot.occupiedBy)>=0: occupied+=1
			if int(slot.reservedByJob)>=0: reserved+=1
			slots.append({"index":int(slot.index),"x":slot.position.x,"y":slot.position.y,"occupiedBy":int(slot.occupiedBy),"reservedByJob":int(slot.reservedByJob),"available":bool(slot.available)})
		records.append({"id":str(zone.id),"nameKo":str(zone.get("nameKo","사격 진지")),"x":zone.position.x,"y":zone.position.y,"r":float(zone.get("r",.024)),"placementRole":"ranged","acceptedUnitTypes":zone.get("acceptedUnitTypes",["archer"]),"elevation":int(zone.get("elevation",0)),"rangeBonusPercent":((1.0+float(zone.get("elevation",0))*.12)*(1.0+maxf(0.0,float(zone.get("postRangeBonusPercent",0.0)))/100.0)-1.0)*100.0,"postRangeBonusPercent":float(zone.get("postRangeBonusPercent",0.0)),"slotCapacity":int(zone.get("slotCapacity",0)),"occupied":occupied,"reserved":reserved,"available":maxi(0,int(zone.get("slotCapacity",0))-occupied-reserved),"slots":slots})
	return records

func enemy_role_contract(kind: String, actor: Dictionary = {}) -> Dictionary:
	var emplacement: bool=kind in EMPLACEMENT_ENEMY_KINDS
	var result: Dictionary={"combatRole":ENEMY_EMPLACEMENT_ROLE if emplacement else ENEMY_PATH_ROLE,"roleKo":"진지 공격" if emplacement else "경로 공격","roleMarker":"target" if emplacement else "route_arrow","roleColor":"f0ac57" if emplacement else "e45d54"}
	for key in ["combatRole","roleKo","roleMarker","roleColor"]:
		if actor.has(key): result[key]=actor[key]
	return result

func _friendly_emplacement_troop(unit: Dictionary) -> bool:
	return str(unit.get("type","")) in ["archer","gunner"] and (bool(unit.get("emplacementShooter",false)) or str(unit.get("deploymentPlacementRole",unit.get("placementRole","")))=="ranged")

func can_enemy_engage_unit(enemy: Dictionary, unit: Dictionary, contact: bool = false) -> bool:
	if not can_enemy_target_unit(unit): return false
	if bool(enemy.get("roadRanged",false)):
		if int(enemy.get("pathIndex",-1))!=int(unit.get("postPathIndex",-2)): return false
		if _friendly_emplacement_troop(unit): return true
		if not contact or not GroundCombat.is_marching(str(unit.get("type",""))) or not ground_combat.shares_contact_front(unit,enemy): return false
		var contact_radius: float=maxf(ground_combat._frontline_contact_reach(unit),float(enemy.get("meleeRange",.032)))
		return enemy.position.distance_squared_to(unit.position)<=contact_radius*contact_radius
	var role: String=str(enemy.combatRole) if enemy.has("combatRole") else str(enemy_role_contract(str(enemy.get("kind","raider"))).combatRole)
	if role==ENEMY_EMPLACEMENT_ROLE:
		return true
	if not ground_combat.shares_contact_front(unit,enemy): return false
	if GroundCombat.is_marching(str(unit.get("type",""))): return true
	# Guards and ambushers can intercept on their actual lane. A route attacker
	# only retaliates where they touch; it never follows them to their home.
	return contact and str(unit.get("type","")) in ["naginata","ninja"] and unit.position.distance_to(enemy.position)<=ground_combat.reach(unit)*1.05 and ground_combat.can_fight(unit)

func recruit_cost(unit_type: String) -> int:
	var definition: Dictionary=recruit_catalog.get(unit_type,{})
	if definition.is_empty():
		for entry in UNIT_TYPES:
			if str(entry.id)==unit_type: definition=entry;break
	if definition.is_empty(): return 0
	return UnitGrowth.recruit_cost(definition,clampi(int(campaign_levels.get(unit_type,1)),1,10)) if roster_configured else int(config.get("recruitCost",60))

func _unit_definition(unit: Dictionary) -> Dictionary:
	if unit.has("definition"):
		return unit.definition
	if recruit_catalog.has(str(unit.get("type",""))):
		return recruit_catalog[str(unit.type)]
	for definition in UNIT_TYPES:
		if str(definition.id) == str(unit.get("type","")):
			return definition
	return UNIT_TYPES[0]

func _evolution_for(definition: Dictionary, permanent_level: int) -> Dictionary:
	return UnitGrowth.evolution(definition,permanent_level)

func _ready() -> void:
	rng.randomize()
	ui_font = GameFonts.body()
	if not three_d_enabled and not painted_actors.is_ready() and ResourceLoader.exists("res://assets/units-atlas.png"):
		sprite_atlas = load("res://assets/units-atlas.png")
	_load_animation_assets()
	_load_visual_profiles()
	var shader: Shader = Shader.new()
	shader.code = ACTOR_COLOR_SHADER
	actor_material = ShaderMaterial.new()
	actor_material.shader = shader
	actor_overlay = Node2D.new()
	actor_overlay.z_index = 2048
	actor_overlay.draw.connect(_draw_actor_overlay)
	add_child(actor_overlay)

func _load_visual_profiles() -> void:
	var profile_path: String = "res://native/visual_profiles.json"
	if not FileAccess.file_exists(profile_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	if data is Dictionary:
		for profile in data.get("profiles", []):
			visual_profiles[str(profile.get("stageId", ""))] = profile

func visual_profile() -> Dictionary:
	if visual_profiles.has(str(config.get("id", ""))):
		return visual_profiles[str(config.id)]
	var defaults: Dictionary = {"ambientTint":"#dedbcb","actorBrightness":0.92,"actorSaturation":0.70,"shadowTint":"#151811","shadowOpacity":0.24,"shadowDirection":{"x":0.65,"y":0.35},"shadowLength":0.34,"perspective":{"farScale":0.74,"nearScale":1.08,"verticalCompression":0.88},"roadOpacity":0.16,"fogTint":"#b7c2ba","fogStrength":0.05}
	match str(config.get("theme", "")):
		"forest": defaults.ambientTint = "#cdd1b9"
		"farm", "town", "siege": defaults.ambientTint = "#e0d2b4"
		"river", "harbor": defaults.ambientTint = "#bdccd0"
		"temple": defaults.ambientTint = "#d0c6b8"
		"snow":
			defaults.ambientTint = "#c6d9e1"
			defaults.shadowTint = "#253748"
			defaults.shadowOpacity = 0.17
			defaults.actorSaturation = 0.58
		"night":
			defaults.ambientTint = "#9ba6b5"
			defaults.actorBrightness = 0.78
			defaults.actorSaturation = 0.58
	return defaults

func _load_animation_assets() -> void:
	var manifest_path: String = "res://assets/units-animated/manifest.json"
	if FileAccess.file_exists(manifest_path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if data is Dictionary:
			animation_manifest = data
	# Combat timing remains identical. The active 3D pipeline has new geometry
	# and does not need to allocate the retired sprite sheets.
	if three_d_enabled or painted_actors.is_ready(): return
	for key in ANIMATED_UNIT_KEYS:
		var sprite_paths: Dictionary = animation_manifest.get("sprites", {})
		var path: String = str(sprite_paths.get(key, "res://assets/units-animated/%s.png" % key))
		if ResourceLoader.exists(path):
			var texture: Texture2D = load(path)
			if texture != null and texture.get_width() >= 6 and texture.get_height() >= 4:
				animated_textures[key] = texture

func _animation_definition(state: String) -> Dictionary:
	var definitions: Dictionary = animation_manifest.get("animations", {})
	return definitions.get(state, {"row":ANIMATION_ROWS.get(state, 0),"frames":6,"fps":ANIMATION_FPS.get(state, 5.0),"loop":state in ["idle","walk"]})

func _animation_duration(state: String) -> float:
	var definition: Dictionary = _animation_definition(state)
	return float(definition.get("frames", 6)) / maxf(1.0, float(definition.get("fps", 9.0)))

func _impact_time(unit_type: String) -> float:
	var impact_frames: Dictionary = animation_manifest.get("impactFrames", {})
	var index: int = int(impact_frames.get(unit_type, 4 if unit_type in ["archer","samurai"] else 3))
	return float(index) / maxf(1.0, float(_animation_definition("attack").get("fps", 12.0)))

func set_field_rect(value: Rect2) -> void:
	field_rect = value
	unit_skills.invalidate_layout_queries()
	queue_redraw()

func bind_render_projection(provider: Control) -> void:
	render_projection_provider=provider
	unit_skills.invalidate_layout_queries()

func set_input_clip(clip: Control) -> void:
	field_input_clip=clip

func screen_to_local_point(screen_point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse()*screen_point

func screen_to_field_point(screen_point: Vector2) -> Vector2:
	if _uses_world_projection():
		var picked: Dictionary=render_projection_provider.screen_to_model_point(screen_point)
		return picked.get("position",Vector2(NAN,NAN)) if bool(picked.get("valid",false)) else Vector2(NAN,NAN)
	return model_point((screen_to_local_point(screen_point)-field_rect.position)/field_rect.size)

func _uses_world_projection() -> bool:
	return is_instance_valid(render_projection_provider) and render_projection_provider.has_method("uses_world_geometry") and bool(render_projection_provider.uses_world_geometry())

func view_point(canonical_point: Vector2) -> Vector2:
	return BattlefieldPresentation.to_view(canonical_point,presentation_mirrored)

func model_point(display_point: Vector2) -> Vector2:
	return BattlefieldPresentation.to_model(display_point,presentation_mirrored)

func screen_point_in_field(screen_point: Vector2) -> bool:
	if is_instance_valid(field_input_clip):
		var clipped: Vector2=field_input_clip.get_global_transform_with_canvas().affine_inverse()*screen_point
		if not Rect2(Vector2.ZERO,field_input_clip.size).has_point(clipped): return false
	if not field_rect.has_point(screen_to_local_point(screen_point)): return false
	var ancestor: Node=get_parent()
	while ancestor!=null:
		if ancestor is Control and ancestor.clip_contents:
			var local: Vector2=ancestor.get_global_transform_with_canvas().affine_inverse()*screen_point
			if not Rect2(Vector2.ZERO,ancestor.size).has_point(local): return false
		ancestor=ancestor.get_parent()
	return true

func field_point_to_screen(point: Vector2) -> Vector2:
	if _uses_world_projection():
		return render_projection_provider.get_global_transform_with_canvas()*render_projection_provider.model_to_field_point(point)
	return get_global_transform_with_canvas()*_screen(point)

func set_input_enabled(value: bool) -> void:
	input_enabled = value

func set_seed(value: int) -> void:
	rng.seed = value

static func battle_mode_preview(map_config: Dictionary, minutes: int) -> Dictionary:
	return BattleDuration.preview(map_config,minutes)

func _is_timed_battle() -> bool:
	# Compatibility for old diagnostic callers. Gameplay has no time limit.
	return false

func _is_cycle_battle() -> bool:
	return str(battle_plan.get("mode",""))=="cycles"

func _cycle_wave() -> Dictionary:
	if wave<=0 or wave>battle_plan.get("waves",[]).size(): return {}
	return battle_plan.waves[wave-1]

func _timed_wave() -> Dictionary:
	# Old observers may still read the current plan through this name.
	return _cycle_wave()

func _combat_wave_level() -> int:
	return int(_cycle_wave().get("sourceWave",wave))

func _living_enemy_count() -> int:
	var count: int=0
	for enemy in enemies:
		if float(enemy.get("hp",0.0))>0.0 and not bool(enemy.get("escaped",false)): count+=1
	return count

func _cycle_attackers_cleared() -> bool:
	return spawn_queue.is_empty() and ambush_warnings.is_empty() and _living_enemy_count()==0

func _attack_cycles_cleared() -> bool:
	return total_waves>0 and completed_wave>=total_waves and _cycle_attackers_cleared()

func _try_finish_cycles() -> bool:
	if finished or battle_closed: return finished
	if bool(config.get("trainingOnly",false)) or not bool(EnemyModeProfiles.profile_for(config).get("combatEnabled",true)): return false
	if not _attack_cycles_cleared(): return false
	for objective in objectives:
		if float(objective.get("hp",0))<=0: _finish(false);return true
	if advance_mission.enabled and (not advance_mission.complete or advance_mission.failed): return false
	_finish(true)
	return true

func load_map(map_config: Dictionary, duration_minutes: int = BattleDuration.FIXED_MINUTES) -> void:
	# Never carry another battlefield's physical geometry into this map.
	structure_placement_clear = Callable()
	ground_combat.structure_segment_clear = Callable()
	ground_combat.structure_placement_clear = Callable()
	battle_generation+=1
	realtime_simulation_pending=0.0
	friendly_impact_receipts.clear()
	painted_actors.bind_battle(self)
	_cancel_all_recruitment("map_change",false)
	config = CampaignScenarios.apply(map_config,map_config.get("story",{}))
	_cache_circle_floor()
	presentation_mirrored = BattlefieldPresentation.mirror_for_stage(config)
	battle_minutes = BattleDuration.normalize_minutes(duration_minutes)
	battle_plan.clear()
	battle_refill_clock = 0.0
	battle_refill_count = 0
	battle_refill_cursor = 0
	last_emplacement_targets.clear()
	completed_wave = 0
	running = false
	paused = false
	between_waves = false
	finished = false
	battle_closed=false
	victory = false
	speed = 1.0
	gold = int(config.get("initialGold", 280))
	passive_gold_clock = 0.0
	var stage_number: int=maxi(1,int(config.get("stageNumber",1)))
	var income_index: int=clampi(stage_number-1,0,PASSIVE_GOLD_BY_STAGE.size()-1)
	passive_gold_per_tick=maxi(1,int(config.get("passiveGoldPerTick",PASSIVE_GOLD_BY_STAGE[income_index])))
	wave = 0
	total_waves = int(BattleDuration.preview(config,duration_minutes).get("totalWaves",4))
	kills = 0
	units.clear()
	enemies.clear()
	projectiles.clear()
	effects.clear()
	death_actors.clear()
	learning_supports.clear()
	learning_attempts.clear()
	quiz_gold_receipts.clear()
	emplacement_body_bounds.clear()
	battle_support.bind(self)
	battle_support.reset()
	animation_time = 0.0
	spawn_queue.clear()
	spawn_source_waves.clear()
	spawn_metadata.clear()
	spawn_plan_cursor=0
	enemy_approach_states.clear()
	enemy_approach_step.clear()
	enemy_lane_routes.clear()
	ambush_warnings.clear()
	next_ambush_id=1
	attack_pattern="skirmish"
	friendly_casualties_pending=false
	wave_spawn_schedule.clear()
	objectives.clear()
	paths.clear()
	zones.clear()
	pending.clear()
	ui_deployment_active = false
	placement_cursor_visible = false
	placement_cursor = Vector2(-1,-1)
	selected_id = -1
	explicit_selection_id = -1
	next_id = 1
	recruits = 0
	elapsed = 0.0
	wave_time = 0.0
	spawn_clock = 0.0
	bridge_index = 0
	bridge_cooldown = 0.0
	storm_clock = 0.0
	storm_active = false
	escort_distance = 0.0
	for data in config.get("objectives", []):
		var obj: Dictionary = data.duplicate(true)
		obj["position"] = _point(obj)
		if bool(obj.get("mobile", false)) and not config.get("escortRoute", []).is_empty():
			obj["position"] = _point(config.escortRoute[0])
		obj["maxHp"] = int(obj.get("hp", 25))
		objectives.append(obj)
	for data in config.get("paths", []):
		var path: Dictionary = data.duplicate(true)
		var points: Array = []
		for p in path.get("points", []):
			points.append(_point(p))
		path["points"] = points
		paths.append(path)
	ground_combat.bind(self)
	ground_combat.reset()
	unit_skills.bind(self)
	unit_skills.reset()
	_load_campaign_story()
	for data in config.get("buildZones", []):
		var build_zone: Dictionary = data.duplicate(true)
		build_zone["position"] = _point(build_zone)
		build_zone["placementRole"] = "ranged"
		zones.append(build_zone)
	for data in config.get("tactics", {}).get("groundPosts", []):
		var post: Dictionary = data.duplicate(true)
		var path_index: int = int(post.get("pathIndex", -1))
		var segment_index: int = int(post.get("segmentIndex", -1))
		if path_index<0 or path_index>=paths.size() or segment_index<0 or segment_index>=paths[path_index].points.size()-1:
			continue
		post["position"] = ground_combat.route_point(path_index, ground_combat.marker_distance(path_index,segment_index,float(post.get("t",0.5))))
		post["placementRole"] = "ground"
		post["elevation"] = 0
		zones.append(post)
	for site in ground_combat.build_ambush_sites(): zones.append(site)
	battle_plan=BattleDuration.build(config,_build_base_wave_schedule(total_waves),battle_minutes)
	total_waves=int(battle_plan.totalWaves)
	wave_spawn_schedule=_build_wave_schedule()
	advance_mission.bind(self)
	advance_mission.reset(config)
	_refresh_placement_hints()
	var background_path: String = str(config.get("background", ""))
	painted_field.configure(config)
	background=null
	if not three_d_enabled and not painted_field.is_ready() and not background_path.is_empty() and ResourceLoader.exists(background_path): background=load(background_path)
	_emit_state()
	queue_redraw()

func start_battle() -> void:
	if config.is_empty() or finished or battle_closed or running:
		return
	var generation: int=battle_generation
	paused = false
	running = true
	if wave == 0:
		_begin_wave()
	if generation!=battle_generation: return
	if not finished and not battle_closed:
		advance_mission.start()
		if advance_mission.enabled and advance_mission.failed: _finish(false)
	_emit_state()

func pause_battle() -> void:
	if not running or finished or between_waves:
		return
	paused = not paused
	_emit_state()

func set_speed(value: float) -> void:
	speed=1.0
	if is_finite(value):
		if is_equal_approx(value,1.5) or is_equal_approx(value,2.0): speed=1.5
		elif is_equal_approx(value,1.25): speed=1.25
	_emit_state()

func effective_speed() -> float:
	return BASE_BATTLE_SPEED*speed

func continue_wave() -> void:
	if finished or battle_closed:
		return
	if between_waves:
		between_waves = false
		paused = false
		_begin_wave()
	elif wave == 0:
		start_battle()
	_emit_state()

func begin_placement(unit_type: String, path_index: int = -1) -> bool:
	if finished or battle_closed or config.is_empty(): return false
	var choice: Dictionary = {}
	if roster_configured:
		if not recruit_catalog.has(unit_type) or not unlocked_roster.has(unit_type):
			_event("locked","아직 해금되지 않은 병력입니다.")
			return false
		choice = recruit_catalog[unit_type]
	else:
		for candidate in UNIT_TYPES:
			if str(candidate.id)==unit_type: choice=candidate;break
		if choice.is_empty(): return false
	if not bool(choice.get("active",true)): return false
	var cost: int = recruit_cost(unit_type)
	if GroundCombat.is_marching(unit_type):
		return _dispatch_marching(choice,cost,clampi(int(campaign_levels.get(unit_type,1)),1,10),path_index)
	if gold+int(pending.get("paid",0))<cost:
		_event("gold","배치에 필요한 금화가 부족합니다.")
		return false
	# The preview reserves neither money nor an actor id. Enemies may spawn
	# while the player chooses a site; the real id is allocated at commit.
	gold += int(pending.get("paid",0))
	var permanent_level: int = clampi(int(campaign_levels.get(unit_type,1)),1,10)
	var evolution: Dictionary = _evolution_for(choice,permanent_level)
	pending = {"id":-1,"type":unit_type,"name":evolution.name,"jp":evolution.jp,"reading":evolution.reading,"paid":0,"cost":cost,"preview":true,"campaignLevel":permanent_level,"evolution":int(evolution.stage),"definition":choice.duplicate(true)}
	_refresh_placement_hints()
	placement_cursor = Vector2(.5,.5)
	for hint in placement_hints:
		if hint.x>=0: placement_cursor=hint;break
	placement_cursor_visible = true
	_emit_state()
	return true

func _dispatch_marching(choice: Dictionary, cost: int, permanent_level: int, path_index: int) -> bool:
	if finished or config.is_empty(): return false
	if gold+int(pending.get("paid",0))<cost:
		_event("gold","출진에 필요한 금화가 부족합니다.")
		return false
	var base: Dictionary=ground_combat.select_march_base(path_index)
	if base.is_empty():
		_event("route","출진할 수 있는 육지 경로를 선택하십시오.")
		return false
	# Validate the complete action before releasing an old preview or spending.
	gold+=int(pending.get("paid",0))
	# Repeated paid card clicks keep their existing free sticky selection.
	# Clearing/restoring it would publish a second UI state and rebuild all
	# placement hints for every order in an otherwise unchanged spear burst.
	var keep_selection: bool=bool(pending.get("explicitDeploymentSelection",false)) and str(pending.get("type",""))==str(choice.id) and int(pending.get("paid",0))==0
	if not keep_selection: pending.clear()
	placement_cursor_visible=false
	var evolution: Dictionary=_evolution_for(choice,permanent_level)
	var template: Dictionary={"id":-1,"type":choice.id,"name":evolution.name,"jp":evolution.jp,"reading":evolution.reading,"cost":cost,"campaignLevel":permanent_level,"evolution":int(evolution.stage),"definition":choice.duplicate(true)}
	return _enqueue_recruitment(template,base,base.position)

func _deployment_template(unit_id: String) -> Dictionary:
	var definition: Dictionary = {}
	if roster_configured:
		if not unlocked_roster.has(unit_id) or not recruit_catalog.has(unit_id): return {}
		definition = recruit_catalog[unit_id]
	else:
		for candidate in UNIT_TYPES:
			if str(candidate.id)==unit_id: definition=candidate;break
	if definition.is_empty() or not bool(definition.get("active",true)): return {}
	var permanent_level: int = clampi(int(campaign_levels.get(unit_id,1)),1,10)
	var evolution: Dictionary = _evolution_for(definition,permanent_level)
	return {"id":-1,"type":unit_id,"name":evolution.name,"jp":evolution.jp,"reading":evolution.reading,"paid":0,"cost":recruit_cost(unit_id),"preview":true,"campaignLevel":permanent_level,"evolution":int(evolution.stage),"definition":definition.duplicate(true)}

func select_deployment(unit_id: String) -> bool:
	# Selection is free for every role, including marching. Only an explicit
	# submit_deployment call may reserve space, allocate an order or spend.
	if finished or battle_closed or config.is_empty() or int(pending.get("paid",0))>0: return false
	var template: Dictionary=_deployment_template(unit_id)
	if template.is_empty(): return false
	var changed: bool=str(pending.get("type",""))!=unit_id or not bool(pending.get("explicitDeploymentSelection",false))
	pending=template
	pending["explicitDeploymentSelection"]=true
	placement_cursor_visible=false
	if changed:
		_refresh_placement_hints()
		_emit_state()
	return true

func _deployment_rejected(result: Dictionary, message: String) -> Dictionary:
	result["ok"] = false
	result["valid"] = false
	result["message"] = message
	result["reason"] = message
	return result

func marching_support_areas(type_name: String, requested_path: int = -1) -> Array:
	var areas: Array=[]
	if bool(placement_contract(type_name).get("baseOnly",false)): return areas
	if finished or battle_closed or config.is_empty(): return areas
	for area in ground_combat.marching_support_areas(type_name,requested_path):
		areas.append({"postId":str(area.postId),"center":area.center,"radius":float(area.radius),"pathIndex":int(area.pathIndex),"x":area.center.x,"y":area.center.y})
	return areas

func deployment_preview(unit_id: String, position_norm: Vector2, path_id: String = "") -> Dictionary:
	# Explicit-unit queries never select a card, alter pending, reserve IDs,
	# publish events, or spend. The legacy click preview remains independent.
	var result: Dictionary = {"ok":false,"active":true,"valid":false,"visible":input_enabled and not finished and not battle_closed,"type":unit_id,"requestedPosition":_normalized_position(position_norm),"position":_normalized_position(position_norm),"message":"","reason":""}
	result.merge(placement_contract(unit_id))
	if finished or battle_closed or config.is_empty(): return _deployment_rejected(result,"전투가 종료되었거나 준비되지 않았습니다.")
	if not input_enabled: return _deployment_rejected(result,"현재 화면에서는 병력을 배치할 수 없습니다.")
	if not position_norm.is_finite() or position_norm.x<0.0 or position_norm.x>1.0 or position_norm.y<0.0 or position_norm.y>1.0:
		return _deployment_rejected(result,"전장 안의 유효한 위치를 선택하십시오.")
	var template: Dictionary = _deployment_template(unit_id)
	if template.is_empty(): return _deployment_rejected(result,"아직 해금되지 않았거나 존재하지 않는 병력입니다.")
	var cost: int = int(template.cost)
	result.merge({"cost":cost,"affordable":gold>=cost,"quantity":unit_skills.recruit_quantity(unit_id,int(template.campaignLevel)),"evolution":int(template.evolution),"campaignLevel":int(template.campaignLevel),"name":str(template.name),"jp":str(template.jp),"reading":str(template.reading),"range":float(_read_stats(template).range)})
	if cost<=0 or gold<cost: return _deployment_rejected(result,"배치에 필요한 금화가 부족합니다.")
	if not GroundCombat.is_marching(unit_id):
		result.merge(_stationary_placement_preview(template,position_norm,true),true)
		result["ok"] = bool(result.valid)
		result["message"] = str(result.reason)
		return result
	var path_index: int = -1
	if not path_id.is_empty():
		for index in range(paths.size()):
			if str(paths[index].get("id",index))==path_id: path_index=index;break
		if path_index<0: return _deployment_rejected(result,"출진할 수 있는 육지 경로를 선택하십시오.")
	result["supportAreas"]=marching_support_areas(unit_id,path_index)
	var base: Dictionary = ground_combat.select_march_base(path_index)
	if base.is_empty(): return _deployment_rejected(result,"출진할 수 있는 육지 경로를 선택하십시오.")
	if bool(placement_contract(unit_id).get("baseOnly",false)):
		result.merge({"position":_normalized_position(base.position),"basePosition":_normalized_position(base.position),"baseId":str(base.baseId),"baseNameKo":str(base.baseNameKo),"pathId":str(base.pathId),"pathIndex":int(base.pathIndex),"dropRadius":MARCH_DEPLOYMENT_PICK_RADIUS,"placementMode":"base_march","message":"아군 본진에서 생산 후 진격로로 출진"},true)
		result["ok"]=true
		result["valid"]=true
		return result
	var support: Dictionary=ground_combat.marching_support_destination(unit_id,position_norm,path_index)
	if not support.is_empty():
		result.merge({"position":_normalized_position(support.supportPosition),"basePosition":_normalized_position(support.position),"baseId":str(support.baseId),"baseNameKo":str(support.baseNameKo),"pathId":str(support.pathId),"pathIndex":int(support.pathIndex),"dropRadius":float(support.supportDropRadius),"supportDeployment":true,"supportPostId":str(support.supportPostId),"placementMode":"emplacement_brawl","message":"주변 적 무리와 한 차례 난전 후 진격로 복귀"},true)
		result["ok"]=true
		result["valid"]=true
		return result
	var dispatch: Dictionary=ground_combat.marching_click_destination(position_norm,path_index,unit_id)
	if dispatch.is_empty(): return _deployment_rejected(result,"진격로까지 통행 가능한 육지 위치를 선택하십시오.")
	result.merge({"position":_normalized_position(position_norm),"clickPosition":_normalized_position(position_norm),"dispatchOrigin":_normalized_position(position_norm),"dispatchJoinPosition":_normalized_position(dispatch.dispatchJoinPosition),"basePosition":_normalized_position(dispatch.position),"baseId":str(dispatch.baseId),"baseNameKo":str(dispatch.baseNameKo),"pathId":str(dispatch.pathId),"pathIndex":int(dispatch.pathIndex),"dropRadius":.05,"placementMode":"field_march"},true)
	result["ok"] = true
	result["valid"] = true
	return result

func submit_deployment(unit_id: String, position_norm: Vector2, path_id: String = "") -> Dictionary:
	# No cached preview can authorize payment. Re-read every rule at commit,
	# then use the existing single-order queue transaction without legacy setup.
	var result: Dictionary = deployment_preview(unit_id,position_norm,path_id)
	if not bool(result.ok): return result
	var template: Dictionary = _deployment_template(unit_id)
	var destination: Dictionary = ground_combat.select_march_base(int(result.pathIndex)) if GroundCombat.is_marching(unit_id) else _eligible_zone(position_norm,unit_id)
	if bool(result.get("supportDeployment",false)):
		destination=ground_combat.marching_support_destination(unit_id,position_norm,int(result.pathIndex))
	elif GroundCombat.is_marching(unit_id) and not bool(placement_contract(unit_id).get("baseOnly",false)):
		destination=ground_combat.marching_click_destination(position_norm,int(result.pathIndex),unit_id)
	if template.is_empty() or destination.is_empty(): return _deployment_rejected(result,"배치 조건이 바뀌었습니다. 다시 선택하십시오.")
	var job_id: int = next_recruitment_id
	if not _enqueue_recruitment(template,destination,_point(result.position)):
		return _deployment_rejected(result,"병사들이 설 수 있는 빈자리가 부족하거나 배치 조건이 바뀌었습니다.")
	result["jobId"] = job_id
	queue_redraw()
	return result

func placement_preview(position_norm: Vector2) -> Dictionary:
	if pending.is_empty(): return {"active":false,"valid":false,"visible":false,"reason":""}
	return _stationary_placement_preview(pending,position_norm,placement_cursor_visible and not ui_deployment_active)

func _stationary_placement_preview(template: Dictionary, position_norm: Vector2, cursor_visible: bool) -> Dictionary:
	var cost: int=int(template.get("cost",template.get("paid",0)))
	var affordable: bool=not bool(template.get("preview",false)) or gold>=cost
	var result: Dictionary={"active":true,"valid":false,"visible":cursor_visible and input_enabled and not finished,"affordable":affordable,"type":str(template.type),"evolution":int(template.get("evolution",0)),"campaignLevel":int(template.get("campaignLevel",1)),"cost":cost,"requestedPosition":_normalized_position(position_norm),"position":_normalized_position(position_norm),"range":float(_read_stats(template).range),"reason":""}
	result.merge(placement_contract(str(template.type)))
	if finished: result.reason="전투가 종료되었습니다.";return result
	if not position_norm.is_finite(): result.reason="유효한 위치를 선택하십시오.";return result
	if roster_configured and (not recruit_catalog.has(str(template.type)) or not unlocked_roster.has(str(template.type))): result.reason="아직 해금되지 않은 병력입니다.";return result
	if not affordable: result.reason="배치에 필요한 금화가 부족합니다.";return result
	var build_zone: Dictionary=_eligible_zone(position_norm,str(template.type))
	if build_zone.is_empty(): result.reason=str(result.placementHintKo);return result
	var actual: Vector2=_placement_position(position_norm,build_zone)
	var quantity: int=unit_skills.recruit_quantity(str(template.type),int(template.get("campaignLevel",1)))
	if int(build_zone.get("slotCapacity",0))<=0:
		for other in units:
			if not GroundCombat.is_marching(str(other.type)) and _reserved_position(other).distance_to(actual)<.052: result.reason="다른 병력과 조금 떨어뜨려 배치하십시오.";return result
		for job in recruitment_queue:
			if str(job.kind)!="marching" and job.position.distance_to(actual)<.0521: result.reason="생산 중인 병력의 예약 지점입니다.";return result
	var members: Array=_placed_squad_positions(template,build_zone,actual,quantity)
	if members.size()!=quantity: result.reason="이 편성의 병사들이 설 수 있는 빈자리가 부족합니다.";return result
	actual=members[0]
	var probe: Dictionary=template.duplicate()
	probe.position=actual
	probe.elevation=int(build_zone.get("elevation",0))
	# Optional authored percentage, default zero. Preview and real actors
	# receive the same value; no new post or bonus is introduced here.
	probe.postRangeBonusPercent=float(build_zone.get("postRangeBonusPercent",0.0))
	result.merge({"valid":true,"position":_normalized_position(actual),"range":float(_read_stats(probe).range),"quantity":quantity,"zoneId":str(build_zone.get("id","")),"placementRole":str(build_zone.get("placementRole","")),"slotCapacity":int(build_zone.get("slotCapacity",0)),"elevation":int(probe.elevation),"rangeBonusPercent":((1.0+float(probe.elevation)*.12)*(1.0+maxf(0.0,float(probe.postRangeBonusPercent))/100.0)-1.0)*100.0,"memberPositions":[]},true)
	result["postRangeBonusPercent"]=float(probe.postRangeBonusPercent)
	for member in members: result.memberPositions.append(_normalized_position(member))
	if str(build_zone.get("placementRole",""))=="ambush": result.merge({"ambushSiteId":str(build_zone.id),"siteNameKo":str(build_zone.nameKo),"homePosition":_normalized_position(actual),"ambushRadius":float(_read_stats(template).range)})
	return result

func _zone_accepts(build_zone: Dictionary, type_name: String) -> bool:
	if build_zone.has("acceptedUnitTypes"): return build_zone.acceptedUnitTypes.has(type_name)
	return str(build_zone.get("placementRole","ranged")) in placement_contract(type_name).get("acceptedPlacementRoles",[str(placement_contract(type_name).placementRole)])

func _shooting_slots(build_zone: Dictionary) -> Array:
	var slots: Array=[]
	var index: int=0
	for raw in build_zone.get("slotPositions",[]):
		var point: Vector2=_point(raw)
		var record: Dictionary={"index":index,"position":point,"occupiedBy":-1,"reservedByJob":-1}
		for unit in units:
			if float(unit.get("hp",0))>0 and not GroundCombat.is_marching(str(unit.type)) and str(unit.get("deploymentZoneId",""))==str(build_zone.id) and _reserved_position(unit).distance_to(point)<.008: record.occupiedBy=int(unit.id);break
		for job in recruitment_queue:
			if str(job.kind)=="marching" or str(job.destination.get("id",""))!=str(build_zone.id): continue
			for reserved in job.get("memberPositions",[]):
				if reserved.distance_to(point)<.008: record.reservedByJob=int(job.id);break
		record["available"]=int(record.occupiedBy)<0 and int(record.reservedByJob)<0
		slots.append(record)
		index+=1
	return slots

func _placed_squad_positions(template: Dictionary, destination: Dictionary, anchor: Vector2, quantity: int) -> Array:
	if int(destination.get("slotCapacity",0))>0:
		var free: Array=[]
		for slot in _shooting_slots(destination):
			if bool(slot.available) and ground_combat.land_segment_safe(slot.position,slot.position,.008): free.append(slot)
		free.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			var first: float=anchor.distance_squared_to(a.position)
			var second: float=anchor.distance_squared_to(b.position)
			return int(a.index)<int(b.index) if is_equal_approx(first,second) else first<second
		)
		if free.size()<quantity: return []
		var members: Array=[]
		for index in range(quantity): members.append(free[index].position)
		return members

	if quantity<=1: return [anchor]
	# Each member is a real soldier, with an independently reserved home.
	for direction in [Vector2.RIGHT,Vector2.DOWN,Vector2(1,1).normalized(),Vector2(1,-1).normalized()]:
		var members: Array=[]
		for index in range(quantity):
			var member: Vector2=anchor+direction*(float(index)-float(quantity-1)*.5)*.026
			var zone: Dictionary=_eligible_zone(member,str(template.type))
			if zone.is_empty() or str(zone.get("id",""))!=str(destination.get("id","")): break
			member=_placement_position(member,zone)
			var crowded: bool=false
			for other in units:
				if not GroundCombat.is_marching(str(other.type)) and _reserved_position(other).distance_to(member)<.026: crowded=true;break
			for job in recruitment_queue:
				if str(job.kind)=="marching": continue
				for reserved in job.get("memberPositions",[job.position]):
					if reserved.distance_to(member)<.026: crowded=true;break
			if crowded: break
			members.append(member)
		if members.size()==quantity: return members
	return []

func recruit(unit_id: String = "", path_index: int = -1) -> bool:
	if finished or config.is_empty():
		return false
	if unit_id.is_empty() and roster_configured and not unlocked_roster.is_empty(): unit_id=str(unlocked_roster.keys()[0])
	elif unit_id.is_empty() and not roster_configured:
		unit_id=str(UNIT_TYPES[0].id)
		if recruits<=0: return begin_placement(unit_id,path_index)
		var roll: int = rng.randi_range(1, 100)
		for candidate in UNIT_TYPES:
			roll -= int(candidate.weight)
			if roll <= 0:
				unit_id=str(candidate.id)
				break
	return begin_placement(unit_id,path_index)

func place_unit(x: float, y: float) -> bool:
	if pending.is_empty() or finished:
		return false
	var position_norm: Vector2 = Vector2(x, y)
	if position_norm.is_finite(): placement_cursor=position_norm;placement_cursor_visible=true
	var preview: Dictionary = placement_preview(position_norm)
	if not bool(preview.valid):
		_event("placement",str(preview.reason))
		queue_redraw()
		if actor_overlay!=null: actor_overlay.queue_redraw()
		return false
	var build_zone: Dictionary = _eligible_zone(position_norm, str(pending.type))
	position_norm = _point(preview.position)
	if not _enqueue_recruitment(pending,build_zone,position_norm): return false
	queue_redraw()
	return true

func _enqueue_recruitment(template: Dictionary, destination: Dictionary, position: Vector2) -> bool:
	var cost: int=maxi(0,int(template.get("cost",0)))
	if finished or battle_closed or cost<=0 or gold<cost: return false
	if not deployment_zone_active(destination): return false
	var definition: Dictionary=_unit_definition(template)
	var duration: float=float(definition.get("recruitSeconds",clampf(float(cost)*.035,2.0,5.5)))
	if not is_finite(duration) or duration<=0: duration=clampf(float(cost)*.035,2.0,5.5)
	var quantity: int=unit_skills.recruit_quantity(str(template.type),int(template.get("campaignLevel",1)))
	var kind: String=str(placement_contract(str(template.type)).deploymentKind)
	if kind=="marching" and bool(placement_contract(str(template.type)).get("baseOnly",false)):
		# Recheck the same mission policy at the payment boundary. A stale or
		# direct field-drop destination must never bypass the card's base rule.
		var base: Dictionary=ground_combat.select_march_base(int(destination.get("pathIndex",-1)))
		if base.is_empty() or bool(destination.get("supportDeployment",false)) or destination.has("dispatchOrigin"): return false
		if str(destination.get("baseId",""))!=str(base.baseId) or position.distance_squared_to(base.position)>.00000001: return false
	var spawn_started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	var member_positions: Array=_marching_spawn_positions(destination,position,quantity,str(template.type)) if kind=="marching" else _placed_squad_positions(template,destination,position,quantity)
	_profile_elapsed("spawnReservations",spawn_started,member_positions.size())
	if member_positions.size()!=quantity: return false
	var job: Dictionary={"id":next_recruitment_id,"type":str(template.type),"name":str(template.name),"kind":kind,"pathIndex":int(destination.get("pathIndex",-1)),"position":position,"cost":cost,"quantity":quantity,"remainingSeconds":duration,"totalSeconds":duration,"status":"queued","template":template.duplicate(true),"destination":destination.duplicate(true)}
	job["memberPositions"]=member_positions
	next_recruitment_id+=1
	gold-=cost
	recruitment_queue.append(job)
	var previous_hint_type: String=_placement_type()
	var keep_selection: bool=bool(pending.get("explicitDeploymentSelection",false)) and str(pending.get("type",""))==str(template.type)
	if not keep_selection: pending.clear()
	placement_cursor_visible=false
	if kind=="marching": ground_combat.commit_march_base(destination)
	recruits+=1
	# Marchers never occupy fixed placement hints or fixed shooting seats.
	if kind!="marching" or previous_hint_type!=_placement_type(): _refresh_placement_hints()
	_event("recruitment_queued","%s 생산 대기 · %.1f초" % [job.name,duration],{"side":"friendly","unitType":str(job.type),"cost":cost,"jobId":int(job.id),"quantity":quantity,"pathIndex":int(job.pathIndex),"position":_normalized_position(position)})
	_emit_state()
	return true

func _marching_spawn_positions(destination: Dictionary, anchor: Vector2, quantity: int, type_name: String = "") -> Array:
	var members: Array=[]
	var path_index: int=int(destination.get("pathIndex",0))
	var road_bound: bool=bool(GroundCombat.placement_contract(type_name,config).get("roadBoundMarch",false))
	var tangent: Vector2=(paths[path_index].points[0]-paths[path_index].points[-1]).normalized()
	var normal: Vector2=Vector2(-tangent.y,tangent.x)
	# Build one local occupancy index for this complete order. Candidate
	# probes must not rescan the whole army and queue for every empty point.
	var occupied_cells: Dictionary={}
	for other in units:
		if float(other.get("hp",0))>0 and not bool(other.get("consumed",false)):
			_reserve_spawn_point(occupied_cells,_reserved_position(other))
	for job in recruitment_queue:
		for reserved in job.get("memberPositions",[]): _reserve_spawn_point(occupied_cells,reserved)
	var support: bool=bool(destination.get("supportDeployment",false))
	var support_candidates: Array=[]
	var support_probe: Dictionary={}
	var field_dispatch: bool=destination.has("dispatchOrigin")
	if support or field_dispatch:
		if support: support_probe={"homePosition":anchor,"guardZone":destination.supportZone,"guardRadius":float(destination.supportRadius),"occupancyRadius":.008}
		# Search the existing physical drop area in every direction. A fixed
		# post's two shooter seats do not limit these independent marchers.
		for row in range(-3,4):
			for column in range(-4,5):
				var point: Vector2=anchor+normal*(float(column)+float(row)*.5)*.016+tangent*float(row)*.016*sqrt(3.0)*.5
				if point.distance_squared_to(anchor)<=.05*.05+.000000001: support_candidates.append(point)
		support_candidates.sort_custom(func(a: Vector2,b: Vector2) -> bool:
			var first: float=a.distance_squared_to(anchor)
			var second: float=b.distance_squared_to(anchor)
			if not is_equal_approx(first,second): return first<second
			return a.x<b.x if not is_equal_approx(a.x,b.x) else a.y<b.y
		)
	for index in range(quantity):
		var selected: Vector2=Vector2(INF,INF)
		var candidates: Array=support_candidates
		if not support and not field_dispatch:
			candidates=[]
			for ring in range(5):
				for lane_offset in range(3):
					var lane: int=(index+lane_offset)%3-1
					var row: int=index/3
					candidates.append(anchor+normal*float(lane)*.016+tangent*float(row+ring)*.016)
		for candidate in candidates:
			if candidate.x<0 or candidate.x>1 or candidate.y<0 or candidate.y>1: continue
			if candidate.distance_to(anchor)>.05 or not _spawn_point_free(occupied_cells,candidate): continue
			if road_bound and not ground_combat._road_point_inside(candidate,path_index): continue
			if not ground_combat.land_segment_safe(candidate,candidate,.008) or not ground_combat.land_segment_safe(anchor,candidate,.008): continue
			if destination.has("dispatchJoinPosition") and not ground_combat.land_segment_safe(candidate,destination.dispatchJoinPosition,.008): continue
			if support:
				if candidate.distance_to(destination.supportAreaCenter)>float(destination.supportDropRadius): continue
				if not ground_combat.guard_point_inside(support_probe,candidate) or not ground_combat.land_segment_safe(candidate,destination.supportReturnPosition,.008): continue
			selected=candidate
			break
		if not selected.is_finite(): return []
		members.append(selected)
		_reserve_spawn_point(occupied_cells,selected)
	return members

func _reserve_spawn_point(cells: Dictionary, point: Vector2) -> void:
	var key: Vector2i=Vector2i(floori(point.x/.014),floori(point.y/.014))
	if not cells.has(key): cells[key]=[]
	cells[key].append(point)

func _spawn_advance_followups(path_index: int, quantity: int) -> Array:
	# Mission reinforcements are ordinary, visible and attackable spear actors.
	# They use the same validated gate births and normal marching initializer,
	# without charging or duplicating a player recruitment order.
	if not advance_mission.enabled or not advance_mission.captured or finished or battle_closed: return []
	var base: Dictionary=ground_combat.select_march_base(path_index)
	if base.is_empty(): return []
	var positions: Array=_marching_spawn_positions(base,base.position,quantity,"spear")
	if positions.size()!=quantity: return []
	var definition: Dictionary=recruit_catalog.get("spear",{})
	if definition.is_empty():
		for fallback in UNIT_TYPES:
			if str(fallback.id)=="spear": definition=fallback;break
	if definition.is_empty(): return []
	var level: int=clampi(int(campaign_levels.get("spear",1)),1,10)
	var evolution: Dictionary=_evolution_for(definition,level)
	var result: Array=[]
	for point in positions:
		var unit: Dictionary={"id":next_id,"type":"spear","name":evolution.name,"jp":evolution.jp,"reading":evolution.reading,"definition":definition.duplicate(true),"campaignLevel":level,"evolution":int(evolution.stage),"paid":0,"cost":0,"position":point,"cooldown":0.0,"healClock":8.0,"elevation":0,"aim":Vector2.RIGHT,"animation":"walk","animationClock":0.0,"animationPhase":fmod(float(next_id)*.173,1.0),"deployDuration":.35,"attackPlan":{},"pulseClock":0.0,"hitClock":0.0,"productionJobId":-1,"advanceFollowup":true,"deploymentZoneId":str(base.baseId),"deploymentPlacementRole":"marching","emplacementShooter":false,"postRangeBonusPercent":0.0,"deploymentSlotIndex":-1}
		next_id+=1
		ground_combat.initialize_marching_unit(unit,base,point)
		ground_combat.initialize_march_departure(unit)
		unit_skills.initialize_unit(unit)
		units.append(unit)
		ground_combat.register_spear_birth(unit)
		result.append(unit)
		effects.append({"position":point,"time":0.0,"duration":.55,"color":Color("73e5d2"),"kind":"deploy"})
	unit_skills.invalidate_roster_index()
	return result

func _spawn_point_free(cells: Dictionary, point: Vector2) -> bool:
	var key: Vector2i=Vector2i(floori(point.x/.014),floori(point.y/.014))
	for x in range(key.x-1,key.x+2):
		for y in range(key.y-1,key.y+2):
			for occupied in cells.get(Vector2i(x,y),[]):
				if point.distance_squared_to(occupied)<.014*.014: return false
	return true

func production_preview_snapshot(lightweight_render: bool = false) -> Array:
	var result: Array=[]
	if finished or battle_closed: return result
	for job in recruitment_queue:
		var remaining: float=maxf(0.0,float(job.remainingSeconds))
		var total: float=maxf(.000001,float(job.totalSeconds))
		if lightweight_render:
			# Drawing reads immutable reserved positions. Progress remains live;
			# the full public snapshot below still returns its independent copies.
			result.append({"jobId":int(job.id),"type":str(job.type),"progress":clampf(1.0-remaining/total,0,1),"memberPositions":job.memberPositions,"friendly":true,"level":int(job.template.get("campaignLevel",1))})
			continue
		var members: Array=[]
		for index in range(job.memberPositions.size()):
			var point: Vector2=job.memberPositions[index]
			members.append({"memberIndex":index,"previewActorId":-100000-int(job.id)*8-index,"x":point.x,"y":point.y,"position":_normalized_position(point),"type":str(job.type),"campaignLevel":int(job.template.get("campaignLevel",1)),"evolution":int(job.template.get("evolution",0)),"aimX":-1.0,"aimY":0.0})
		result.append({"jobId":int(job.id),"type":str(job.type),"nameKo":str(job.name),"status":str(job.status),"cancelled":false,"remainingSeconds":remaining,"totalSeconds":total,"progress":clampf(1.0-remaining/total,0,1),"quantity":int(job.quantity),"members":members,"memberPositions":job.memberPositions.duplicate(),"positions":job.memberPositions.duplicate(),"friendly":true,"level":int(job.template.get("campaignLevel",1)),"progress01":clampf(1.0-remaining/total,0,1),"pathIndex":int(job.pathIndex),"deploymentKind":str(job.kind),"zoneId":str(job.destination.get("id","")),"paused":paused or between_waves or not running,"speed":speed})
	return result

func cancel_recruitment(job_id: int) -> bool:
	for index in range(recruitment_queue.size()):
		var job: Dictionary=recruitment_queue[index]
		if int(job.id)!=job_id: continue
		recruitment_queue.remove_at(index)
		gold+=int(job.cost)
		if str(job.kind)!="marching": _refresh_placement_hints()
		_event("recruitment_cancelled","%s 주문 취소 · 금화 +%d" % [job.name,int(job.cost)],{"jobId":job_id,"unitType":str(job.type),"refund":int(job.cost)})
		_emit_state()
		return true
	return false

func _cancel_all_recruitment(reason: String, publish: bool = true) -> int:
	var refund: int=0
	for job in recruitment_queue: refund+=int(job.cost)
	recruitment_queue.clear()
	gold+=refund
	if publish and refund>0: _event("recruitment_cancelled","미완료 생산 주문을 취소했습니다.",{"refund":refund,"reason":reason})
	return refund

func close_battle() -> void:
	if battle_closed: return
	var generation: int=battle_generation
	battle_closed=true
	unit_skills.cancel_ninja_charges()
	ui_deployment_active=false
	battle_support.cease()
	running=false
	paused=false
	cancel_recruit()
	_cancel_all_recruitment("battle_closed")
	if generation!=battle_generation: return
	for unit in units:
		if str(unit.type)=="ninja" and float(unit.get("hp",0))>0: ground_combat.mark_ninja_consumed(unit,"battle_closed")
	_remove_consumed_units()
	if generation!=battle_generation: return
	_refresh_placement_hints()
	_emit_state()

func _exit_tree() -> void:
	_cancel_all_recruitment("quit",false)

func _advance_recruitment(delta: float) -> void:
	var generation: int=battle_generation
	var ready: Array=[]
	var produced: bool=false
	for job in recruitment_queue:
		var previous_remaining: float=float(job.remainingSeconds)
		job.remainingSeconds=maxf(0.0,previous_remaining-delta)
		job.status="producing" if float(job.remainingSeconds)>.0000001 else "ready"
		if float(job.remainingSeconds)<=.0000001: ready.append({"job":job,"completionOffset":previous_remaining})
	ready.sort_custom(func(a: Dictionary,b: Dictionary):
		return int(a.job.id)<int(b.job.id) if is_equal_approx(float(a.completionOffset),float(b.completionOffset)) else float(a.completionOffset)<float(b.completionOffset)
	)
	# Read-only presentation can observe one completed production batch. Raw
	# observers retain per-job removal/events so cancellation and reentry keep
	# their original contract. No production deadline is deferred to a new frame.
	var batch: bool=ready.size()>1 and game_event.get_connections().is_empty()
	var completed_jobs: Dictionary={}
	var notices: Array=[]
	for completed in ready:
		var job: Dictionary=completed.job
		if not batch:
			var queue_index: int=recruitment_queue.find(job)
			if queue_index<0: continue
			recruitment_queue.remove_at(queue_index)
		else:
			completed_jobs[int(job.id)]=true
		var created: Array=[]
		var first: Dictionary={}
		for index in range(int(job.quantity)):
			var unit: Dictionary=job.template.duplicate(true)
			unit.erase("preview")
			unit.merge({"id":next_id,"paid":int(job.cost)/int(job.quantity)+(int(job.cost)%int(job.quantity) if index==0 else 0),"position":job.position,"cooldown":0.0,"healClock":8.0,"elevation":int(job.destination.get("elevation",0)),"aim":Vector2.RIGHT,"animation":"idle","animationClock":0.0,"animationPhase":fmod(float(next_id)*.173,1.0),"deployDuration":.35,"attackPlan":{},"pulseClock":0.0,"hitClock":0.0,"productionJobId":int(job.id)},true)
			unit["deploymentZoneId"]=str(job.destination.get("id",""))
			unit["postRangeBonusPercent"]=float(job.destination.get("postRangeBonusPercent",0.0))
			unit.position=job.memberPositions[index]
			unit["emplacementShooter"]=str(job.destination.get("placementRole",""))=="ranged"
			unit["deploymentPlacementRole"]=str(job.destination.get("placementRole",""))
			unit["deploymentSlotIndex"]=-1
			for slot_index in range(job.destination.get("slotPositions",[]).size()):
				if _point(job.destination.slotPositions[slot_index]).distance_to(unit.position)<.008: unit.deploymentSlotIndex=slot_index
			next_id+=1
			if str(job.kind)=="marching":
				ground_combat.initialize_marching_unit(unit,job.destination,job.memberPositions[index])
				if bool(job.destination.get("supportDeployment",false)):
					var member_destination: Dictionary=job.destination.duplicate(true)
					member_destination.supportPosition=job.memberPositions[index]
					ground_combat.initialize_marching_support(unit,member_destination)
				else:
					ground_combat.initialize_march_departure(unit)
					if job.destination.has("dispatchOrigin"):
						unit["clickPosition"]=job.destination.clickPosition
						unit["dispatchOrigin"]=job.destination.dispatchOrigin
						unit["dispatchJoinPosition"]=job.destination.dispatchJoinPosition
						unit["dispatchJoinPending"]=unit.position.distance_to(unit.dispatchJoinPosition)>.0001
					if str(unit.type)!="spear":
						unit.merge({"combatState":"march","gatherRemaining":0.0,"gatherGroupId":0},true)
						unit.animation="walk"
			else:
				ground_combat.initialize_unit(unit,job.destination)
				unit.deploying=not GroundCombat.is_frontline(str(unit.type))
				if bool(unit.deploying): unit.animation="walk"
			unit_skills.initialize_unit(unit)
			units.append(unit)
			ground_combat.register_spear_birth(unit)
			if first.is_empty(): first=unit
			created.append(int(unit.id))
			selected_id=int(unit.id)
			effects.append({"position":unit.position,"time":0.0,"duration":.55,"color":Color("73e5d2"),"kind":"deploy"})
		produced=produced or str(job.kind)!="marching"
		var notice: Dictionary={"type":"recruited" if str(job.kind)=="marching" else "placed","actor":first,"payload":{"cost":int(job.cost),"quantity":int(job.quantity),"jobId":int(job.id),"actorIds":created,"deploymentKind":str(job.kind),"pathIndex":int(job.pathIndex),"message":"%s 생산 완료" % job.name}}
		if batch:
			notices.append(notice)
		else:
			_combat_event(str(notice.type),notice.actor,{},notice.payload)
			if generation!=battle_generation or finished or battle_closed: return
	if batch:
		var waiting: Array=[]
		for job in recruitment_queue:
			if not completed_jobs.has(int(job.id)): waiting.append(job)
		# Keep the public queue object and the surviving orders in their old order.
		recruitment_queue.clear()
		recruitment_queue.append_array(waiting)
		for notice in notices:
			_combat_event(str(notice.type),notice.actor,{},notice.payload)
			if generation!=battle_generation or finished or battle_closed: return
	if produced: _refresh_placement_hints()

func cancel_recruit() -> void:
	if not pending.is_empty():
		gold += int(pending.get("paid", 0))
		pending.clear()
		placement_cursor_visible = false
		_refresh_placement_hints()
		_emit_state()

func select_unit(id: int) -> void:
	selected_id = id
	_emit_state()

func order_assassination(enemy_id: int, unit_id: int = -1) -> Dictionary:
	var result: Dictionary={"accepted":false,"reasonKo":""}
	if not input_enabled or paused or between_waves or finished:
		result.reasonKo="전투가 재개된 뒤 암살 대상을 지정하십시오.";return result
	var unit: Dictionary=_selected() if unit_id<0 else ground_combat._unit(unit_id)
	if unit.is_empty() or not GroundCombat.is_ambush(str(unit.type)) or float(unit.get("hp",0))<=0 or bool(unit.get("consumed",false)):
		result.reasonKo="배치된 닌자를 먼저 선택하십시오.";return result
	if str(unit.get("animation","idle"))=="attack":
		result.reasonKo="닌자가 현재 공격을 마친 뒤 대상을 지정하십시오.";return result
	var target: Dictionary=_enemy(enemy_id)
	if target.is_empty() or float(target.get("hp",0))<=0:
		result.reasonKo="살아 있는 지상 강적 또는 적 진지를 지정하십시오.";return result
	var radius: float=float(_read_stats(unit).range)*2.0
	if int(target.pathIndex)!=int(unit.postPathIndex) or unit.homePosition.distance_to(target.position)>radius:
		result.reasonKo="출발 지점과 같은 길의 가까운 지상 적이나 진지를 지정하십시오.";return result
	if not ground_combat.ninja_mission_target_valid(unit,target) or not ground_combat.ninja_route_valid(unit,target):
		result.reasonKo="해당 표적까지 합법적인 지상 접근 경로가 없습니다.";return result
	if int(unit.get("priorityTargetId",-1))==enemy_id:
		result.reasonKo="이미 그 적을 암살 대상으로 지정했습니다.";result["duplicate"]=true;return result
	if int(unit.get("priorityTargetId",-1))>=0:
		result.reasonKo="소모성 닌자는 한 번 지정한 암살 임무를 다른 대상으로 바꿀 수 없습니다.";return result
	unit["priorityTargetId"]=enemy_id
	unit["targetId"]=enemy_id
	unit["ambushStrikeDone"]=false
	unit["combatState"]="ambush_approach"
	result.merge({"accepted":true,"unitId":int(unit.id),"targetId":enemy_id,"assassinationRadius":radius,"reasonKo":"지정한 강적 또는 진지를 암살합니다. 임무가 끝나거나 표적을 잃으면 퇴장하며 재사용할 수 없습니다."},true)
	_combat_event("assassination_ordered",unit,target,{"message":str(result.reasonKo)})
	_emit_state()
	queue_redraw()
	return result

func grant_reward(kind: String) -> void:
	var amount: int = 70 if kind == "correct" else 25 if kind == "hinted" else 40
	gold += amount
	_event("reward", "보급 도착 · 금화 +%d" % amount)
	_emit_state()

func apply_learning_support(position_norm: Vector2, hinted: bool, attempt_id: String) -> Dictionary:
	if config.is_empty() or finished or not running or wave<1:
		return {"ok":false,"reason":"battle_inactive"}
	if attempt_id.strip_edges().is_empty():
		return {"ok":false,"reason":"missing_attempt_id"}
	if learning_attempts.has(attempt_id):
		return {"ok":false,"reason":"duplicate_attempt"}
	if not position_norm.is_finite() or position_norm.x<0.0 or position_norm.x>1.0 or position_norm.y<0.0 or position_norm.y>1.0:
		return {"ok":false,"reason":"invalid_position"}
	var duration: float = 6.0 if hinted else 12.0
	var factor: float = 1.08 if hinted else 1.15
	var support: Dictionary = {"attemptId":attempt_id,"mapId":str(config.get("id","")),"wave":wave,"x":position_norm.x,"y":position_norm.y,"r":0.17,"hinted":hinted,"duration":duration,"remaining":duration,"unitDamageFactor":factor}
	learning_attempts[attempt_id] = true
	learning_supports.append(support)
	_event("learning-support","전장 지원 · 주변 병력 공격력 +%d%% · %d초" % [8 if hinted else 15,int(duration)])
	_emit_state()
	queue_redraw()
	if actor_overlay != null:
		actor_overlay.queue_redraw()
	var result: Dictionary = support.duplicate(true)
	result["ok"] = true
	return result

func grant_learning_reward(hinted: bool, attempt_id: String, skill: String, anchor: Vector2=Vector2(-1,-1)) -> Dictionary:
	var result: Dictionary=battle_support.claim(attempt_id,hinted,skill,anchor)
	if bool(result.get("ok",false)) and not bool(result.get("duplicate",false)):
		_event("learning-reward",str(result.nameKo)+" 획득 · 전투 복귀 후 발동",{"supportKind":str(result.kind),"attemptId":attempt_id})
		_emit_state()
	return result

func grant_quiz_gold(attempt_id: String) -> int:
	# This battle-only receipt is independent of support availability/hints.
	# Record before emitting state so a reentrant accepted-answer call is safe.
	var receipt_id: String=attempt_id.strip_edges()
	if receipt_id.is_empty() or quiz_gold_receipts.has(receipt_id) or config.is_empty() or finished or battle_closed or (not running and not between_waves): return 0
	var amount: int=25+2*(maxi(1,int(config.get("stageNumber",1)))-1)
	var configured: Variant=config.get("quizCorrectGold",amount)
	if configured is int: amount=maxi(1,int(configured))
	elif configured is float and is_finite(float(configured)): amount=maxi(1,int(configured))
	elif configured is String and str(configured).is_valid_int(): amount=maxi(1,int(configured))
	quiz_gold_receipts[receipt_id]=amount
	gold+=amount
	_emit_state()
	return amount

func _update_learning_supports(delta: float) -> void:
	var active: Array[Dictionary] = []
	for support in learning_supports:
		support["remaining"] = maxf(0.0,float(support.remaining)-delta)
		if float(support.remaining)>0.00001:
			active.append(support)
	learning_supports = active

func _advance_passive_gold(delta: float) -> void:
	# Combat simulation time excludes pause/study and follows the chosen speed.
	# Keep the remainder so frame size and short pauses cannot lose a payment.
	passive_gold_clock+=delta
	var ticks: int=floori((passive_gold_clock+.0000001)/PASSIVE_GOLD_INTERVAL)
	if ticks<=0: return
	passive_gold_clock=maxf(0.0,passive_gold_clock-ticks*PASSIVE_GOLD_INTERVAL)
	gold+=ticks*passive_gold_per_tick

func toggle_bridge() -> void:
	if str(config.get("theme", "")) != "river":
		return
	if bridge_cooldown > 0.0:
		_event("bridge", "다리 전환을 준비 중입니다. 잠시 기다려 주십시오.")
		return
	bridge_index = 1 - bridge_index
	bridge_cooldown = 6.0
	_event("bridge", "새 적은 %s 다리로 진입합니다. 이미 건넌 적은 계속 이동합니다." % bridge_label())
	_emit_state()
	queue_redraw()

func bridge_label() -> String:
	if bridge_index < paths.size():
		var custom_label: String = str(paths[bridge_index].get("displayName", paths[bridge_index].get("label", "")))
		if not custom_label.is_empty():
			return custom_label
	var bridges: Array = config.get("bridges", [])
	if bridges.size() >= 2:
		var first: Vector2 = _point(bridges[0])
		var second: Vector2 = _point(bridges[1])
		if absf(second.x-first.x) > absf(second.y-first.y):
			return "왼쪽" if (bridge_index == 0) == (first.x < second.x) else "오른쪽"
		return "위쪽" if (bridge_index == 0) == (first.y < second.y) else "아래쪽"
	return "제 %d" % (bridge_index + 1)

func _input(event: InputEvent) -> void:
	if ui_deployment_active: return
	# Pointer motion must precede GUI handling: a toolbar Control may consume
	# it before _unhandled_input, while the map ghost still needs to disappear.
	if not input_enabled or finished: return
	if event is InputEventMouseMotion and not pending.is_empty():
		placement_cursor_visible = screen_point_in_field(event.position)
		if placement_cursor_visible: placement_cursor=screen_to_field_point(event.position)
		queue_redraw()
		if actor_overlay!=null: actor_overlay.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or finished or ui_deployment_active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and not pending.is_empty():
		cancel_recruit()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Field geometry uses canvas coordinates. The event retains the actual
		# click even if the pointer has already moved or an automation restores it.
		if not screen_point_in_field(event.position):
			return
		var normalized: Vector2 = screen_to_field_point(event.position)
		if not pending.is_empty():
			place_unit(normalized.x, normalized.y)
		else:
			var assassin: Dictionary=_selected()
			if not assassin.is_empty() and GroundCombat.is_ambush(str(assassin.type)):
				for enemy in enemies:
					if ground_combat.is_tower_attacker(enemy) and enemy.position.distance_to(normalized)<.045:
						var ordered: Dictionary=order_assassination(int(enemy.id))
						if not bool(ordered.accepted): _event("assassination",str(ordered.reasonKo))
						get_viewport().set_input_as_handled()
						return
			selected_id = -1
			var closest: float = 0.055
			for unit in units:
				var distance: float = unit.position.distance_to(normalized)
				if distance < closest:
					closest = distance
					selected_id = int(unit.id)
			explicit_selection_id = selected_id
			_emit_state()
			queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_recruit()

func _process(delta: float) -> void:
	var frame_delta: float = maxf(0.0,delta)
	if running and not paused and not between_waves and not finished:
		# This is the current render frame's budget, never a bank of old time.
		# Repaying stalled frames can accelerate movement, attacks and spawning
		# together while the selected battle speed itself remains unchanged.
		realtime_simulation_pending=minf(frame_delta,0.25)*effective_speed()
		_advance_realtime_simulation()
	elif (finished or between_waves) and not paused and not death_actors.is_empty():
		# Only the already-defeated bodies finish their fall. Battle, support,
		# recovery and cooldown clocks remain suspended during study or results.
		_update_death_actors(minf(frame_delta, 0.15) * effective_speed())
	if not running or between_waves or finished or battle_closed:
		realtime_simulation_pending=0.0
	state_clock += frame_delta
	if state_clock >= 0.25:
		state_clock = 0.0
		_emit_state()
	queue_redraw()

func _advance_realtime_simulation() -> void:
	# Finish each authoritative step, then yield to input/rendering. Overload
	# slows the entire simulation clock rather than accumulating a catch-up
	# burst. It can lengthen a battle's wall time; no actor alone is slowed.
	# Explicit advance_simulation() retains its full-duration contract.
	var started: int=Time.get_ticks_usec()
	var generation: int=battle_generation
	var steps: int=0
	while realtime_simulation_pending>.0000001 and steps<MAX_REALTIME_STEPS and running and not paused and not between_waves and not finished and not battle_closed:
		var step: float=minf(realtime_simulation_pending,MAX_SIMULATION_STEP)
		realtime_simulation_pending=maxf(0.0,realtime_simulation_pending-step)
		advance_simulation(step)
		steps+=1
		if generation!=battle_generation:
			realtime_simulation_pending=0.0
			break
		if Time.get_ticks_usec()-started>=REALTIME_SIMULATION_BUDGET_USEC: break
	# An unfinished render-frame budget is not replayed on a later frame,
	# including after pause, navigation or a selected-speed change.
	realtime_simulation_pending=0.0
	_profile_elapsed("realtimeSimulation",started,steps)

func advance_simulation(delta: float) -> void:
	if not running or paused or between_waves or finished:
		return
	var generation: int=battle_generation
	if not bool(EnemyModeProfiles.profile_for(config).get("combatEnabled",true)):
		# Registered non-combat chapters must wait for their authored task,
		# never acquire a survival victory or combat reinforcements by time.
		elapsed += maxf(0.0,delta)
		animation_time += maxf(0.0,delta)
		_advance_actor_animations(maxf(0.0,delta))
		return
	var remaining: float = maxf(0.0,delta)
	while remaining>.0000001 and running and not paused and not between_waves and not finished and generation==battle_generation:
		var step: float = minf(remaining,MAX_SIMULATION_STEP)
		_advance_simulation_step(step)
		remaining -= step

func _advance_simulation_step(delta: float) -> void:
	var started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	var scope: Dictionary=unit_skills.begin_query_scope()
	_advance_simulation_step_contents(delta)
	unit_skills.end_query_scope(scope)
	_profile_elapsed("simulationStep",started,units.size()+enemies.size())

func _advance_simulation_step_contents(delta: float) -> void:
	var generation: int=battle_generation
	elapsed += delta
	animation_time += delta
	wave_time += delta
	_advance_passive_gold(delta)
	_advance_recruitment(delta)
	if generation!=battle_generation or finished or battle_closed: return
	_advance_ambush_warnings(delta)
	if generation!=battle_generation or finished or battle_closed: return
	var skills_started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	unit_skills.stationary_enemy_queries(true)
	unit_skills.step(delta)
	unit_skills.stationary_enemy_queries(false)
	if generation!=battle_generation or finished or battle_closed: return
	_profile_elapsed("skillStep",skills_started,units.size()+enemies.size())
	battle_support.step(delta)
	_update_learning_supports(delta)
	var animation_started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	unit_skills.stationary_enemy_queries(true)
	_advance_actor_animations(delta)
	unit_skills.stationary_enemy_queries(false)
	_profile_elapsed("actorAnimations",animation_started,units.size()+enemies.size())
	if generation!=battle_generation or finished or battle_closed: return
	bridge_cooldown = maxf(0.0, bridge_cooldown - delta)
	_update_map_mode(delta)
	if generation!=battle_generation or finished or battle_closed: return
	spawn_clock -= delta
	if battle_support.departure_delay>0.0: spawn_clock=maxf(spawn_clock,.025)
	while spawn_clock <= 0.0 and not spawn_queue.is_empty():
		var options: Dictionary=spawn_metadata.pop_front() if spawn_metadata.size()==spawn_queue.size() else {}
		var source_wave: int = int(spawn_source_waves.pop_front()) if spawn_source_waves.size()==spawn_queue.size() else wave
		_queue_enemy_spawn(str(spawn_queue.pop_front()),source_wave,options)
		if generation!=battle_generation or finished or battle_closed: return
		spawn_clock += _spawn_interval()
	if spawn_queue.is_empty(): spawn_clock=maxf(0.0,spawn_clock)
	var ground_started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	ground_combat.step(delta)
	_profile_elapsed("groundStep",ground_started,units.size())
	_remove_consumed_units()
	if generation!=battle_generation or finished or battle_closed: return
	var enemy_started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	movement_ranges.clear()
	var movement_radius: float=0.0
	for unit in units:
		if ground_combat.active_support(unit):
			var unit_range: float=movement_search_range(unit)+.025
			movement_ranges[int(unit.id)]=unit_range
			movement_radius=maxf(movement_radius,unit_range)
	var movement_context: Dictionary=unit_skills.membership_query_context()
	if not movement_context.is_empty():
		movement_context["movementQueryRadius"]=movement_radius
		movement_context["movementQueryClock"]=elapsed
	_prepare_enemy_approach_step(delta)
	for enemy in enemies:
		if float(enemy.hp) <= 0.0:
			continue
		var previous_enemy_position: Vector2=enemy.position
		_move_enemy(enemy, delta)
		if generation!=battle_generation or finished or battle_closed: break
		if float(enemy.get("hp",0.0))>0.0 and is_same(_enemy(int(enemy.id)),enemy): ground_combat.finish_enemy_step(enemy,previous_enemy_position)
	enemy_approach_step.clear()
	_profile_elapsed("enemyStep",enemy_started,enemies.size())
	_remove_fallen_units()
	if finished:
		return
	var attacks_started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	unit_skills.stationary_enemy_queries(true)
	_update_units(delta)
	_profile_elapsed("friendlyAttacks",attacks_started,units.size())
	var shots_started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	_update_projectiles(delta)
	unit_skills.stationary_enemy_queries(false)
	_profile_elapsed("projectileStep",shots_started,projectiles.size())
	_remove_consumed_units()
	if generation!=battle_generation or finished or battle_closed: return
	if friendly_casualties_pending:
		_remove_fallen_units()
		friendly_casualties_pending=false
	var survivors: Array = []
	for enemy in enemies:
		if float(enemy.hp) <= 0.0:
			if not bool(enemy.get("escaped", false)) and not bool(enemy.get("deathRewardConsumed",false)):
				enemy["deathRewardConsumed"]=true
				kills += 1
				gold += int(enemy.reward)
				var last_hit: Dictionary = enemy.get("lastHit",{})
				var killer: Dictionary = {"id":last_hit.get("actorId",-1),"type":last_hit.get("unitType",""),"position":last_hit.get("sourcePosition",enemy.position)}
				unit_skills.on_enemy_killed(enemy,killer)
				if generation!=battle_generation or battle_closed: return
				_combat_event("killed",killer,enemy,{"reward":int(enemy.reward),"position":_normalized_position(enemy.position),"side":"friendly"})
				if generation!=battle_generation or battle_closed: return
				death_actors.append({"id":enemy.id,"position":enemy.position,"aim":enemy.aim,"kind":enemy.kind,"animation":"death","animationClock":0.0,"animationPhase":0.0,"sailing":_sailing_visual(enemy),"fortification":bool(enemy.get("fortification",false)),"stationaryEnemy":bool(enemy.get("stationaryEnemy",false)),"hp":0.0,"maxHp":float(enemy.maxHp),"historicalCommander":enemy.get("historicalCommander",{}).duplicate(true)})
				effects.append({"position":enemy.position,"time":0.0,"duration":0.4,"color":Color("dcb36d"),"kind":"hit"})
		else:
			survivors.append(enemy)
	if survivors.size()!=enemies.size(): enemies = survivors
	advance_mission.step(delta)
	if advance_mission.enabled and advance_mission.failed:
		_finish(false)
		return
	if _try_finish_cycles(): return
	_update_death_actors(delta)
	for effect in effects:
		effect["time"] = float(effect.time) + delta
	effects = effects.filter(func(effect): return float(effect.time) < float(effect.duration))
	if finished:
		return
	if bool(config.get("trainingOnly",false)): return
	if _cycle_attackers_cleared(): _complete_wave()

func _remove_consumed_units() -> void:
	var generation: int=battle_generation
	var was_closed: bool=battle_closed
	var survivors: Array=[]
	var departed: Array=[]
	for unit in units:
		if not bool(unit.get("consumed",false)):
			survivors.append(unit)
			continue
		departed.append(unit)
		unit["attackPlan"]={}
		for enemy in enemies:
			ground_combat.remove_contact(enemy,int(unit.id))
			if int(enemy.get("stationaryTargetId",-1))==int(unit.id):
				_begin_hunter_return(enemy)
		if selected_id==int(unit.id): selected_id=-1
	if departed.is_empty(): return
	units=survivors
	unit_skills.invalidate_roster_index()
	_refresh_placement_hints()
	# Consumption is an irreversible departure, not a casualty or a refund.
	for unit in departed:
		_combat_event("unit_consumed",unit,{}, {"side":"friendly","consumeReason":str(unit.get("consumeReason","mission_ended")),"targetId":int(unit.get("consumedTargetId",-1)),"deploymentKind":"ambush","message":"%s 임무 종료 · 소모" % unit.name})
		if generation!=battle_generation or (battle_closed and not was_closed): return

func _remove_fallen_units() -> void:
	var has_fallen: bool=false
	for unit in units:
		if float(unit.get("hp",0))<=0.0:
			has_fallen=true
			break
	if not has_fallen: return
	var previous_count: int=units.size()
	var survivors: Array=[]
	for unit in units:
		if float(unit.get("hp",0))>0:
			survivors.append(unit)
			continue
		for enemy in enemies:
			ground_combat.remove_contact(enemy,int(unit.id))
		var actor: Dictionary=unit.duplicate(true)
		actor["friendly"]=true
		actor["kind"]="friendly"
		actor["animation"]="death"
		actor["animationClock"]=0.0
		actor["attackPlan"]={}
		actor["sailing"]=false
		death_actors.append(actor)
		_combat_event("unit_fallen",unit,{}, {"side":"friendly","deploymentKind":str(placement_contract(str(unit.type)).deploymentKind),"message":"%s 전사" % unit.name})
		if selected_id==int(unit.id): selected_id=-1
	# Preserve roster identity when nobody died. Replacing an unchanged array
	# invalidates the spatial index and melee graph halfway through this step.
	if survivors.size()!=previous_count:
		units=survivors
		unit_skills.invalidate_roster_index()
		_refresh_placement_hints()

func _refill_timed_wave() -> void:
	# Compatibility only: finite cycles never replenish an exhausted queue.
	return

func _begin_wave() -> void:
	if bool(config.get("trainingOnly",false)): return
	if not bool(EnemyModeProfiles.profile_for(config).get("combatEnabled",true)): return
	if wave >= total_waves:
		_try_finish_cycles()
		return
	if wave>0 and completed_wave<wave: return
	var generation: int=battle_generation
	wave += 1
	var started_cycle: int=wave
	wave_time = 0.0
	spawn_plan_cursor=0
	attack_pattern=EnemyModeProfiles.attack_pattern(config,wave)
	spawn_clock = _spawn_delay()
	if spawn_metadata.size()!=spawn_queue.size():
		spawn_metadata.clear()
		for _entry in spawn_queue: spawn_metadata.append({})
	battle_refill_clock=0.0
	battle_refill_cursor=0
	if wave_spawn_schedule.is_empty(): wave_spawn_schedule=_build_wave_schedule()
	var entries: Array=wave_spawn_schedule[wave-1].duplicate(true)
	if attack_pattern=="formation":
		entries.sort_custom(func(a,b): return (0 if str(a.kind) in ["shield","heavy"] else 1)<(0 if str(b.kind) in ["shield","heavy"] else 1))
	elif attack_pattern=="mounted_vanguard":
		entries.sort_custom(func(a,b): return (0 if str(a.kind)=="runner" else 1)<(0 if str(b.kind)=="runner" else 1))
	for entry in entries: _append_spawn_entry(str(entry.kind),int(entry.sourceWave))
	_append_emplacement_assault()
	if generation!=battle_generation or finished or battle_closed or wave!=started_cycle: return
	if not advance_mission.enabled and (wave % 5 == 0 or wave == total_waves):
		_append_spawn_entry("commander",_combat_wave_level())
	var extra: Dictionary = _trait().get("reinforcements", {})
	if not extra.is_empty() and wave % maxi(1, int(extra.get("every", 1))) == 0:
		var kind: String = str(extra.get("kind", "raider"))
		if kind in ["raider","runner","shield","heavy","commander"]:
			for index in range(clampi(int(extra.get("count", 1)), 0, 8)):
				_append_spawn_entry(kind,_combat_wave_level())
	_event("wave", "제 %d 파상 공격 · 적 %d기" % [wave, spawn_queue.size()],{"side":"system","count":spawn_queue.size(),"spawnDelay":spawn_clock,"spawnInterval":_spawn_interval()})
	if generation!=battle_generation or finished or battle_closed or wave!=started_cycle: return
	_emit_state()
	if generation!=battle_generation or finished or battle_closed or wave!=started_cycle: return
	wave_started.emit({"wave":wave,"mapId":str(config.get("id",""))})

func _ninja_unlock_stage() -> int:
	return int(recruit_catalog.get("ninja",{}).get("unlockClears",14))+1

func emplacement_assault_plan() -> Dictionary:
	var targets: Array=[]
	var authored_targets: Array=config.get("emplacementAssaultZoneIds",["left-shoulder-pad","right-shoulder-pad"])
	for zone in zones:
		if str(zone.get("placementRole",""))!="ranged": continue
		if not deployment_zone_active(zone): continue
		if bool(config.get("paintedPresentation",false)) and str(zone.get("id","")) not in authored_targets: continue
		targets.append(str(zone.id))
	var settings: Dictionary=EnemyModeProfiles.assault_settings(config)
	var start_wave: int=maxi(1,int(settings.get("startWave",3)))
	var cadence: int=maxi(1,int(settings.get("everyWaves",3)))
	var active: bool=not bool(config.get("trainingOnly",false)) and wave>=start_wave and (wave-start_wave)%cadence==0 and not targets.is_empty()
	return {"active":active,"targetZoneIds":targets,"groupSize":clampi(int(settings.get("groupSize",2)),1,2),"maxGroupsPerAssault":2,"lastDispatchedZoneIds":last_emplacement_targets.duplicate(),"cadenceWaves":cadence,"mainPressure":"continuous"}

func _append_emplacement_assault() -> void:
	if not bool(EnemyModeProfiles.assault_settings(config).get("enabled",true)): return
	var plan: Dictionary=emplacement_assault_plan()
	if not bool(plan.active): return
	var dispatched: Array=[]
	var targets: Array=plan.targetZoneIds
	for target_zone_id in targets:
		if dispatched.size()>=int(plan.maxGroupsPerAssault): break
		var zone_id: String=str(target_zone_id)
		var path_index: int=_emplacement_assault_path(zone_id)
		if path_index<0: continue
		dispatched.append(zone_id)
		for member in range(int(plan.groupSize)):
			var kind: String=EnemyModeProfiles.assault_kind(config,member,wave)
			spawn_queue.append(kind)
			spawn_source_waves.append(_combat_wave_level())
			spawn_metadata.append({"originKind":"raider","formationPattern":"coordinated_assault","formationGroup":"w%d:assault:%s" % [wave,zone_id],"formationRank":0,"formationLane":member,"assaultZoneId":zone_id,"mainIngressOnly":true,"pathIndex":path_index,"fortification":false})
	if not dispatched.is_empty():
		last_emplacement_targets=dispatched.duplicate()
		_event("emplacement_warning","주 진격 지속 · 적 원거리병 접근",{"side":"enemy","targetZoneIds":dispatched,"count":dispatched.size()*int(plan.groupSize)})

func _emplacement_assault_path(zone_id: String) -> int:
	var target: Dictionary={}
	for zone in zones:
		if str(zone.get("id",""))==zone_id: target=zone;break
	if target.is_empty(): return -1
	var selected: int=-1
	var closest: float=INF
	for path_index in range(paths.size()):
		for segment in range(paths[path_index].points.size()-1):
			var distance: float=ground_combat.point_distance(path_index,segment,target.position)
			var point: Vector2=ground_combat.route_point(path_index,distance)
			var separation: float=point.distance_to(target.position)
			if separation<closest and ground_combat.land_segment_safe(point,target.position): selected=path_index;closest=separation
	return selected

func _append_spawn_entry(origin: String, source_wave: int) -> void:
	if not bool(EnemyModeProfiles.profile_for(config).get("combatEnabled",true)): return
	var ordinal: int=spawn_plan_cursor
	spawn_plan_cursor+=1
	var kind: String=origin
	var stage: int=int(config.get("stageNumber",1))
	if wave>=3 and origin!="commander":
		if origin=="runner" and stage>=9: kind="enemy_cavalry"
	var tower_settings: Dictionary=EnemyModeProfiles.fortification_settings(config)
	var tower_start: int=maxi(1,int(tower_settings.get("startWave",3)))
	var tower_cadence: int=maxi(1,int(tower_settings.get("everyWaves",2)))
	var fortification: bool=bool(tower_settings.get("enabled",false)) and stage>=int(tower_settings.get("minStage",15)) and wave>=tower_start and (wave-tower_start)%tower_cadence==0 and ordinal==0 and origin!="commander"
	if fortification: kind=EnemyModeProfiles.fortification_kind(config,wave)
	if emplacement_protection_active():
		if kind in EMPLACEMENT_ENEMY_KINDS: kind=origin
		fortification=false
	var cohort_size: int=_enemy_approach_cohort_size()
	var group: int=ordinal/cohort_size
	var path_index: int=-1
	if not paths.is_empty():
		# Rotate the first cohort, not the whole army into one road. Every
		# successive six-soldier group retains its own authored route.
		var route_offset: int=(maxi(1,wave)-1)%paths.size() if bool(_trait().get("cycleRoutes",false)) else 0
		path_index=(group+route_offset)%paths.size()
	var member: int=ordinal%cohort_size
	var columns: int=_enemy_formation_columns(attack_pattern)
	var lane: int=_enemy_formation_lane(member,columns)
	var rank: int=member/columns
	spawn_queue.append(kind)
	spawn_source_waves.append(source_wave)
	spawn_metadata.append({"originKind":origin,"combatRole":str(enemy_role_contract(kind).combatRole),"formationPattern":attack_pattern,"formationGroup":"w%d:g%d" % [wave,group],"formationRank":rank,"formationLane":lane,"pathIndex":path_index,"fortification":fortification,"mainIngressOnly":fortification})

func _load_campaign_story() -> void:
	if campaign_story_loaded: return
	campaign_story_loaded=true
	var path: String="res://native/campaign_story.json"
	if not FileAccess.file_exists(path): return
	var content: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not content is Dictionary: return
	for entry in content.get("stages",[]): campaign_story_index[str(entry.get("stageId",""))]=entry

func _fortification_position(path_index: int) -> Dictionary:
	var total: float=float(ground_combat.cumulative[path_index][-1])
	var first_land: float=0.0
	if str(config.get("theme",""))=="harbor":
		var landing: int=clampi(int(config.get("landingIndex",2)),0,ground_combat.cumulative[path_index].size()-1)
		first_land=float(ground_combat.cumulative[path_index][landing])
	var candidates: Array=[]
	for fraction in [.12,.22,.32]: candidates.append(lerpf(first_land,total,float(fraction)))
	for site in ground_combat.ambush_sites:
		if int(site.pathIndex)==path_index: candidates.append(float(site.homeDistance))
	for segment in range(ground_combat.cumulative[path_index].size()-1):
		for fraction in [.2,.5,.8]: candidates.append(ground_combat.marker_distance(path_index,segment,float(fraction)))
	for candidate in candidates:
		var distance: float=float(candidate)
		if distance<first_land+.008: continue
		var position: Vector2=ground_combat.route_point(path_index,distance)
		if not Rect2(.04,.06,.92,.88).has_point(position): continue
		if not ground_combat.land_segment_safe(position,position,.015): continue
		var reachable: bool=false
		for site in ground_combat.ambush_sites:
			if int(site.pathIndex)==path_index and site.position.distance_to(position)<=float(recruit_catalog.get("ninja",{}).get("range",.15))*2.0 and ground_combat.land_route_safe(path_index,float(site.homeDistance),distance): reachable=true;break
		if not reachable: continue
		var occupied: bool=false
		for enemy in enemies:
			var other_station: Vector2=enemy.get("fortificationPosition",enemy.position)
			if (bool(enemy.get("fortification",false)) or bool(enemy.get("stationaryAfterIngress",false))) and float(enemy.hp)>0 and other_station.distance_to(position)<.055: occupied=true;break
		if occupied: continue
		var point_index: int=1
		for index in range(1,ground_combat.cumulative[path_index].size()):
			if distance<=float(ground_combat.cumulative[path_index][index]): point_index=index;break
		return {"position":position,"distance":distance,"pointIndex":point_index}
	return {}

func _fortification_ingress(path_index: int, station: Dictionary) -> Dictionary:
	if station.is_empty() or path_index<0 or path_index>=paths.size(): return {}
	var points: Array=paths[path_index].points
	if points.size()<2: return {}
	var start: Vector2=points[0]
	var forward: Vector2=points[1]-start
	if forward.length_squared()<.000001: return {}
	forward=forward.normalized()
	# Legacy paths can begin on-screen. Extend their actual first leg backwards
	# only after checking the complete physical connection to the authored road.
	var offscreen: Rect2=Rect2(-.05,-.05,1.10,1.10)
	var extension: int=0
	while offscreen.has_point(start) and extension<20:
		start-=forward*.12
		extension+=1
	if offscreen.has_point(start): return {}
	var ingress: Array=[start]
	if start.distance_to(points[0])>.000001: ingress.append(points[0])
	var station_distance: float=float(station.distance)
	for index in range(1,points.size()):
		if float(ground_combat.cumulative[path_index][index])>=station_distance-.000001: break
		ingress.append(points[index])
	ingress.append(station.position)
	for index in range(ingress.size()-1):
		if not ground_combat.land_segment_safe(ingress[index],ingress[index+1],.002): return {}
	return {"id":"fortification-main-%d" % path_index,"pathIndex":path_index,"points":ingress,"joinDistance":station_distance,"pointIndex":int(station.pointIndex)}

func _original_wave_kind(wave_number: int, index: int) -> String:
	var kind: String = "raider"
	if wave_number>=2 and index%5==3: kind="runner"
	if wave_number>=3 and index%6==4: kind="shield"
	if wave_number>=6 and index%9==7: kind="heavy"
	# Historical terrain changes should not silently replace the original roster.
	var encounter_theme: String = str(config.get("historicalBattlefield",{}).get("legacyEncounterTheme",config.get("theme","")))
	if encounter_theme=="siege" and index%5==4: kind="shield"
	return EnemyModeProfiles.original_kind(config,wave_number,index,kind)

func _build_wave_schedule() -> Array:
	if _is_cycle_battle():
		var cycle_schedule: Array=[]
		for plan in battle_plan.waves:
			cycle_schedule.append(plan.entries.duplicate(true))
		return cycle_schedule
	return _build_base_wave_schedule(total_waves)

func _build_base_wave_schedule(wave_count: int) -> Array:
	# Redistribute the exact original roster. Each soldier retains its original
	# HP/speed, reward and armor; only arrival waves change. Stage traits and
	# scheduled commanders/reinforcements keep their original wave triggers.
	var original: Array = []
	var weights: Array = []
	var total_weight: float = 0.0
	for wave_number in range(1,wave_count+1):
		var original_count: int = 9+wave_number*2+int(config.get("tierIndex",0))*2+int(config.get("level",1))/3
		for index in range(original_count):
			original.append({"kind":_original_wave_kind(wave_number,index),"sourceWave":wave_number})
		var progress: float = float(wave_number-1)/maxf(1,float(wave_count-1))
		var weight: float = 4.0+34.0*pow(progress,1.3)
		weights.append(weight)
		total_weight+=weight
	var schedule: Array = []
	var cursor: int = 0
	var cumulative_weight: float = 0.0
	for weight in weights:
		cumulative_weight+=float(weight)
		var next_cursor: int = mini(original.size(),roundi(float(original.size())*cumulative_weight/total_weight))
		schedule.append(original.slice(cursor,next_cursor))
		cursor=next_cursor
	return schedule

func _wave_progress() -> float:
	if _is_cycle_battle():
		return clampf(float(_combat_wave_level()-1)/maxf(1,float(battle_plan.baseTotalWaves-1)),0,1)
	return clampf(float(wave-1)/maxf(1,float(total_waves-1)),0,1)

func _spawn_delay() -> float:
	return 3.0 if wave<=1 else 2.0 if wave==2 else 1.0

func _spawn_interval() -> float:
	var authored: float=float(_cycle_wave().get("spawnInterval",0.0))
	if authored>0.0: return authored
	var fallback: float
	if _is_cycle_battle():
		if str(config.get("id",""))=="basic-forest" and int(config.get("stageNumber",0))==1:
			fallback=1.20 if wave<=1 else 1.10 if wave==2 else lerpf(1.00,0.62,clampf(float(_combat_wave_level()-3)/maxf(1,float(battle_plan.baseTotalWaves-3)),0,1))
		else:
			fallback=1.50 if wave<=1 else 1.35 if wave==2 else lerpf(1.15,0.62,clampf(float(_combat_wave_level()-3)/maxf(1,float(battle_plan.baseTotalWaves-3)),0,1))
	else:
		fallback=1.50 if wave<=1 else 1.35 if wave==2 else lerpf(1.15,0.62,clampf(float(wave-3)/maxf(1,float(total_waves-3)),0,1))
	return fallback*BattleDuration.ARRIVAL_INTERVAL_MULTIPLIER

func _approach_march_factor() -> float:
	return lerpf(2.35,4.0,pow(_wave_progress(),0.85))

func _spawn_path_index(options: Dictionary) -> int:
	if paths.is_empty(): return -1
	# Side-entry geometry owns its join route. A queued cohort's explicit
	# route also survives spawning, regardless of visual theme or wave.
	var entry: Dictionary=options.get("ambushEntry",{})
	var entry_path: int=int(entry.get("pathIndex",-1))
	if entry_path>=0 and entry_path<paths.size(): return entry_path
	var requested: int=int(options.get("pathIndex",-1))
	if requested>=0 and requested<paths.size(): return requested
	return rng.randi_range(0,paths.size()-1)

func _stage01_light_replacements() -> bool:
	return str(config.get("id",""))=="basic-forest" and int(config.get("stageNumber",1))==1 and bool(config.get("paintedPresentation",false))

func _enemy_approach_cohort_size() -> int:
	return clampi(int(config.get("enemyApproachCohortSize",3)),3,6) if advance_mission.enabled else 6

func _spawn_enemy(kind: String, source_wave: int = -1, options: Dictionary = {}) -> Dictionary:
	if not bool(EnemyModeProfiles.profile_for(config).get("combatEnabled",true)): return {}
	if paths.is_empty():
		return {}
	# Mobile emplacement pressure is now ordinary ranged infantry on the
	# existing road. The separate, authored enemy fortifications stay intact.
	if kind=="enemy_samurai" and not bool(options.get("fortification",false)): kind="enemy_archer"
	var origin_kind: String=str(options.get("originKind",{"enemy_archer":"raider","enemy_gunner":"shield","enemy_cavalry":"runner","enemy_samurai":"heavy"}.get(kind,kind)))
	if _stage01_light_replacements() and kind in ["heavy","enemy_samurai","samurai"]:
		kind="raider"
		origin_kind="raider"
	if emplacement_protection_active() and kind in EMPLACEMENT_ENEMY_KINDS: kind=origin_kind
	var path_index: int=_spawn_path_index(options)
	var path: Dictionary = paths[path_index]
	var prepared_station: Dictionary={}
	if kind in ["enemy_archer","enemy_gunner"] and bool(options.get("fortification",false)):
		var tower_settings: Dictionary=EnemyModeProfiles.fortification_settings(config)
		if int(config.get("stageNumber",1))>=int(tower_settings.get("minStage",15)):
			prepared_station=_fortification_position(path_index)
		var crew_entry: Dictionary=_fortification_ingress(path_index,prepared_station)
		options=options.duplicate(true)
		if prepared_station.is_empty() or crew_entry.is_empty():
			# Unsafe cover never appears halfway down a road. Keep the original
			# main-front soldier instead and expose the rejected request in evidence.
			kind=origin_kind
			options["fortification"]=false
			options.erase("ambushEntry")
			_event("fortification_unavailable","안전한 적 사격 진지 없음 · 주 전선 합류",{"side":"enemy","pathIndex":path_index,"reason":"no_reachable_station_or_offscreen_route"})
		else:
			options["ambushEntry"]=crew_entry
	# Reapply after legacy protection/fortification fallback conversions too.
	if _stage01_light_replacements() and kind in ["heavy","enemy_samurai","samurai"]:
		kind="raider"
		origin_kind="raider"
	var road_ranged: bool=kind in ["enemy_archer","enemy_gunner"] and prepared_station.is_empty() and not bool(options.get("fortification",false))
	if road_ranged: origin_kind="raider"
	var difficulty: float = float(config.get("difficulty", 1.0))
	var first_stage: bool = str(config.get("id", "")) == "basic-forest" and int(config.get("stageNumber", 0)) == 1
	if first_stage:
		difficulty *= FIRST_STAGE_ENEMY_HP_FACTOR
	var difficulty_wave: int = wave if source_wave<0 else source_wave
	var base_hp: float = (32.0 + difficulty_wave * 10.0) * difficulty
	var move_speed: float = 0.020 + difficulty_wave * 0.00035
	var armor: float = .08 if first_stage and origin_kind in ["raider","runner"] else 0.0
	var damage: int = 1
	var reward: int = 7
	match origin_kind:
		"runner":
			base_hp *= 0.7
			move_speed *= 1.5
		"shield":
			base_hp *= 1.65
			move_speed *= 0.78
			armor = 0.38
			reward = 11
			damage = 2
		"heavy":
			base_hp *= 2.2
			move_speed *= 0.72
			armor = 0.25
			damage = 3
			reward = 30
		"commander":
			base_hp *= 6.0
			move_speed *= 0.62
			armor = 0.3
			damage = 5
			reward = 90
	# Samurai aliases retain their existing combat statistics, but share the
	# heavy/samurai kill bounty even when their authored origin is different.
	if kind=="commander" or origin_kind=="commander": reward=90
	elif kind in ["heavy","enemy_samurai","samurai"] or origin_kind in ["heavy","enemy_samurai","samurai"]: reward=30
	if first_stage or (str(config.get("id",""))=="basic-farm" and int(config.get("stageNumber",0))==2):
		reward=maxi(1,roundi(float(reward)*clampf(float(config.get("enemyBountyMultiplier",1.0)),0.0,1.0)))
	for bonus in _trait().get("enemyBonuses", []):
		if str(bonus.get("kind", "all")) in [kind,origin_kind,"all"]:
			base_hp *= float(bonus.get("hpFactor", 1.0))
			move_speed *= float(bonus.get("speedFactor", 1.0))
	var enemy: Dictionary = {"id":next_id,"kind":kind,"sourceWave":difficulty_wave,"hp":base_hp,"maxHp":base_hp,"speed":move_speed,"armor":armor,"damage":damage,"reward":reward,"pathIndex":path_index,"pointIndex":1,"position":path.points[0],"aim":Vector2.RIGHT,"escaped":false,"animation":"walk","animationClock":0.0,"animationPhase":fmod(float(next_id)*0.117,1.0),"hitClock":0.0}
	enemy.merge(enemy_role_contract(kind),true)
	enemy["roadRanged"]=road_ranged
	enemy["assaultZoneId"]=str(options.get("assaultZoneId",""))
	enemy["spawnPathIndex"]=path_index
	enemy["routeProgress"]=0.0
	enemy.merge({"originKind":origin_kind,"formationPattern":str(options.get("formationPattern","skirmish")),"formationGroup":str(options.get("formationGroup","")),"formationRank":int(options.get("formationRank",0)),"formationLane":int(options.get("formationLane",0)),"stationaryEnemy":false,"fortification":false})
	if kind in ["enemy_archer","enemy_gunner"]:
		enemy["attackRange"]=.205 if kind=="enemy_archer" else .14
		enemy["attackInterval"]=.85 if kind=="enemy_archer" else 1.55
		enemy["rangedPlan"]={}
		enemy["attackCooldown"]=0.0
		if not prepared_station.is_empty() and bool(options.get("fortification",false)):
			enemy.merge({"position":prepared_station.position,"pointIndex":int(prepared_station.pointIndex),"stationaryEnemy":true,"fortification":true,"animation":"idle","formationLane":0,"fortificationPosition":prepared_station.position},true)
	if kind=="commander":
		var story: Dictionary=campaign_story_index.get(str(config.get("id","")),{})
		if not story.is_empty() and bool(story.get("opponentOnField",true)) and story.get("opponent") is Dictionary:
			var commander: Dictionary=story.opponent.duplicate(true)
			commander.merge({"id":str(commander.get("id",story.get("battleEventId","opponent"))),"battleEventId":str(story.get("battleEventId","")),"year":int(story.get("year",0))},true)
			enemy["historicalCommander"]=commander
	if not bool(enemy.stationaryEnemy): enemy.position=_enemy_lane_point(enemy,0)
	if options.has("ambushEntry") and str(enemy.combatRole)==ENEMY_EMPLACEMENT_ROLE and not road_ranged:
		var entry: Dictionary=options.ambushEntry
		var ingress: Array=entry.points.duplicate()
		var settles: bool=bool(enemy.stationaryEnemy)
		if settles:
			var station_distance: float=ground_combat.enemy_distance(enemy)
			var join_distance: float=float(entry.joinDistance)
			var stop_points: Array=[]
			var lengths: Array=ground_combat.cumulative[path_index]
			if station_distance>=join_distance:
				for index in range(lengths.size()):
					if float(lengths[index])>join_distance+.00001 and float(lengths[index])<station_distance-.00001: stop_points.append(path.points[index])
			else:
				for index in range(lengths.size()-1,-1,-1):
					if float(lengths[index])<join_distance-.00001 and float(lengths[index])>station_distance+.00001: stop_points.append(path.points[index])
			stop_points.append(enemy.position)
			var previous: Vector2=ingress[-1]
			for point in stop_points:
				if not ground_combat.land_segment_safe(previous,point,.002): settles=false;break
				previous=point
			if settles: ingress.append_array(stop_points)
		var final_index: int=int(enemy.pointIndex) if settles else int(entry.pointIndex)
		# Prepared cover is stationary. The crew walks in from the side; cover
		# must not become a moving bunker or an assassination target en route.
		enemy.merge({"position":ingress[0],"pointIndex":int(entry.pointIndex),"ingressPoints":ingress,"ingressIndex":1,"ingressActive":true,"ingressJoinDistance":float(entry.joinDistance),"ingressPointIndex":final_index,"stationaryAfterIngress":settles,"stationaryEnemy":false,"fortification":false,"ambushEntranceId":str(entry.id),"routeProgress":float(entry.joinDistance)},true)
		var transport: Array = []
		for point in entry.get("transportPoints",[]): transport.append(_point(point))
		if str(entry.get("transportKind",""))=="boat" and transport.size()>=2 and transport[-1].distance_to(ingress[0])<.00001:
			enemy.merge({"position":transport[0],"transportPoints":transport,"transportIndex":1,"transportKind":"boat","transportActive":true},true)
		_prepare_ingress_target(enemy)
	_prepare_enemy_approach_birth(enemy)
	# Face the first real leg before the first render. Boat transport and
	# hidden ingress take precedence over the unrelated main-road heading.
	var first_destination: Vector2=_enemy_lane_point(enemy,int(enemy.pointIndex))
	if bool(enemy.get("transportActive",false)):
		first_destination=enemy.transportPoints[int(enemy.transportIndex)]
	elif bool(enemy.get("ingressActive",false)):
		first_destination=enemy.ingressPoints[int(enemy.ingressIndex)]
		if enemy.has("ingressTargetPoint") and int(enemy.ingressIndex)==int(enemy.ingressTargetIndex):
			first_destination=enemy.ingressTargetPoint
	var spawn_direction: Vector2=first_destination-enemy.position
	if spawn_direction.length_squared()>.000000001:
		enemy.aim=spawn_direction.normalized()
	else:
		var forward_index: int=clampi(int(enemy.pointIndex),1,path.points.size()-1)
		enemy.aim=(path.points[forward_index]-path.points[forward_index-1]).normalized()
	if _is_cycle_battle(): enemy["counterWave"]=difficulty_wave
	next_id += 1
	enemies.append(enemy)
	return enemy

func _prepared_ambush_entry(path_index: int) -> Dictionary:
	var candidates: Array=[]
	for authored in config.get("sideAmbushEntrances",[]):
		if int(authored.get("pathIndex",-1))!=path_index: continue
		var points: Array=[_point(authored.get("point",{}))]
		for connection in authored.get("connectionPoints",[]):
			var point: Vector2=_point(connection)
			if points[-1].distance_to(point)>.00001: points.append(point)
		if points.size()<2: continue
		var safe: bool=true
		for index in range(points.size()-1):
			if not points[index].is_finite() or not ground_combat.land_segment_safe(points[index],points[index+1],.002): safe=false;break
		if not safe: continue
		var closest: float=INF
		var join: float=0.0
		var segment_index: int=0
		for segment in range(paths[path_index].points.size()-1):
			var distance: float=ground_combat.point_distance(path_index,segment,points[-1])
			var offset: float=ground_combat.route_point(path_index,distance).distance_to(points[-1])
			if offset<closest: closest=offset;join=distance;segment_index=segment
		if closest>.004: continue
		points[-1]=ground_combat.route_point(path_index,join)
		if not ground_combat.land_segment_safe(points[-2],points[-1],.002): continue
		var candidate: Dictionary = {"id":str(authored.get("id","side:"+str(path_index))),"pathIndex":path_index,"points":points,"joinDistance":join,"pointIndex":segment_index+1}
		if str(authored.get("transportKind",""))=="boat":
			var transport: Array = []
			for value in authored.get("transportPoints",[]):
				var transport_point: Vector2 = _point(value)
				if not transport_point.is_finite() or transport_point.x<0 or transport_point.x>1 or transport_point.y<0 or transport_point.y>1: safe=false;break
				if transport.is_empty() or transport[-1].distance_to(transport_point)>.00001: transport.append(transport_point)
			if not safe or transport.size()<2 or transport[-1].distance_to(points[0])>.00001: continue
			candidate["transportPoints"] = transport
			candidate["transportKind"] = "boat"
		candidates.append(candidate)
	return candidates[rng.randi_range(0,candidates.size()-1)] if not candidates.is_empty() else {}

func _queue_enemy_spawn(kind: String, source_wave: int, options: Dictionary) -> void:
	if not bool(EnemyModeProfiles.profile_for(config).get("combatEnabled",true)): return
	# Mobile ranged soldiers enter on the same authored road as the main
	# column. Enemy fortification crews still prepare their own safe ingress.
	_spawn_enemy(kind,source_wave,options)

func _advance_ambush_warnings(delta: float) -> void:
	var generation: int=battle_generation
	var keep: Array=[]
	for warning in ambush_warnings:
		warning.remainingSeconds=maxf(0,float(warning.remainingSeconds)-delta)
		if float(warning.remainingSeconds)>0.0000001: keep.append(warning);continue
		_spawn_enemy(str(warning.kind),int(warning.sourceWave),warning.options)
		if generation!=battle_generation or finished or battle_closed: return
	ambush_warnings=keep

func _prepare_ingress_target(enemy: Dictionary) -> void:
	if bool(enemy.get("transportActive",false)) or not bool(enemy.get("ingressActive",false)) or bool(enemy.get("stationaryAfterIngress",false)) or int(enemy.get("stationaryTargetId",-1))>=0: return
	enemy["ingressTargetClock"]=.35
	var best: Dictionary={}
	var best_cost: float=INF
	var best_point: Vector2=Vector2.ZERO
	var best_index: int=-1
	var travelled: float=0.0
	# Keep the authored corridor, but leave it at the nearest safe connection
	# to a real firing emplacement instead of overshooting to the main road.
	for index in range(int(enemy.ingressIndex),enemy.ingressPoints.size()):
		var start: Vector2=enemy.position if index==int(enemy.ingressIndex) else enemy.ingressPoints[index-1]
		var end: Vector2=enemy.ingressPoints[index]
		for unit in units:
			if str(unit.get("type","")) not in ["archer","gunner"] or not can_enemy_engage_unit(enemy,unit): continue
			var connections: Array=[Geometry2D.get_closest_point_to_segment(unit.position,start,end),start,end]
			for connection in connections:
				var distance: float=connection.distance_to(unit.position)
				if distance>HUNTER_ACQUIRE_RADIUS or not ground_combat.land_segment_safe(connection,unit.position): continue
				if _mobile_emplacement_attacker(enemy) and not _find_emplacement_goal(enemy,unit,connection).is_finite(): continue
				var cost: float=travelled+start.distance_to(connection)+distance
				if cost<best_cost:
					best=unit;best_cost=cost;best_point=connection;best_index=index
		travelled+=start.distance_to(end)
	if best.is_empty(): return
	enemy["stationaryTargetId"]=int(best.id)
	enemy["ingressTargetPoint"]=best_point
	enemy["ingressTargetIndex"]=best_index
	enemy["targetCommitTime"]=elapsed
	enemy["targetLostClock"]=0.0
	ground_combat.cancel_counterattack(enemy)

func _enemy_ingress_step(enemy: Dictionary, delta: float) -> bool:
	if not bool(enemy.get("ingressActive",false)): return false
	if enemy.has("ingressTargetPoint"):
		var target: Dictionary=ground_combat._unit(int(enemy.get("stationaryTargetId",-1)))
		var connection: Vector2=enemy.ingressTargetPoint
		if not can_enemy_engage_unit(enemy,target) or connection.distance_to(target.position)>HUNTER_RELEASE_RADIUS or not ground_combat.land_segment_safe(connection,target.position): _begin_hunter_return(enemy)
	enemy["ingressTargetClock"]=maxf(0,float(enemy.get("ingressTargetClock",0))-delta)
	if float(enemy.ingressTargetClock)<=0: _prepare_ingress_target(enemy)
	var previous: Vector2=enemy.position
	var remaining: float=float(enemy.speed)*_approach_march_factor()*1.6*delta
	var reaches_emplacement: bool=false
	while remaining>0 and int(enemy.ingressIndex)<enemy.ingressPoints.size():
		var connects_emplacement: bool=enemy.has("ingressTargetPoint") and int(enemy.ingressIndex)==int(enemy.ingressTargetIndex)
		var destination: Vector2=enemy.ingressTargetPoint if connects_emplacement else enemy.ingressPoints[int(enemy.ingressIndex)]
		var offset: Vector2=destination-enemy.position
		var step: float=minf(remaining,offset.length())
		var next: Vector2=enemy.position.move_toward(destination,step)
		if not ground_combat.land_segment_safe(enemy.position,next,.002): enemy.animation="idle";return true
		enemy.position=next
		remaining-=step
		if offset.length()<=step+.000001:
			if connects_emplacement: reaches_emplacement=true;break
			enemy.ingressIndex=int(enemy.ingressIndex)+1
		else: break
	enemy.animation="walk"
	_turn_enemy(enemy,enemy.position-previous,delta)
	_track_footstep(enemy,previous,"enemy")
	if reaches_emplacement or int(enemy.ingressIndex)>=enemy.ingressPoints.size():
		enemy.ingressActive=false
		enemy.pointIndex=int(enemy.ingressPointIndex)
		enemy.routeProgress=float(enemy.ingressJoinDistance)
		if reaches_emplacement:
			enemy["threatAnchor"]=enemy.position
			enemy["pursuitRouteDistance"]=float(enemy.ingressJoinDistance)
		if bool(enemy.get("stationaryAfterIngress",false)):
			enemy.stationaryEnemy=true
			enemy.fortification=true
			_event("fortification_settled","적 사격 진지 구축",{"side":"enemy","actorId":int(enemy.id),"kind":str(enemy.kind),"hp":float(enemy.hp),"maxHp":float(enemy.maxHp),"position":_normalized_position(enemy.position),"pathIndex":int(enemy.pathIndex)})
		if bool(enemy.get("stationaryEnemy",false)): enemy.animation="idle"
	return true

func _stage02_road_column(enemy: Dictionary) -> bool:
	return str(config.get("id",""))=="basic-farm" and not bool(enemy.get("stationaryEnemy",false)) and not bool(enemy.get("stationaryAfterIngress",false)) and not bool(enemy.get("ingressActive",false)) and not bool(enemy.get("transportActive",false)) and not bool(enemy.get("hunterReturning",false)) and not _mobile_emplacement_attacker(enemy) and not _sailing_visual(enemy)

func _enemy_lane_art_metric() -> Vector2:
	var dimensions: Dictionary=config.get("paintedComposition",{}).get("artSize",{})
	return Vector2(maxf(1.0,float(dimensions.get("width",1944))),maxf(1.0,float(dimensions.get("height",809))))

func _enemy_road_clearance(enemy: Dictionary) -> float:
	# Use the same real ground-body margin as navigation. Animation, viewport
	# shape and a lifted toe must not shrink lanes or become a movement stop.
	var metric: Vector2=_enemy_lane_art_metric()
	return maxf(.5,float(paths[int(enemy.pathIndex)].get("paintedRoadHalfWidthPixels",52.0))-.008*maxf(metric.x,metric.y))

func _enemy_road_lane_gap(enemy: Dictionary) -> float:
	var clearance: float=_enemy_road_clearance(enemy)
	var path_index: int=int(enemy.pathIndex)
	var source: Array=paths[path_index].points
	var metric: Vector2=_enemy_lane_art_metric()
	var key: String="shape:%d" % path_index
	var shape: Dictionary=enemy_lane_routes.get(key,{})
	if shape.is_empty() or shape.source!=source or shape.metric!=metric:
		var directions: Array=[]
		for index in range(source.size()-1): directions.append(((source[index+1]-source[index])*metric).normalized())
		var maximum: float=1.0
		for index in range(directions.size()-1):
			var denominator: float=1.0+(directions[index] as Vector2).dot(directions[index+1])
			if denominator>.25: maximum=maxf(maximum,((directions[index].orthogonal()+directions[index+1].orthogonal())/denominator).length())
		shape={"source":source.duplicate(),"metric":metric,"miter":maximum}
		enemy_lane_routes[key]=shape
	# An outer miter extends beyond its line offset. Include that expansion so
	# the lane's own checkpoint remains reachable inside rounded road corners.
	return minf(float(paths[path_index].get("enemyFormationLaneGapPixels",18.0)),maxf(0.0,clearance-.25)/float(shape.miter))

func enemy_road_lateral_offset(enemy: Dictionary, forward: Vector2) -> Vector2:
	var lane: float=float(enemy.get("formationLane",0))
	if str(config.get("id",""))!="basic-farm": return forward.normalized().orthogonal()*lane*ENEMY_FORMATION_LANE_GAP
	var metric: Vector2=_enemy_lane_art_metric()
	var gap: float=_enemy_road_lane_gap(enemy)
	return (forward*metric).normalized().orthogonal()*lane*gap/metric

func _enemy_lane_route(enemy: Dictionary) -> Dictionary:
	var path_index: int=int(enemy.pathIndex)
	var source: Array=paths[path_index].points
	var lane: int=int(enemy.get("formationLane",0))
	var metric: Vector2=_enemy_lane_art_metric()
	var gap: float=_enemy_road_lane_gap(enemy)
	var key: String="%d:%d" % [path_index,lane]
	var cached: Dictionary=enemy_lane_routes.get(key,{})
	if not cached.is_empty() and cached.source==source and cached.get("metric",Vector2.ZERO)==metric and float(cached.get("gap",-1.0))==gap and cached.terrain==ground_combat.structure_segment_clear and cached.water==ground_combat.water_rects and cached.obstacles==config.get("obstacles",[]): return cached
	var offset: float=float(lane)*gap
	var points: Array=[]
	var center_pixels: Array=[]
	for index in range(source.size()):
		center_pixels.append(source[index]*metric)
		var incoming: Vector2=((source[index]-source[maxi(0,index-1)])*metric).normalized()
		var outgoing: Vector2=((source[mini(index+1,source.size()-1)]-source[index])*metric).normalized()
		var lateral: Vector2=outgoing.orthogonal() if index==0 else incoming.orthogonal()
		if index>0 and index<source.size()-1:
			# The painted road is wide, not square. Intersect its parallel
			# pixel-space legs before converting the accepted lane back to world.
			var denominator: float=1.0+incoming.dot(outgoing)
			if denominator>.25: lateral=(incoming.orthogonal()+outgoing.orthogonal())/denominator
		var candidate: Vector2=source[index]+lateral*offset/metric
		if index==source.size()-1 or not ground_combat.land_segment_safe(candidate,candidate,.008): candidate=source[index]
		points.append(candidate)
	# An offset must never create a wall shortcut. Narrow only the affected
	# leg back onto its authored centerline, with a bounded neighboring pass.
	for pass_index in range(2):
		var changed: bool=false
		for index in range(points.size()-1):
			if ground_combat.land_segment_safe(points[index],points[index+1],.008): continue
			if points[index]!=source[index] or points[index+1]!=source[index+1]: changed=true
			points[index]=source[index];points[index+1]=source[index+1]
		if not changed: break
	var lengths: Array=[0.0]
	for index in range(points.size()-1): lengths.append(float(lengths[-1])+points[index].distance_to(points[index+1]))
	var result: Dictionary={"source":source.duplicate(),"points":points,"centerPixels":center_pixels,"lengths":lengths,"metric":metric,"gap":gap,"terrain":ground_combat.structure_segment_clear,"water":ground_combat.water_rects.duplicate(),"obstacles":config.get("obstacles",[]).duplicate(true)}
	enemy_lane_routes[key]=result
	return result

func _enemy_road_step_safe(enemy: Dictionary, start: Vector2, end: Vector2) -> bool:
	var route: Dictionary=_enemy_lane_route(enemy)
	var a: Vector2=start*route.metric
	var b: Vector2=end*route.metric
	var limit_squared: float=pow(_enemy_road_clearance(enemy),2)
	var start_distance: float=INF
	var end_distance: float=INF
	for index in range(route.centerPixels.size()-1):
		var first: Vector2=route.centerPixels[index]
		var second: Vector2=route.centerPixels[index+1]
		var from: float=a.distance_squared_to(Geometry2D.get_closest_point_to_segment(a,first,second))
		var to: float=b.distance_squared_to(Geometry2D.get_closest_point_to_segment(b,first,second))
		# A road-leg capsule is convex. If both endpoints fit this same capsule,
		# the entire stride fits; checking only its destination missed corners.
		if from<=limit_squared+.00000001 and to<=limit_squared+.00000001: return true
		start_distance=minf(start_distance,from)
		end_distance=minf(end_distance,to)
	# Real combat may have displaced a body. Re-enter by actual strides, never
	# snap it onto the route or immobilize it outside the walking corridor.
	return start_distance>limit_squared+.00000001 and end_distance<start_distance-.00000001

func _enemy_road_walk_step(enemy: Dictionary, desired: Vector2, budget: float) -> Vector2:
	if _enemy_road_step_safe(enemy,enemy.position,desired): return desired
	var route: Dictionary=_enemy_lane_route(enemy)
	var index: int=clampi(int(enemy.pointIndex),1,route.points.size()-1)
	var rejoin: Vector2=Geometry2D.get_closest_point_to_segment(enemy.position,route.points[index-1],route.points[index])
	for checkpoint in [rejoin,route.points[index-1],route.source[index-1]]:
		if enemy.position.distance_squared_to(checkpoint)<.000000000001: continue
		var candidate: Vector2=enemy.position.move_toward(checkpoint,budget)
		if _enemy_road_step_safe(enemy,enemy.position,candidate) and ground_combat.land_segment_safe(enemy.position,candidate,.008): return candidate
	return enemy.position

func _enemy_lane_station(enemy: Dictionary) -> float:
	var route: Dictionary=_enemy_lane_route(enemy)
	var points: Array=route.points
	var segment: int=clampi(int(enemy.pointIndex)-1,0,points.size()-2)
	var leg: Vector2=points[segment+1]-points[segment]
	var distance: float=(enemy.position-points[segment]).dot(leg.normalized())
	# Preserve signed real rear-rank positions before the offscreen entrance.
	if segment==0 and distance<0.0: return distance
	return float(route.lengths[segment])+clampf(distance,0.0,leg.length())

func _enemy_lane_waypoint_passed(enemy: Dictionary, target: Vector2) -> bool:
	var route: Dictionary=_enemy_lane_route(enemy)
	var index: int=int(enemy.pointIndex)
	if index<1 or index>=route.points.size()-1: return false
	var incoming: Vector2=target-route.points[index-1]
	# Pass only within one source pixel and only when the whole connector to
	# the next checkpoint fits. A broad plane skip cut across curved road edges.
	return incoming.length_squared()>.00000001 and (enemy.position-target).dot(incoming)>=0.0 and ((enemy.position-target)*route.metric).length_squared()<=1.0 and _enemy_road_step_safe(enemy,enemy.position,route.points[index+1])

func _enemy_lane_point(enemy: Dictionary, point_index: int) -> Vector2:
	if _stage02_road_column(enemy):
		var route: Dictionary=_enemy_lane_route(enemy)
		return route.points[clampi(point_index,0,route.points.size()-1)]
	var points: Array=paths[int(enemy.pathIndex)].points
	var index: int=clampi(point_index,0,points.size()-1)
	var direction: Vector2=points[mini(index+1,points.size()-1)]-points[maxi(0,index-1)]
	var offset: float=float(enemy.get("formationLane",0))*ENEMY_FORMATION_LANE_GAP
	var candidate: Vector2=points[index]+direction.normalized().orthogonal()*offset
	if not _sailing_visual(enemy) and not ground_combat.land_segment_safe(candidate,candidate,0): return points[index]
	return candidate

func _mobile_emplacement_attacker(enemy: Dictionary) -> bool:
	return str(enemy.get("combatRole",""))==ENEMY_EMPLACEMENT_ROLE and not bool(enemy.get("roadRanged",false)) and not bool(enemy.get("stationaryEnemy",false)) and not bool(enemy.get("fortification",false)) and not bool(enemy.get("stationaryAfterIngress",false))

func _emplacement_firing_bounds(kind: String) -> Rect2:
	if emplacement_body_bounds.has(kind): return emplacement_body_bounds[kind]
	var bounds: Rect2=Rect2()
	var first: bool=true
	for direction in ["ne","se","sw","nw"]:
		for state in ["idle","aim","attack","recover"]:
			var animation: Dictionary=painted_actors._animation(kind,false,direction,state)
			for pose in animation.get("frames",[]):
				var relative: Rect2=Rect2((-pose.anchor+pose.offset)/pose.body_height,pose.region.size/pose.body_height)
				bounds=relative if first else bounds.merge(relative)
				first=false
	if first: bounds=Rect2(-.4,-1.1,.8,1.2)
	emplacement_body_bounds[kind]=bounds
	return bounds

func _emplacement_body_clear(enemy: Dictionary, point: Vector2) -> bool:
	var actual_position: bool=point==enemy.position
	var cached: Dictionary=enemy.get("emplacementRoadClearCache",{})
	if actual_position and int(cached.get("generation",-1))==battle_generation and str(cached.get("kind",""))==str(enemy.kind) and cached.get("position",Vector2(INF,INF))==point and cached.get("fieldSize",Vector2.ZERO)==field_rect.size and bool(cached.get("mirrored",not presentation_mirrored))==presentation_mirrored:
		return bool(cached.get("clear",false))
	var height: float=painted_actors.body_height_screen*clampf(field_rect.size.y/620.0,.65,1.5)
	var pose: Rect2=_emplacement_firing_bounds(str(enemy.kind))
	var foot: Vector2=_screen(point)+painted_actors.actor_visual_offset(enemy,height)
	var screen_bounds: Rect2=Rect2(foot+pose.position*height,pose.size*height)
	var canonical: Rect2=Rect2(point,Vector2.ZERO)
	for corner in [screen_bounds.position,Vector2(screen_bounds.end.x,screen_bounds.position.y),screen_bounds.end,Vector2(screen_bounds.position.x,screen_bounds.end.y)]:
		var position: Vector2=screen_to_field_point(get_global_transform_with_canvas()*corner)
		if not position.is_finite(): return false
		canonical=canonical.expand(position)
	var clear: bool=ground_combat.road_body_clear(canonical.grow(.008))
	if actual_position: enemy["emplacementRoadClearCache"]={"generation":battle_generation,"kind":str(enemy.kind),"position":point,"fieldSize":field_rect.size,"mirrored":presentation_mirrored,"clear":clear}
	return clear

func emplacement_release_allowed(enemy: Dictionary, target: Dictionary) -> bool:
	# This is a raid-position rule, not a prohibition on ordinary road troops
	# or the separately authored stationary fortification/Ninja contract.
	if not _mobile_emplacement_attacker(enemy): return true
	if str(enemy.kind) not in ["enemy_archer","enemy_gunner"] and str(target.get("type","")) not in ["archer","gunner"]: return true
	return _emplacement_body_clear(enemy,enemy.position)

func _emplacement_range(enemy: Dictionary) -> float:
	return float(enemy.get("attackRange",enemy.get("meleeRange",.032)))

func _emplacement_goal_legal(enemy: Dictionary, target: Dictionary, origin: Vector2, point: Vector2) -> bool:
	if not point.is_finite() or not Rect2(.008,.008,.984,.984).has_point(point): return false
	if point.distance_to(target.position)>_emplacement_range(enemy)*.96 or not _emplacement_body_clear(enemy,point): return false
	return ground_combat.land_segment_safe(point,point,.008) and ground_combat.land_segment_safe(origin,point,.008) and ground_combat.land_segment_safe(point,target.position,.008) and ground_combat.land_segment_safe(enemy.get("threatAnchor",origin),point,.008)

func _find_emplacement_goal(enemy: Dictionary, target: Dictionary, origin: Vector2) -> Vector2:
	if target.is_empty(): return Vector2(INF,INF)
	var nearest: Vector2=origin
	var separation: float=INF
	for path in paths:
		for segment in range(path.points.size()-1):
			var projected: Vector2=Geometry2D.get_closest_point_to_segment(target.position,path.points[segment],path.points[segment+1])
			var distance: float=projected.distance_squared_to(target.position)
			if distance<separation: separation=distance;nearest=projected
	var outward: Vector2=(target.position-nearest).normalized()
	if outward.length_squared()<.5: outward=(target.position-origin).normalized()
	if outward.length_squared()<.5: outward=Vector2.UP
	var best: Vector2=Vector2(INF,INF)
	var score: float=INF
	for factor in [.84,.64,.40]:
		for index in range(16):
			var direction: Vector2=outward.rotated(float(index)*TAU/16.0)
			var candidate: Vector2=target.position+direction*_emplacement_range(enemy)*float(factor)
			if int(enemy.get("emplacementRejectedTargetId",-1))==int(target.id) and (enemy.get("emplacementRejectedGoal",Vector2(INF,INF)) as Vector2).distance_squared_to(candidate)<.014*.014: continue
			var cost: float=origin.distance_to(candidate)+maxf(0.0,-direction.dot(outward))*.014
			if cost>=score-.000001 or not _emplacement_goal_legal(enemy,target,origin,candidate): continue
			best=candidate;score=cost
	return best

func _emplacement_goal(enemy: Dictionary, target: Dictionary, origin: Vector2) -> Vector2:
	var retained: Vector2=enemy.get("emplacementGoalPosition",Vector2(INF,INF))
	if int(enemy.get("emplacementGoalTargetId",-1))==int(target.id) and _emplacement_goal_legal(enemy,target,origin,retained): return retained
	if int(enemy.get("emplacementGoalTargetId",-1))==int(target.id) and float(enemy.get("emplacementGoalRetryAt",0.0))>elapsed: return Vector2(INF,INF)
	var point: Vector2=_find_emplacement_goal(enemy,target,origin)
	enemy["emplacementGoalTargetId"]=int(target.id)
	if point.is_finite():
		enemy["emplacementGoalPosition"]=point
		enemy.erase("emplacementGoalRetryAt")
	else:
		enemy.erase("emplacementGoalPosition")
		enemy["emplacementGoalRetryAt"]=elapsed+.35
	return point

func _emplacement_approach(enemy: Dictionary, target: Dictionary, delta: float) -> bool:
	if not _mobile_emplacement_attacker(enemy): return false
	if enemy.position.distance_to(target.position)<=_emplacement_range(enemy)*.96 and ground_combat.land_segment_safe(enemy.position,target.position,.008) and _emplacement_body_clear(enemy,enemy.position):
		enemy["emplacementBlockedClock"]=0.0
		return false
	var goal: Vector2=_emplacement_goal(enemy,target,enemy.position)
	var previous: Vector2=enemy.position
	if goal.is_finite(): _enemy_threat_walk(enemy,goal,delta)
	if enemy.position.distance_squared_to(previous)>.000000000001:
		enemy["emplacementBlockedClock"]=0.0
	else:
		enemy["animation"]="idle"
		if goal.is_finite():
			enemy["emplacementRejectedTargetId"]=int(target.id)
			enemy["emplacementRejectedGoal"]=goal
			enemy.erase("emplacementGoalPosition")
			enemy["emplacementGoalRetryAt"]=elapsed+.15
		enemy["emplacementBlockedClock"]=float(enemy.get("emplacementBlockedClock",0.0))+delta
		if float(enemy.emplacementBlockedClock)>=HUNTER_LOST_GRACE: _begin_hunter_return(enemy)
	return true

func _enemy_ranged_step(enemy: Dictionary, delta: float) -> bool:
	if str(enemy.kind) not in ["enemy_archer","enemy_gunner"]: return false
	var plan: Dictionary=enemy.get("rangedPlan",{})
	enemy["attackCooldown"]=maxf(0,float(enemy.get("attackCooldown",0))-delta)
	if float(enemy.get("skillAttackDelayUntil",0.0))>elapsed and (not plan.is_empty() or str(enemy.get("animation","idle"))=="attack"): return true
	var target: Dictionary=_hunter_target(enemy,delta)
	if not plan.is_empty() and (target.is_empty() or int(plan.targetId)!=int(target.id) or not _enemy_ranged_target_valid(enemy,target)):
		enemy["rangedPlan"]={}
		plan={}
		enemy["animation"]="idle" if bool(enemy.get("stationaryEnemy",false)) else "walk"
	if not plan.is_empty():
		_aim_enemy_attack(enemy,target,delta)
		if float(enemy.animationClock)>=float(plan.releaseTime):
			if _enemy_ranged_target_valid(enemy,target):
				projectiles.append({"position":enemy.position,"targetId":int(target.id),"targetPos":target.position,"damage":float(plan.damage),"type":str(enemy.kind),"victimSide":"friendly","sourceId":int(enemy.id),"sourcePosition":enemy.position,"sourceActor":{"id":int(enemy.id),"kind":str(enemy.kind),"combatRole":str(enemy.combatRole),"roadRanged":bool(enemy.get("roadRanged",false)),"position":enemy.position,"pathIndex":int(enemy.pathIndex),"pointIndex":int(enemy.pointIndex),"sailing":_sailing_visual(enemy)},"speed":.65 if str(enemy.kind)=="enemy_archer" else 2.7,"age":0.0})
				_combat_event("shot",enemy,target)
			enemy["rangedPlan"]={}
		if float(enemy.animationClock)<.5: return true
	if str(enemy.get("animation","idle"))=="attack" and float(enemy.animationClock)<.5:
		var recovering: Dictionary=enemy_facing_target(enemy)
		if not recovering.is_empty():
			_aim_enemy_attack(enemy,recovering,delta)
			return true
		enemy["animation"]="idle" if bool(enemy.get("stationaryEnemy",false)) else "walk"
	if target.is_empty():
		if bool(enemy.get("stationaryEnemy",false)): enemy.animation="idle";return true
		return bool(enemy.get("hunterReturning",false))
	if _emplacement_approach(enemy,target,delta): return true
	if enemy.position.distance_to(target.position)>float(enemy.attackRange):
		if not bool(enemy.get("stationaryEnemy",false)):
			var destination: Vector2=target.position+(enemy.position-target.position).normalized()*float(enemy.attackRange)*.85
			_enemy_threat_walk(enemy,destination,delta)
		else: enemy.animation="idle"
		return true
	if float(enemy.get("skillAttackDelayUntil",0.0))>elapsed: return true
	_turn_enemy(enemy,target.position-enemy.position,delta)
	if float(enemy.attackCooldown)<=0:
		if not _enemy_ranged_target_valid(enemy,target): return true
		enemy["animation"]="attack"
		enemy["animationClock"]=0.0
		enemy["attackCooldown"]=float(enemy.attackInterval)
		enemy["rangedPlan"]={"targetId":int(target.id),"releaseTime":.25,"damage":(4.0+float(enemy.get("counterWave",wave))*.6)*float(enemy.damage)}
		enemy["attackFacingTargetId"]=int(target.id)
		enemy["attackFacingIsRanged"]=true
		_aim_enemy_attack(enemy,target,delta)
	else: enemy["animation"]="idle"
	return true

func _enemy_ranged_target_valid(enemy: Dictionary, target: Dictionary) -> bool:
	return not target.is_empty() and can_enemy_engage_unit(enemy,target) and emplacement_release_allowed(enemy,target) and enemy.position.distance_to(target.position)<=float(enemy.get("attackRange",0.0)) and ground_combat.land_segment_safe(enemy.position,target.position)

func enemy_facing_target(enemy: Dictionary) -> Dictionary:
	# Read-only gameplay ownership for the sprite's idle/attack facing. It
	# must not independently replace a valid hunter target with a nearer ally.
	if enemy.is_empty() or bool(enemy.get("hunterReturning",false)) or bool(enemy.get("transportActive",false)) or bool(enemy.get("ingressActive",false)): return {}
	var counter: Dictionary=enemy.get("counterPlan",{})
	var ranged: Dictionary=enemy.get("rangedPlan",{})
	var target: Dictionary={}
	if not counter.is_empty():
		target=ground_combat._unit(int(counter.targetId))
		return target if ground_combat._counter_target_valid(enemy,target) else {}
	if not ranged.is_empty():
		target=ground_combat._unit(int(ranged.targetId))
		return target if _enemy_ranged_target_valid(enemy,target) else {}
	if str(enemy.get("animation",""))=="attack" and float(enemy.get("animationClock",0.0))<.5:
		target=ground_combat._unit(int(enemy.get("attackFacingTargetId",-1)))
		var valid: bool=_enemy_ranged_target_valid(enemy,target) if bool(enemy.get("attackFacingIsRanged",false)) else ground_combat._counter_target_valid(enemy,target)
		return target if valid else {}
	target=ground_combat._unit(int(enemy.get("stationaryTargetId",-1)))
	return target if _enemy_ranged_target_valid(enemy,target) else {}

func _aim_enemy_attack(enemy: Dictionary, target: Dictionary, delta: float) -> void:
	if target.is_empty(): return
	var direction: Vector2=target.position-enemy.position
	if str(enemy.get("kind","")) in ["enemy_archer","enemy_gunner"]:
		if direction.length_squared()>.00000001: enemy["aim"]=direction.normalized()
	else: _turn_enemy(enemy,direction,delta)

func _turn_enemy(enemy: Dictionary, direction: Vector2, delta: float) -> void:
	if direction.length_squared()<.00000001: return
	var desired: Vector2=direction.normalized()
	var previous: Vector2=enemy.get("aim",desired)
	if previous.length_squared()<.00000001: enemy.aim=desired;return
	var angle: float=previous.angle()+clampf(previous.angle_to(desired),-8.0*delta,8.0*delta)
	enemy.aim=Vector2.from_angle(angle)

func _road_ranged_post_target_valid(enemy: Dictionary, unit: Dictionary) -> bool:
	if not _friendly_emplacement_troop(unit) or not can_enemy_engage_unit(enemy,unit): return false
	var radius: float=float(enemy.get("attackRange",0.0))
	return enemy.position.distance_squared_to(unit.position)<=radius*radius and ground_combat.land_segment_safe(enemy.position,unit.position)

func _road_ranged_target(enemy: Dictionary, delta: float) -> Dictionary:
	# The road soldier stops only when a real emplacement troop is in range.
	# Never pursue the post across grass or turn a lost target into a side raid.
	var target: Dictionary=ground_combat._unit(int(enemy.get("stationaryTargetId",-1)))
	if _road_ranged_post_target_valid(enemy,target): return target
	enemy["stationaryTargetId"]=-1
	enemy["stationThreatClock"]=maxf(0.0,float(enemy.get("stationThreatClock",0.0))-delta)
	if float(enemy.stationThreatClock)>0.0: return {}
	enemy["stationThreatClock"]=.35
	ground_combat._ensure_crowd_index()
	var nearest: float=INF
	for candidate in ground_combat.crowd.nearby(enemy.position,maxf(0.0,float(enemy.attackRange)),true):
		if not _road_ranged_post_target_valid(enemy,candidate): continue
		var distance: float=enemy.position.distance_squared_to(candidate.position)
		if distance<nearest or (is_equal_approx(distance,nearest) and (target.is_empty() or int(candidate.id)<int(target.id))):
			target=candidate
			nearest=distance
	if not target.is_empty() and _road_ranged_post_target_valid(enemy,target):
		enemy["stationaryTargetId"]=int(target.id)
		return target
	return {}

func _hunter_target(enemy: Dictionary, delta: float) -> Dictionary:
	if bool(enemy.get("roadRanged",false)): return _road_ranged_target(enemy,delta)
	if bool(enemy.get("transportActive",false)) or str(enemy.combatRole)!=ENEMY_EMPLACEMENT_ROLE or bool(enemy.get("hunterReturning",false)): return {}
	var target: Dictionary=ground_combat._unit(int(enemy.get("stationaryTargetId",-1)))
	if not target.is_empty() and can_enemy_engage_unit(enemy,target):
		var anchor: Vector2=enemy.get("threatAnchor",enemy.position)
		var stationary: bool=bool(enemy.get("stationaryEnemy",false))
		var leash: float=float(enemy.get("attackRange",HUNTER_ACQUIRE_RADIUS))*1.35 if stationary else HUNTER_RELEASE_RADIUS
		var reachable: bool=anchor.distance_to(target.position)<=leash and ground_combat.land_segment_safe(enemy.position,target.position) and ground_combat.land_segment_safe(anchor,target.position)
		if _mobile_emplacement_attacker(enemy): reachable=anchor.distance_to(target.position)<=leash and _emplacement_goal(enemy,target,enemy.position).is_finite()
		enemy["targetLostClock"]=0.0 if reachable else float(enemy.get("targetLostClock",0.0))+delta
		if float(enemy.targetLostClock)<HUNTER_LOST_GRACE: return target
	if not target.is_empty() or enemy.has("threatAnchor"):
		_begin_hunter_return(enemy)
		return {}
	enemy["stationThreatClock"]=maxf(0,float(enemy.get("stationThreatClock",0))-delta)
	if float(enemy.stationThreatClock)>0: return {}
	enemy.stationThreatClock=.35
	var best: Dictionary={}
	var best_goal: Vector2=Vector2(INF,INF)
	var best_priority: int=10
	var acquire_radius: float=float(enemy.get("attackRange",HUNTER_ACQUIRE_RADIUS)) if bool(enemy.get("stationaryEnemy",false)) else HUNTER_ACQUIRE_RADIUS
	var closest: float=acquire_radius
	var assigned_zone: String=str(enemy.get("assaultZoneId",""))
	if not assigned_zone.is_empty() and not bool(enemy.get("stationaryEnemy",false)):
		for zone in zones:
			if str(zone.get("id",""))!=assigned_zone: continue
			var path_index: int=int(enemy.pathIndex)
			var projected: float=ground_combat.point_distance(path_index,maxi(0,int(enemy.pointIndex)-1),zone.position)
			var road_point: Vector2=ground_combat.route_point(path_index,projected)
			if ground_combat.land_segment_safe(road_point,zone.position,.008): acquire_radius=maxf(acquire_radius,road_point.distance_to(zone.position)+float(zone.get("r",.024))+.018)
			break
	for unit in units:
		if not can_enemy_engage_unit(enemy,unit): continue
		if not assigned_zone.is_empty() and str(unit.type) in ["archer","gunner","monk","naginata"] and str(unit.get("deploymentZoneId",""))!=assigned_zone: continue
		var distance: float=enemy.position.distance_to(unit.position)
		var priority: int=0 if str(unit.type) in ["archer","gunner","monk","naginata"] else 1
		if distance<=acquire_radius and (priority<best_priority or (priority==best_priority and distance<closest)):
			var goal: Vector2=_find_emplacement_goal(enemy,unit,enemy.position) if _mobile_emplacement_attacker(enemy) else unit.position
			if not goal.is_finite() or (not _mobile_emplacement_attacker(enemy) and not ground_combat.land_segment_safe(enemy.position,unit.position)): continue
			best=unit;closest=distance;best_priority=priority
			best_goal=goal
	if not best.is_empty():
		enemy["stationaryTargetId"]=int(best.id)
		enemy["threatAnchor"]=enemy.position
		enemy["pursuitRouteDistance"]=ground_combat.enemy_distance(enemy)
		enemy["targetCommitTime"]=elapsed
		enemy["targetLostClock"]=0.0
		if _mobile_emplacement_attacker(enemy):
			enemy["emplacementGoalTargetId"]=int(best.id)
			enemy["emplacementGoalPosition"]=best_goal
		ground_combat.cancel_counterattack(enemy)
	return best

func _begin_hunter_return(enemy: Dictionary) -> void:
	if bool(enemy.get("roadRanged",false)):
		enemy["stationaryTargetId"]=-1
		enemy["rangedPlan"]={}
		enemy["stationThreatClock"]=0.0
		ground_combat.cancel_counterattack(enemy)
		return
	enemy.erase("emplacementGoalTargetId")
	enemy.erase("emplacementGoalPosition")
	enemy.erase("emplacementGoalRetryAt")
	enemy.erase("emplacementRejectedTargetId")
	enemy.erase("emplacementRejectedGoal")
	enemy.erase("emplacementBlockedClock")
	enemy["stationaryTargetId"]=-1
	ground_combat.cancel_counterattack(enemy)
	enemy["rangedPlan"]={}
	enemy["stationThreatClock"]=.35
	if bool(enemy.get("ingressActive",false)):
		# An unbuilt, removed or newly protected target cannot interrupt the
		# remaining authored ingress or make a soldier return before arriving.
		enemy.erase("ingressTargetPoint")
		enemy.erase("ingressTargetIndex")
		enemy["ingressTargetClock"]=.35
		return
	if bool(enemy.get("stationaryEnemy",false)):
		enemy.erase("threatAnchor")
		return
	if enemy.has("ingressTargetPoint"):
		# Retrace only the safe final approach, then walk the unused corridor
		# forward. A straight return to the main road can cross its obstacles.
		var return_points: Array=[enemy.get("threatAnchor",enemy.ingressTargetPoint)]
		return_points.append_array(enemy.ingressPoints.slice(int(enemy.ingressTargetIndex)))
		enemy["hunterReturnPoints"]=return_points
		enemy["hunterReturnIndex"]=0
		enemy["hunterReturning"]=true
		enemy["resumeDistance"]=float(enemy.ingressJoinDistance)
		enemy["resumePoint"]=enemy.ingressPoints[-1]
		return
	var lower: float=maxf(0,float(enemy.get("pursuitRouteDistance",ground_combat.enemy_distance(enemy))))
	var best_distance: float=lower
	var best_point: Vector2=ground_combat.route_point(int(enemy.pathIndex),lower)
	var closest: float=INF
	for segment in range(paths[int(enemy.pathIndex)].points.size()-1):
		if float(ground_combat.cumulative[int(enemy.pathIndex)][segment+1])<lower: continue
		var distance: float=maxf(lower,ground_combat.point_distance(int(enemy.pathIndex),segment,enemy.position))
		var point: Vector2=ground_combat.route_point(int(enemy.pathIndex),distance)
		if ground_combat.land_segment_safe(enemy.position,point) and enemy.position.distance_to(point)<closest:
			closest=enemy.position.distance_to(point);best_distance=distance;best_point=point
	enemy["hunterReturning"]=true
	enemy["resumeDistance"]=best_distance
	enemy["resumePoint"]=best_point

func _hunter_return_step(enemy: Dictionary, delta: float) -> bool:
	if not bool(enemy.get("hunterReturning",false)): return false
	var destination: Vector2=enemy.resumePoint
	if enemy.has("hunterReturnPoints"):
		var points: Array=enemy.hunterReturnPoints
		destination=points[int(enemy.hunterReturnIndex)]
		if not _enemy_threat_walk(enemy,destination,delta,.002): return true
		enemy.hunterReturnIndex=int(enemy.hunterReturnIndex)+1
		if int(enemy.hunterReturnIndex)<points.size(): return true
	elif not _enemy_threat_walk(enemy,destination,delta): return true
	if enemy.position.distance_squared_to(enemy.resumePoint)<.00000001:
		enemy.position=enemy.resumePoint
		var point_index: int=1
		for index in range(1,ground_combat.cumulative[int(enemy.pathIndex)].size()):
			point_index=index
			if float(ground_combat.cumulative[int(enemy.pathIndex)][index])>=float(enemy.resumeDistance): break
		enemy.pointIndex=point_index
		enemy["routeProgress"]=maxf(float(enemy.get("routeProgress",0)),float(enemy.resumeDistance))
		enemy.hunterReturning=false
		enemy.erase("threatAnchor")
		enemy.erase("ingressTargetPoint")
		enemy.erase("ingressTargetIndex")
		enemy.erase("hunterReturnPoints")
		enemy.erase("hunterReturnIndex")
	return true

func _enemy_threat_walk(enemy: Dictionary, destination: Vector2, delta: float, margin: float = .008, contact: bool = false) -> bool:
	var previous: Vector2=enemy.position
	var multiplier: float=ENGAGED_MARCH_FACTOR
	if contact:
		if float(enemy.get("slowClock",0.0))>0.0: multiplier*=float(enemy.get("slowFactor",.75))
		for aura in _read_active_auras():
			if bool(aura.active) and enemy.position.distance_to(_point(aura))<=float(aura.get("r",.1)): multiplier*=float(aura.get("enemySpeedFactor",1.0))
		if str(config.get("theme",""))=="harbor" and int(enemy.pointIndex)<=int(config.get("landingIndex",2)): multiplier*=1.6
		if storm_active:
			multiplier*=.62
			var storm_zone: Dictionary=config.get("stormZone",{})
			if not storm_zone.is_empty() and enemy.position.distance_to(_point(storm_zone))<float(storm_zone.get("r",.11)): multiplier=0.0
	var next: Vector2=previous.move_toward(destination,float(enemy.speed)*multiplier*delta)
	var target: Dictionary=ground_combat._unit(int(enemy.get("meleeApproachTargetId",-1))) if contact else {}
	var legal: Callable=func(a: Vector2,b: Vector2) -> bool:
		if not ground_combat.land_segment_safe(a,b,margin) or (not bool(enemy.get("hunterReturning",false)) and not ground_combat.land_segment_safe(b,enemy.get("threatAnchor",a))): return false
		if contact:
			if target.is_empty() or float(target.get("hp",0.0))<=0.0 or b.distance_to(target.position)>GroundCombat.MELEE_ENCOUNTER_RADIUS: return false
			var body_gap: float=maxf(float(target.get("occupancyRadius",.008)),.007)+.007
			if target.position.distance_to(Geometry2D.get_closest_point_to_segment(target.position,a,b))<body_gap: return false
		return true
	if contact: next=ground_combat.crowd.move_point(enemy,next,false,legal,destination,true)
	if not bool(legal.call(previous,next)): return false
	enemy.position=next
	if next.distance_squared_to(previous)>.000000001:
		_turn_enemy(enemy,next-previous,delta)
		if str(enemy.animation)!="walk": enemy.animation="walk";enemy.animationClock=0.0
		_track_footstep(enemy,previous,"enemy")
	else: enemy.animation="idle"
	return next.distance_squared_to(destination)<.00000001

func _enemy_stationary_threat(enemy: Dictionary, delta: float) -> bool:
	var role: String=str(enemy.combatRole) if enemy.has("combatRole") else str(enemy_role_contract(str(enemy.kind)).combatRole)
	if role!=ENEMY_EMPLACEMENT_ROLE: return false
	if str(enemy.kind) in ["enemy_archer","enemy_gunner"] or bool(enemy.get("stationaryEnemy",false)) or _sailing_visual(enemy): return false
	var target: Dictionary=_hunter_target(enemy,delta)
	if target.is_empty(): return bool(enemy.get("hunterReturning",false))
	if _emplacement_approach(enemy,target,delta): return true
	var distance: float=enemy.position.distance_to(target.position)
	if distance>.032:
		ground_combat.cancel_counterattack(enemy)
		var desired: Vector2=target.position+(enemy.position-target.position).normalized()*.026
		_enemy_threat_walk(enemy,desired,delta)
	else: ground_combat.counterattack(enemy,delta,target)
	return true

func _enemy_transport_step(enemy: Dictionary, delta: float) -> bool:
	if not bool(enemy.get("transportActive",false)): return false
	var points: Array = enemy.get("transportPoints",[])
	var previous: Vector2 = enemy.position
	var remaining: float = float(enemy.speed)*_approach_march_factor()*1.6*delta
	while remaining>0 and int(enemy.transportIndex)<points.size():
		var destination: Vector2 = points[int(enemy.transportIndex)]
		var distance: float = enemy.position.distance_to(destination)
		var step: float = minf(remaining,distance)
		enemy.position = enemy.position.move_toward(destination,step)
		remaining -= step
		if distance<=step+.000001: enemy.transportIndex=int(enemy.transportIndex)+1
		else: break
	_turn_enemy(enemy,enemy.position-previous,delta)
	enemy.animation = "idle"
	enemy["blockedBy"] = -1
	ground_combat.cancel_counterattack(enemy)
	enemy["rangedPlan"] = {}
	if int(enemy.transportIndex)>=points.size():
		enemy.position = points[-1]
		enemy.transportActive = false
		enemy["ingressTargetClock"] = 0.0
	return true

func _enemy_group_members(enemy: Dictionary) -> Array:
	var context: Dictionary=unit_skills.membership_query_context()
	if context.is_empty(): return enemies
	# Reuse the current batch's authoritative membership index. Callbacks,
	# roster replacement and generation changes already invalidate it.
	if not is_same(_enemy(int(enemy.id)),enemy): return []
	var index: Dictionary=context.enemyLookup
	if not bool(index.get("cohortsReady",false)):
		var cohorts: Dictionary={}
		for member in enemies:
			var group: String=str(member.get("formationGroup",""))
			if group.is_empty(): continue
			var group_key: String="%d:%s" % [int(member.pathIndex),group]
			if not cohorts.has(group_key): cohorts[group_key]=[]
			cohorts[group_key].append(member)
		index["cohorts"]=cohorts
		index["cohortsReady"]=true
	var key: String="%d:%s" % [int(enemy.pathIndex),str(enemy.get("formationGroup",""))]
	return index.cohorts.get(key,[])

func _enemy_formation_columns(pattern: String) -> int:
	var columns: int=3 if pattern=="formation" else 5 if pattern=="rush" else 2
	return mini(columns,_enemy_approach_cohort_size()) if str(config.get("id",""))=="basic-farm" else columns

func _enemy_formation_lane(member: int, columns: int) -> int:
	return member%3-1 if columns==3 else member%5-2 if columns==5 else (-1 if member%2==0 else 1)

func _queued_enemy_approach_key(options: Dictionary) -> String:
	var group: String=str(options.get("formationGroup",""))
	var path_index: int=int(options.get("pathIndex",-1))
	if group.is_empty() or path_index<0 or path_index>=paths.size() or bool(options.get("fortification",false)) or options.has("ambushEntry"): return ""
	if str(options.get("formationPattern","")) not in ["skirmish","formation","mounted_vanguard","rush","coordinated_assault"]: return ""
	return "%d:%s" % [path_index,group]

func _prepare_enemy_approach_birth(enemy: Dictionary) -> void:
	# Only the ordinary land column uses these slots. Authored boats, side
	# routes and fortification crews retain their own entry and landing path.
	if bool(enemy.get("stationaryEnemy",false)) or bool(enemy.get("stationaryAfterIngress",false)) or bool(enemy.get("ingressActive",false)) or bool(enemy.get("transportActive",false)) or _sailing_visual(enemy): return
	var key: String=_queued_enemy_approach_key(enemy)
	if key.is_empty(): return
	var state: Dictionary=enemy_approach_states.get(key,{"assembled":false,"released":false})
	enemy_approach_states[key]=state
	enemy["approachCohortKey"]=key
	enemy["approachCohortGeneration"]=battle_generation
	var points: Array=paths[int(enemy.pathIndex)].points
	if _stage02_road_column(enemy): points=_enemy_lane_route(enemy).points
	var base: Vector2=enemy.position
	var direction: Vector2=points[1]-points[0] if points.size()>1 else Vector2.ZERO
	var rear: Vector2=base-direction.normalized()*maxi(0,int(enemy.get("formationRank",0)))*ENEMY_FORMATION_ROW_GAP
	# Extend backwards only at birth, entirely outside the map and along a
	# safe first leg. Unsupported entries keep their real original position;
	# the whole cohort is then free, rather than pretending a rear slot exists.
	if direction.length_squared()<.00000001 or Rect2(0,0,1,1).has_point(base) or Rect2(0,0,1,1).has_point(rear) or not ground_combat.land_segment_safe(base,rear,.002):
		state.assembled=true;state.released=true
		return
	enemy.position=rear

func _enemy_approach_progress(enemy: Dictionary) -> float:
	if _stage02_road_column(enemy): return _enemy_lane_station(enemy)
	# Ordinary route projection clamps at its first endpoint. Formation alone
	# also needs the signed distance of a real rear rank behind that endpoint.
	var points: Array=paths[int(enemy.pathIndex)].points
	if int(enemy.pointIndex)<=1 and points.size()>1:
		var direction: Vector2=(points[1]-points[0]).normalized()
		var distance: float=(enemy.position-points[0]).dot(direction)
		if distance<0.0: return distance
	return ground_combat.enemy_distance(enemy)

func _release_enemy_approach(enemy: Dictionary) -> void:
	# A combat callback can load another battle before its controller returns.
	# Reused actor IDs/cohort names must never release that new battle's group.
	if int(enemy.get("approachCohortGeneration",-1))!=battle_generation or not is_same(_enemy(int(enemy.get("id",-1))),enemy): return
	var key: String=str(enemy.get("approachCohortKey",""))
	if enemy_approach_states.has(key):
		var state: Dictionary=enemy_approach_states[key]
		state.assembled=true;state.released=true

func _prepare_enemy_approach_step(delta: float) -> void:
	# One queue pass and one roster pass per authoritative step. All members
	# use this same pre-movement snapshot, independent of their update order.
	var pending: Dictionary={}
	if spawn_metadata.size()==spawn_queue.size():
		for options in spawn_metadata:
			var key: String=_queued_enemy_approach_key(options)
			if key.is_empty(): continue
			if not pending.has(key): pending[key]=[]
			pending[key].append(options)
	var groups: Dictionary={}
	var retained_states: Dictionary={}
	for enemy in enemies:
		var key: String=str(enemy.get("approachCohortKey",""))
		if key.is_empty() or float(enemy.get("hp",0.0))<=0.0 or bool(enemy.get("escaped",false)): continue
		var state: Dictionary=enemy_approach_states.get(key,{"assembled":true,"released":true})
		retained_states[key]=state
		if not groups.has(key): groups[key]={"state":state,"members":[],"hold":false,"front":INF,"pace":INF}
		groups[key].members.append(enemy)
	for key in pending:
		if enemy_approach_states.has(key): retained_states[key]=enemy_approach_states[key]
	enemy_approach_states=retained_states
	var multipliers: Dictionary={}
	var path_march_limits: Dictionary={}
	ground_combat._ensure_crowd_index()
	for key in groups:
		var group: Dictionary=groups[key]
		var state: Dictionary=group.state
		if bool(state.released): continue
		if not bool(state.assembled):
			var waiting: Array=pending.get(key,[])
			if waiting.is_empty(): state.assembled=true
		for enemy in group.members:
			if bool(state.released): break
			# A forced stop belongs to that soldier, not an invisible stop order
			# for the entire approaching column. Never reassemble it afterward.
			if _stage02_road_column(enemy) and float(enemy.get("skillMoveStopUntil",0.0))>elapsed:
				_release_enemy_approach(enemy);break
			if str(enemy.get("formationPattern","")) not in ["skirmish","formation","mounted_vanguard","rush","coordinated_assault"] or bool(enemy.get("stationaryEnemy",false)) or bool(enemy.get("ingressActive",false)) or bool(enemy.get("transportActive",false)) or bool(enemy.get("hunterReturning",false)) or _sailing_visual(enemy):
				_release_enemy_approach(enemy);break
			if not bool(state.assembled) and Rect2(0,0,1,1).has_point(enemy.position):
				_release_enemy_approach(enemy);break
			if not enemy.get("counterPlan",{}).is_empty() or not enemy.get("rangedPlan",{}).is_empty() or int(enemy.get("blockedBy",-1))>=0 or bool(enemy.get("meleeApproachActive",false)):
				_release_enemy_approach(enemy);break
			for ally in ground_combat.crowd.nearby(enemy.position,.12,true):
				if can_enemy_engage_unit(enemy,ally,true) and ground_combat.land_segment_safe(enemy.position,ally.position,0.0):
					_release_enemy_approach(enemy);break
		if bool(state.released): continue
		group.hold=not bool(state.assembled)
		if bool(group.hold): continue
		for enemy in group.members:
			if str(enemy.get("kind",""))=="enemy_cavalry" or float(enemy.speed)<=0.0: continue
			var path_index: int=int(enemy.pathIndex)
			path_march_limits[path_index]=minf(float(path_march_limits.get(path_index,INF)),float(enemy.speed))
	# Infantry on the same route share an approach ceiling across cohorts.
	# Assembly waits and temporary stuns never enter this raw-speed ceiling;
	# each group's existing terrain/status multiplier still limits its stride.
	for group in groups.values():
		if bool(group.state.released) or bool(group.hold): continue
		for enemy in group.members:
			var multiplier: float=0.0 if float(enemy.get("skillMoveStopUntil",0.0))>elapsed else _enemy_route_multiplier(enemy)
			multipliers[int(enemy.id)]={"actor":enemy,"value":multiplier}
			if _stage02_road_column(enemy) and multiplier<=0.0:
				_release_enemy_approach(enemy);break
			group.front=minf(float(group.front),_enemy_approach_progress(enemy)+maxi(0,int(enemy.get("formationRank",0)))*ENEMY_FORMATION_ROW_GAP)
			var march_speed: float=float(enemy.speed)
			if str(enemy.get("kind",""))!="enemy_cavalry": march_speed=minf(march_speed,float(path_march_limits.get(int(enemy.pathIndex),march_speed)))
			group.pace=minf(float(group.pace),maxf(0.0,march_speed*multiplier*delta))
	enemy_approach_step={"clock":elapsed,"generation":battle_generation,"revision":ground_combat.navigation_query_revision,"roster":enemies,"count":enemies.size(),"groups":groups,"multipliers":multipliers}

func _enemy_approach_step_valid() -> bool:
	return not enemy_approach_step.is_empty() and float(enemy_approach_step.clock)==elapsed and int(enemy_approach_step.generation)==battle_generation and int(enemy_approach_step.revision)==ground_combat.navigation_query_revision and is_same(enemy_approach_step.roster,enemies) and int(enemy_approach_step.count)==enemies.size()

func _ordered_enemy_advance(enemy: Dictionary, remaining: float) -> float:
	if not _enemy_approach_step_valid(): return remaining
	var key: String=str(enemy.get("approachCohortKey",""))
	var group: Dictionary=enemy_approach_step.groups.get(key,{})
	if group.is_empty() or bool(group.state.released): return remaining
	if bool(group.hold): return 0.0
	var slot_progress: float=_enemy_approach_progress(enemy)+maxi(0,int(enemy.get("formationRank",0)))*ENEMY_FORMATION_ROW_GAP
	# Never increase this soldier's actual stride or move its position to a
	# slot. Ahead members wait; the whole row advances at the slowest budget.
	return minf(remaining,maxf(0.0,float(group.front)+float(group.pace)-slot_progress))

func _movement_support_candidates(point: Vector2) -> Array:
	var context: Dictionary=unit_skills.membership_query_context()
	if context.is_empty() or not context.has("movementQueryRadius") or float(context.get("movementQueryClock",-1.0))!=elapsed or not game_event.get_connections().is_empty(): return units
	if movement_ranges.is_empty(): return []
	ground_combat._ensure_crowd_index()
	# A fighter killed earlier in this enemy phase still owns its original
	# movement-range entry until normal removal, exactly as in the linear scan.
	return ground_combat.crowd.nearby(point,float(context.movementQueryRadius),true,true)

func _enemy_route_multiplier(enemy: Dictionary) -> float:
	var multiplier: float = _approach_march_factor()
	for unit in _movement_support_candidates(enemy.position):
		var unit_range: float=float(movement_ranges.get(int(unit.id),-1.0))
		if unit_range<0.0: continue
		var separation: Vector2=unit.position-enemy.position
		if absf(separation.x)>unit_range or absf(separation.y)>unit_range: continue
		if unit.position.distance_to(enemy.position)<=unit_range:
			multiplier = ENGAGED_MARCH_FACTOR
			break
	if float(enemy.get("slowClock",0.0)) > 0.0:
		multiplier *= float(enemy.get("slowFactor",0.75))
	for aura in _read_active_auras():
		if bool(aura.active) and enemy.position.distance_to(_point(aura)) <= float(aura.get("r", 0.1)):
			multiplier *= float(aura.get("enemySpeedFactor", 1.0))
	if str(config.get("theme", "")) == "harbor" and int(enemy.pointIndex) <= int(config.get("landingIndex", 2)):
		multiplier *= 1.6
	if storm_active:
		multiplier *= 0.62
		var storm_zone: Dictionary = config.get("stormZone", {})
		if not storm_zone.is_empty() and enemy.position.distance_to(_point(storm_zone)) < float(storm_zone.get("r", 0.11)):
			multiplier = 0.0
	return multiplier

func _move_enemy(enemy: Dictionary, delta: float) -> void:
	if bool(enemy.get("counterReleaseInProgress",false)):
		_release_enemy_approach(enemy)
		return
	# Waterborne troops finish their authored landing before any ground
	# blocker, emplacement pursuit, attack or main-route escape is evaluated.
	if _enemy_transport_step(enemy,delta): return
	if float(enemy.get("skillMoveStopUntil",0.0))>elapsed:
		enemy["attackCooldown"]=maxf(0.0,float(enemy.get("attackCooldown",0.0))-delta)
		if str(enemy.get("animation","idle"))!="attack": enemy["animation"]="idle"
		return
	# Physical marching blockers may delay a hunter's return, but a destroyed
	# emplacement must never remain its committed target during that delay.
	if str(enemy.get("combatRole",""))==ENEMY_EMPLACEMENT_ROLE and not bool(enemy.get("roadRanged",false)) and int(enemy.get("stationaryTargetId",-1))>=0:
		var committed: Dictionary=ground_combat._unit(int(enemy.stationaryTargetId))
		if committed.is_empty() or not can_enemy_engage_unit(enemy,committed): _begin_hunter_return(enemy)
	# Every prepared contact attack retains its actual target through valid
	# windup/release, even when the contact list changes between frames.
	var counter: Dictionary=enemy.get("counterPlan",{})
	if not counter.is_empty():
		var prepared: Dictionary=ground_combat._unit(int(counter.targetId))
		if ground_combat._counter_target_valid(enemy,prepared):
			_release_enemy_approach(enemy)
			ground_combat.counterattack(enemy,delta,prepared)
			return
		ground_combat.cancel_counterattack(enemy)
	if str(enemy.get("kind","")) in ["enemy_archer","enemy_gunner"]:
		if not enemy.get("rangedPlan",{}).is_empty():
			_release_enemy_approach(enemy)
			_enemy_ranged_step(enemy,delta)
			return
		if str(enemy.get("animation",""))=="attack" and float(enemy.get("animationClock",0.0))<.5:
			var recovering: Dictionary=enemy_facing_target(enemy)
			if not recovering.is_empty():
				_release_enemy_approach(enemy)
				enemy["attackCooldown"]=maxf(0.0,float(enemy.get("attackCooldown",0.0))-delta)
				_aim_enemy_attack(enemy,recovering,delta)
				return
			enemy["animation"]="idle" if bool(enemy.get("stationaryEnemy",false)) else "walk"
	if ground_combat.enemy_melee_step(enemy,delta):
		_release_enemy_approach(enemy)
		return
	if ground_combat.blocked(enemy) or ground_combat.enemy_contact(enemy):
		_release_enemy_approach(enemy)
		if _mobile_emplacement_attacker(enemy) and not bool(enemy.get("ingressActive",false)) and not bool(enemy.get("hunterReturning",false)):
			var raid_target: Dictionary=_hunter_target(enemy,delta)
			if not raid_target.is_empty() and _emplacement_approach(enemy,raid_target,delta):
				if str(enemy.kind) in ["enemy_archer","enemy_gunner"]: enemy["attackCooldown"]=maxf(0.0,float(enemy.get("attackCooldown",0.0))-delta)
				return
		enemy["rangedPlan"]={}
		ground_combat.counterattack(enemy,delta)
		return
	if _enemy_ingress_step(enemy,delta):
		_release_enemy_approach(enemy)
		ground_combat.cancel_counterattack(enemy)
		return
	if _hunter_return_step(enemy,delta):
		_release_enemy_approach(enemy)
		ground_combat.cancel_counterattack(enemy)
		return
	if _enemy_stationary_threat(enemy,delta):
		_release_enemy_approach(enemy)
		return
	enemy["blockedBy"] = -1
	ground_combat.cancel_counterattack(enemy)
	if not _sailing_visual(enemy) and _enemy_ranged_step(enemy,delta):
		_release_enemy_approach(enemy)
		return
	if bool(enemy.get("stationaryEnemy",false)): return
	var path: Dictionary = paths[int(enemy.pathIndex)]
	var previous: Vector2 = enemy.position
	var cached_multiplier: Dictionary=enemy_approach_step.multipliers.get(int(enemy.id),{}) if _enemy_approach_step_valid() else {}
	var multiplier: float=float(cached_multiplier.value) if not cached_multiplier.is_empty() and is_same(cached_multiplier.actor,enemy) else _enemy_route_multiplier(enemy)
	var remaining: float = float(enemy.speed) * multiplier * delta
	var lane_column: bool=_stage02_road_column(enemy)
	if not lane_column: remaining=_ordered_enemy_advance(enemy,remaining)
	var next_animation: String = "idle" if _ordered_enemy_advance(enemy,remaining) <= .0000001 else "walk"
	if str(enemy.get("animation", "walk")) != next_animation:
		enemy["animation"] = next_animation
		enemy["animationClock"] = 0.0
	var guard: int = 0
	while remaining > 0.0 and guard < 10:
		guard += 1
		var point_index: int = int(enemy.pointIndex)
		if point_index >= path.points.size():
			_escape_enemy(enemy, str(path.get("objectiveId", "main")))
			break
		var target: Vector2 = _enemy_lane_point(enemy,point_index)
		if lane_column and _enemy_lane_waypoint_passed(enemy,target):
			enemy.pointIndex=point_index+1
			continue
		if point_index == path.points.size() - 1:
			# A fixed camp can have several defended contact points sharing HP.
			# Hunters returning to their own route must keep that route's endpoint.
			target=path.points[-1]
			if str(enemy.combatRole)!=ENEMY_PATH_ROLE:
				var obj: Dictionary = _objective(str(path.get("objectiveId", "main")))
				if not obj.is_empty() and bool(obj.get("mobile",false)): target=obj.position
		var offset: Vector2 = target - enemy.position
		var distance: float = offset.length()
		# Spend the original physical stride across corners; recheck only the
		# row's remaining lane station at each leg, never grant catch-up speed.
		var available: float=_ordered_enemy_advance(enemy,remaining) if lane_column else remaining
		if available<=.0000001: break
		var next_position: Vector2 = target if available >= distance else enemy.position + offset.normalized() * available
		# Mission-required soldiers march along the same road as the wave.
		# Their kill tracking must not create a separate stop at the capture point.
		if lane_column: next_position=_enemy_road_walk_step(enemy,next_position,available)
		if not _sailing_visual(enemy) and not ground_combat.crowd.nearby(enemy.position,.10,true).is_empty():
			var legal: Callable=func(a: Vector2,b: Vector2) -> bool:
				if not ground_combat.land_segment_safe(a,b,.008): return false
				return not lane_column or _enemy_road_step_safe(enemy,a,b)
			next_position=ground_combat.crowd.move_point(enemy,next_position,false,legal,target if lane_column else Vector2(INF,INF))
		# Authored bridge and landing segments keep their existing water rules.
		# Every ordinary ground step still respects this scene's real walls.
		if not _sailing_visual(enemy) and ground_combat.structure_segment_clear.is_valid() and not bool(ground_combat.structure_segment_clear.call(enemy.position,next_position,.008)):
			_release_enemy_approach(enemy)
			enemy["animation"] = "idle"
			break
		if available >= distance and next_position.distance_squared_to(target)<.000000000001:
			enemy["position"] = target
			enemy["pointIndex"] = point_index + 1
			remaining -= distance
		else:
			enemy["position"] = next_position
			remaining = 0.0
	if not finished and not bool(enemy.get("escaped",false)):
		_turn_enemy(enemy,enemy.position-previous,delta)
		enemy["routeProgress"]=maxf(float(enemy.get("routeProgress",0.0)),ground_combat.enemy_distance(enemy))
		_track_footstep(enemy,previous,"enemy")

func _escape_enemy(enemy: Dictionary, objective_id: String) -> void:
	if bool(enemy.escaped):
		return
	enemy["escaped"] = true
	unit_skills.cancel_ninja_target_charges(enemy)
	enemy["routeProgress"]=float(ground_combat.cumulative[int(enemy.pathIndex)][-1])
	enemy["hp"] = 0.0
	var obj: Dictionary = _objective(objective_id)
	if obj.is_empty():
		return
	var previous_health: int = int(obj.hp)
	obj["hp"] = maxi(0, previous_health - int(enemy.damage))
	var impact: Vector2 = obj.position if bool(obj.get("mobile",false)) else enemy.position
	_combat_event("objective_hit",enemy,{}, {"victimId":str(obj.get("id",objective_id)),"victimSide":"objective","victimPosition":_normalized_position(impact),"position":_normalized_position(impact),"objectivePosition":_normalized_position(obj.position),"damage":previous_health-int(obj.hp),"hpAfter":int(obj.hp)})
	effects.append({"position":impact,"time":0.0,"duration":0.6,"color":Color("d75744"),"kind":"damage"})
	if int(obj.hp) <= 0:
		_finish(false)

func _update_units(delta: float) -> void:
	for unit in units:
		unit["cooldown"] = maxf(0.0, float(unit.cooldown) - delta)
		if str(unit.type)=="monk" or str(unit.get("combatState","")) in ["gather","guard_dash"] or not ground_combat.active_support(unit) or float(unit.cooldown)>0.0 or str(unit.get("animation","idle"))=="attack" or not unit_skills.attack_ready(unit):
			continue
		if str(unit.type)=="commander" and unit_skills.can_charge(unit) and float(unit.get("chargeCooldown",0))<=0.0:
			continue
		if ground_combat.melee_attack_waiting(unit): continue
		var stats: Dictionary = _read_stats(unit)
		var target: Dictionary = {}
		var best_progress: float = -1.0
		if GroundCombat.is_frontline(str(unit.type)):
			target = ground_combat.attack_target(unit)
		else:
			for enemy in unit_skills.enemy_area_candidates(unit.position,maxf(0.0,float(stats.range))):
				if not can_friendly_target_enemy(unit,enemy) or not _enemy_visible(enemy): continue
				if unit.position.distance_to(enemy.position) > float(stats.range): continue
				var progress: float = float(enemy.pointIndex) / paths[int(enemy.pathIndex)].points.size()
				if progress > best_progress: best_progress=progress;target=enemy
		if target.is_empty() or not can_friendly_target_enemy(unit,target) or not ground_combat.primary_target_allowed(unit,target,"prepare"):
			continue
		var melee_duration: float=float(stats.interval) if str(unit.type)=="ninja" else maxf(float(stats.interval),_animation_duration("attack"))
		var melee_seat: int=ground_combat.claim_melee_attack(unit,target,true,melee_duration)
		if melee_seat<0: continue
		unit["aim"] = (target.position - unit.position).normalized()
		unit["cooldown"] = float(stats.interval)
		var damage: float = float(stats.damage)
		unit["animation"] = "attack"
		unit["animationClock"] = 0.0
		var duration: float = minf(_animation_duration("attack"),float(stats.interval)*0.95) if str(unit.type) in ["ninja","spear"] else _animation_duration("attack")
		unit["attackDuration"] = duration
		unit["attackPlan"] = unit_skills.prepare_attack(unit,target,damage,_impact_time(str(unit.type))*duration/_animation_duration("attack"))
		if melee_seat>0: unit.attackPlan["meleeSeatToken"]=melee_seat
		if str(unit.type)=="ninja" and not unit.attackPlan.is_empty(): ground_combat.commit_ninja_melee_attack(unit,unit.attackPlan,float(stats.interval))

func _advance_actor_animations(delta: float) -> void:
	var generation: int=battle_generation
	for unit in units:
		unit["animationClock"] = float(unit.get("animationClock", 0.0)) + delta
		unit["pulseClock"] = maxf(0.0, float(unit.get("pulseClock", 0.0)) - delta)
		unit["hitClock"] = maxf(0.0,float(unit.get("hitClock",0))-delta)
		var state: String = str(unit.get("animation", "idle"))
		if state == "walk" and bool(unit.get("deploying",false)) and float(unit.animationClock) >= float(unit.get("deployDuration", 0.35)):
			unit["animation"] = "idle"
			unit["animationClock"] = 0.0
			unit["deploying"] = false
		elif state == "attack":
			var plan: Dictionary = unit.get("attackPlan", {})
			if not plan.is_empty() and str(unit.type)=="ninja" and not str(plan.get("ninjaAction","")).is_empty():
				var complete: bool=unit_skills.advance_ninja_attack(unit,plan,float(unit.animationClock))
				if generation!=battle_generation or battle_closed: return
				if complete and is_same(unit.get("attackPlan",{}),plan): unit["attackPlan"]={}
			elif not plan.is_empty() and plan.has("releaseTimes"):
				var complete: bool=unit_skills.actions.advance(unit,plan,float(unit.animationClock))
				if generation!=battle_generation or battle_closed: return
				if complete and is_same(unit.get("attackPlan",{}),plan): unit["attackPlan"]={}
			elif not plan.is_empty() and float(unit.animationClock) >= float(plan.get("releaseTime", 0.25)):
				_release_unit_attack(unit, plan)
				if generation!=battle_generation or battle_closed: return
				if bool(plan.get("guardDash",false)) and not unit.get("guardDashData",{}).is_empty():
					unit_skills.finish_guard_dash(unit,false)
					unit.guardDashData={}
				unit["attackPlan"] = {}
			if float(unit.animationClock) >= float(unit.get("attackDuration",_animation_duration("attack"))):
				unit["animation"] = "idle"
				unit["animationClock"] = 0.0
		elif state=="heal" and float(unit.animationClock)>=float(unit.get("healDuration",.6)):
			unit["animation"]="idle"
			unit["animationClock"] = 0.0
	for enemy in enemies:
		if str(enemy.get("animation","idle"))!="attack" or float(enemy.get("skillAttackDelayUntil",0.0))<=elapsed:
			enemy["animationClock"] = float(enemy.get("animationClock", 0.0)) + delta
		enemy["hitClock"] = maxf(0.0, float(enemy.get("hitClock", 0.0)) - delta)
		enemy["slowClock"] = maxf(0.0, float(enemy.get("slowClock", 0.0)) - delta)

func _release_unit_attack(unit: Dictionary, plan: Dictionary) -> void:
	if str(unit.type)=="ninja" and not str(plan.get("ninjaAction","")).is_empty():
		unit_skills.advance_ninja_attack(unit,plan,float(unit.get("animationClock",0.0)))
		return
	if plan.has("releaseTimes"):
		unit_skills.actions.advance(unit,plan,float(unit.get("animationClock",0.0)))
		return
	if str(unit.type)=="monk" or float(unit.get("hp",0))<=0 or bool(unit.get("consumed",false)): return
	if not plan.get("skillMeta",{}).is_empty() and not unit_skills._valid_meta(plan.skillMeta): return
	if bool(plan.get("nativeReleaseConsumed",false)): return
	var generation: int=battle_generation
	plan["nativeReleaseConsumed"]=true
	var ground: bool = GroundCombat.is_ground(str(unit.type))
	var frontline: bool = GroundCombat.is_frontline(str(unit.type))
	if frontline and not ground_combat.can_fight(unit): return
	var target: Dictionary = _enemy(int(plan.targetId))
	# Territorial melee keeps the prepared actor/target commitment. A dead
	# target frees that group seat instead of redirecting this windup's hit.
	if ground and not ground_combat.melee_release_allowed(unit,target,plan,true): return
	# A corpse remains in the roster until this step's casualty pass. Let it
	# reach the existing dead-target fallback just like an already removed foe.
	if not target.is_empty() and float(target.get("hp",0.0))>0.0 and not can_friendly_target_enemy(unit,target): return
	var stats: Dictionary = _read_stats(unit)
	if str(unit.type) in ["naginata","ninja"]:
		var original_target_valid: bool=ground_combat.primary_target_allowed(unit,target,"release")
		if bool(plan.get("guardDash",false)) and int(unit.get("guardDashTargetId",-1))!=int(plan.targetId): original_target_valid=false
		if not original_target_valid:
			if str(unit.type)=="ninja":
				var reason: String="target_defeated" if not target.is_empty() and float(target.get("hp",0))<=0 else "target_lost"
				ground_combat.mark_ninja_consumed(unit,reason)
			return
	if target.is_empty() or float(target.hp) <= 0.0:
		if frontline:
			target = ground_combat.attack_target(unit) if not bool(plan.get("charge",false)) else {}
		else:
			target = {}
			for candidate in enemies:
				if can_friendly_target_enemy(unit,candidate) and _enemy_visible(candidate) and unit.position.distance_to(candidate.position) <= float(stats.range):
					target = candidate
					break
	if target.is_empty():
		return
	if not ground_combat.primary_target_allowed(unit,target,"release"): return
	unit["aim"] = (target.position - unit.position).normalized()
	var damage: float = float(plan.damage)
	var source: Dictionary=_attack_source(unit,plan)
	if ground:
		if not ground_combat.shares_contact_front(unit,target) or unit.position.distance_to(target.position) > ground_combat.reach(unit)*1.1 or not ground_combat.land_segment_safe(unit.position,target.position):
			return
		_combat_event("shot",unit,target,_skill_event_fields(plan))
		if generation!=battle_generation or battle_closed or finished: return
		if float(unit.get("hp",0.0))<=0.0 or not is_same(ground_combat._unit(int(unit.id)),unit) or not ground_combat.melee_release_allowed(unit,target,plan,true) or not ground_combat.primary_target_allowed(unit,target,"release") or unit.position.distance_to(target.position)>ground_combat.reach(unit)*1.1 or not ground_combat.land_segment_safe(unit.position,target.position): return
		var actual_damage: float = _damage_enemy(target, damage, str(unit.type),source)
		if generation!=battle_generation or battle_closed or finished: return
		if actual_damage>0.0:
			plan["actualReleaseCommitted"]=true
			unit_skills.actions.on_primary_impact(unit,target,plan,actual_damage)
			if generation!=battle_generation or battle_closed or finished: return
		if bool(plan.get("charge",false)):
			_combat_event("charge_impact",unit,target,{"damage":actual_damage,"position":_normalized_position(target.position)})
			if generation!=battle_generation or battle_closed or finished: return
		effects.append({"position":target.position,"time":0.0,"duration":0.18,"color":Color("e8d8b4"),"kind":"hit"})
		unit_skills.after_release(unit,target,plan)
		if str(unit.type)=="ninja" and float(target.hp)<=0:
			ground_combat.mark_ninja_consumed(unit,"target_defeated")
		if bool(plan.get("guardDash",false)):
			unit_skills.finish_guard_dash(unit,true)
			unit.guardDashData={}
	else:
		if not _enemy_visible(target) or unit.position.distance_to(target.position)>float(stats.range): return
		if str(unit.type)=="gunner" and (int(target.pathIndex)!=int(unit.postPathIndex) or unit.position.distance_to(target.position)>float(stats.range) or not _enemy_visible(target) or _sailing_visual(target)):
			return
		var shot: Dictionary={"position":unit.position,"targetId":target.id,"targetPos":target.position,"damage":damage,"type":unit.type,"sourceId":unit.id,"sourcePosition":unit.position,"sourceUnit":source,"emplacementShooter":bool(unit.get("emplacementShooter",false)),"speed":2.7 if str(unit.type)=="gunner" else .65,"age":0.0}
		projectiles.append(unit_skills.decorate_projectile(shot,unit,plan))
		plan["actualReleaseCommitted"]=true
		unit_skills.actions.on_release(unit,plan)
		_combat_event("shot",unit,target,_skill_event_fields(plan))
		if generation!=battle_generation or battle_closed or finished: return
		unit_skills.after_release(unit,target,plan)

func _skill_event_fields(context: Dictionary) -> Dictionary:
	var fields: Dictionary={}
	for key in ["skillId","skillIds","flags","effectKind","skillMeta","campaignLevel","hitIndex","releaseIndex","releaseTime","skillAction","chargeId","ninjaAction","duration"]:
		if context.has(key):
			var value: Variant=context[key]
			fields[key]=value.duplicate(true) if value is Dictionary or value is Array else value
	if not fields.has("campaignLevel") and context.get("skillMeta",{}).has("campaignLevel"): fields["campaignLevel"]=int(context.skillMeta.campaignLevel)
	return fields

func _attack_source(unit: Dictionary, context: Dictionary = {}) -> Dictionary:
	var source: Dictionary={"id":int(unit.id),"type":str(unit.type),"position":unit.position,"campaignLevel":int(unit.get("campaignLevel",1)),"emplacementShooter":bool(unit.get("emplacementShooter",false))}
	source.merge(_skill_event_fields(context),true)
	return source

func _update_death_actors(delta: float) -> void:
	var survivors: Array = []
	for actor in death_actors:
		actor["animationClock"] = float(actor.animationClock) + delta
		if float(actor.animationClock) < _animation_duration("death"):
			survivors.append(actor)
	death_actors = survivors

func animation_frame_data(actor: Dictionary, phase_offset: float = 0.0, enemy_actor: bool = false) -> Dictionary:
	var state: String = str(actor.get("animation", "idle"))
	var clock: float = float(actor.get("animationClock", 0.0))
	var definition: Dictionary = _animation_definition(state)
	var fps: float = maxf(1.0, float(definition.get("fps", 5.0)))
	var frame_count: int = maxi(1, int(definition.get("frames", 6)))
	var phase: float = float(actor.get("animationPhase", 0.0)) + phase_offset
	var frame: int = int(floor((clock + phase) * fps)) % frame_count
	if not bool(definition.get("loop", state in ["idle","walk"])):
		frame = clampi(int(floor((clock + phase_offset) * fps)), 0, frame_count - 1)
	var key: String = str(actor.get("type", "archer"))
	if enemy_actor:
		key = "enemy_heavy" if str(actor.get("kind", "raider")) in ["shield","heavy","commander","enemy_samurai"] else "enemy_light"
	var cell: Vector2 = Vector2(256,256)
	if animated_textures.has(key):
		var texture: Texture2D = animated_textures[key]
		cell = Vector2(texture.get_width()/float(animation_manifest.get("columns", 6)),texture.get_height()/float(animation_manifest.get("rows", 4)))
	var row: int = int(definition.get("row", 0))
	return {"state":state,"row":row,"frame":frame,"clock":clock,"textureKey":key,"source":"animated" if animated_textures.has(key) else "static-fallback","region":{"x":frame*cell.x,"y":row*cell.y,"w":cell.x,"h":cell.y}}

func _update_projectiles(delta: float) -> void:
	var remaining: Array = []
	var current: Array=projectiles
	projectiles=[]
	for shot in current:
		shot["age"] = float(shot.age) + delta
		var hostile: bool=str(shot.get("victimSide","enemy"))=="friendly"
		var target: Dictionary = ground_combat._unit(int(shot.targetId)) if hostile else _enemy(int(shot.targetId))
		var hostile_source: Dictionary=shot.get("sourceActor",{})
		if hostile and hostile_source.is_empty(): hostile_source=_enemy(int(shot.get("sourceId",-1)))
		if hostile and not can_enemy_engage_unit(hostile_source,target): continue
		var target_alive: bool=not target.is_empty() and float(target.get("hp",0))>0
		if not hostile and target_alive:
			var projectile_source: Dictionary=shot.get("sourceUnit",{"type":str(shot.type),"emplacementShooter":bool(shot.get("emplacementShooter",false))})
			if not can_friendly_target_enemy(projectile_source,target): continue
		var barrage: bool=not hostile and "archer_barrage" in shot.get("skillMeta",{}).get("skillIds",[])
		if float(shot.age)>2.0 or (not target_alive and not barrage):
			continue
		if target_alive: shot["targetPos"] = target.position
		var impact_position: Vector2=shot.targetPos+shot.get("impactOffset",Vector2.ZERO)
		var offset: Vector2 = impact_position - shot.position
		var distance: float = offset.length()
		var step: float = float(shot.speed) * delta
		if distance <= step:
			shot["position"]=impact_position
			shot["impactPosition"]=impact_position
			if hostile:
				_damage_friendly(target,float(shot.damage),hostile_source)
			else:
				var source: Dictionary={"id":int(shot.get("sourceId",-1)),"type":str(shot.type),"position":shot.get("sourcePosition",shot.position),"campaignLevel":int(shot.get("campaignLevel",1)),"emplacementShooter":bool(shot.get("emplacementShooter",shot.get("sourceUnit",{}).get("emplacementShooter",false)))}
				source.merge(shot.get("sourceUnit",{}),true)
				source.merge(_skill_event_fields(shot),true)
				var actual_damage: float=_damage_enemy(target,float(shot.damage),str(shot.type),source) if target_alive else 0.0
				unit_skills.after_projectile_hit(shot,target if target_alive else {},actual_damage)
			effects.append({"position":impact_position,"time":0.0,"duration":0.15,"color":Color("edc585"),"kind":"hit"})
		else:
			shot["position"] = shot.position + offset.normalized() * step
			remaining.append(shot)
	projectiles.append_array(remaining)

func _damage_friendly(unit: Dictionary, amount: float, source: Dictionary, impact: Dictionary = {}) -> float:
	if not can_enemy_engage_unit(source,unit,true): return 0.0
	var impact_id: String=str(impact.get("impactId",""))
	if not impact_id.is_empty():
		if friendly_impact_receipts.has(impact_id): return 0.0
		# Consume before modifiers/notifications can synchronously reenter.
		friendly_impact_receipts[impact_id]=true
	var generation: int=battle_generation
	var armor: float=UnitGrowth.base_armor(str(unit.type))
	var modified: Dictionary=unit_skills.modify_incoming(unit,amount,armor,source,impact)
	if generation!=battle_generation or battle_closed or finished or not can_enemy_engage_unit(source,unit,true) or not is_same(ground_combat._unit(int(unit.id)),unit): return 0.0
	if bool(impact.get("contactCounter",false)) and not ground_combat.counter_impact_allowed(source,unit,impact): return 0.0
	var before: float=float(unit.hp)
	unit["hp"]=maxf(0,before-maxf(0,float(modified.get("amount",amount*(1.0-armor)))))
	var after: float=float(unit.hp)
	var actual_damage: float=before-after
	unit["hitClock"]=.12
	var fields: Dictionary=_skill_event_fields(modified)
	fields.merge({"position":_normalized_position(unit.position),"damage":actual_damage,"hpBefore":before,"hpAfter":after,"armor":float(modified.get("armor",armor)),"blocked":bool(modified.get("blocked",false))},true)
	for key in ["attackId","impactId","contactCounter","counterTargetLimit"]:
		if impact.has(key): fields[key]=impact[key]
	# HP is already changed when the individual hit event is observed.
	_combat_event("hit",source,unit,fields)
	if generation!=battle_generation: return actual_damage
	if float(unit.hp)<=0:
		ground_combat._on_unit_injured(unit)
		friendly_casualties_pending=true
	return actual_damage

func _damage_enemy(enemy: Dictionary, amount: float, unit_type: String, source: Dictionary = {}) -> float:
	var shooter: Dictionary=source if not source.is_empty() else {"type":unit_type}
	var actor: Dictionary=ground_combat._unit(int(source.get("id",-1)))
	if not actor.is_empty(): shooter=actor
	if not can_friendly_target_enemy(shooter,enemy): return 0.0
	var generation: int=battle_generation
	var previous_health: float = float(enemy.hp)
	var armor: float = unit_skills.modify_enemy_armor(enemy,float(enemy.armor))
	var modified: Dictionary=unit_skills.modify_outgoing(enemy,amount,unit_type,source)
	amount=maxf(0,float(modified.get("amount",amount)))
	if unit_type == "samurai" or unit_type == "commander":
		armor *= 0.4
	elif unit_type == "gunner":
		armor *= 0.3
	if unit_type == "ninja" and not bool(source.get("ninjaPayload",false)) and float(enemy.hp) <= float(enemy.maxHp)*0.30:
		amount *= 1.5
	enemy["hp"] = 0.0 if bool(modified.get("instant",false)) else maxf(0,float(enemy.hp)-amount*(1.0-armor))
	if float(enemy.hp)<=0.0: unit_skills.cancel_ninja_target_charges(enemy)
	var actual_damage: float = previous_health-maxf(0,float(enemy.hp))
	if actual_damage<=0.0: return 0.0
	unit_skills.actions.after_enemy_damage(source,actual_damage)
	var attacker: Dictionary = source if not source.is_empty() else {"type":unit_type,"id":-1,"position":enemy.position}
	enemy["lastHit"] = {"actorId":attacker.get("id",-1),"unitType":unit_type,"sourcePosition":attacker.get("position",enemy.position),"impactId":str(source.get("skillMeta",{}).get("impactId",""))}
	var fields: Dictionary=_skill_event_fields(source)
	if not str(modified.get("skillId","")).is_empty(): fields["skillId"]=str(modified.skillId)
	if not str(modified.get("effectKind","")).is_empty(): fields["effectKind"]=str(modified.effectKind)
	var flags: Dictionary=fields.get("flags",{}).duplicate(true)
	flags.merge(modified.get("flags",{}),true)
	fields["flags"]=flags
	fields.merge({"damage":actual_damage,"hpBefore":previous_health,"hpAfter":float(enemy.hp),"armor":armor,"position":_normalized_position(enemy.position),"instant":bool(modified.get("instant",false))},true)
	_combat_event("hit",attacker,enemy,fields)
	if generation!=battle_generation or battle_closed or finished or not is_same(_enemy(int(enemy.id)),enemy): return actual_damage
	enemy["hitClock"] = 0.12
	unit_skills.after_enemy_hit(enemy,actual_damage,unit_type,source)
	return actual_damage

func _update_map_mode(delta: float) -> void:
	var theme: String = str(config.get("theme", ""))
	var weather: Dictionary = config.get("historicalBattlefield",{}).get("presentationWeather",{})
	# Legacy map themes are navigation/game-mode labels, not evidence of snow
	# in the selected historical phase. Only an explicit snow presentation
	# may enable the existing storm mechanic.
	if theme == "snow" and float(weather.get("snowCoverage",0)) > 0:
		storm_clock += delta
		var next_storm: bool = fmod(storm_clock, 26.0) > 19.0
		if next_storm != storm_active:
			storm_active = next_storm
			_event("weather", "눈보라! 고갯길이 잠시 막히고 공격 범위가 줄어듭니다." if storm_active else "눈보라가 잦아들었습니다.")
	else:
		storm_active = false
		storm_clock = 0.0
	if theme == "convoy" and not objectives.is_empty():
		var route_points: Array = config.get("escortRoute", [])
		if route_points.size() < 2:
			return
		escort_distance += delta * 0.005
		var full_length: float = 0.0
		for i in range(route_points.size() - 1):
			full_length += _point(route_points[i]).distance_to(_point(route_points[i + 1]))
		var distance: float = fmod(escort_distance, maxf(full_length, 0.01))
		for i in range(route_points.size() - 1):
			var start: Vector2 = _point(route_points[i])
			var end: Vector2 = _point(route_points[i + 1])
			var segment: float = start.distance_to(end)
			if distance <= segment:
				objectives[0]["position"] = start.lerp(end, distance / maxf(segment, 0.001))
				break
			distance -= segment

func _enemy_visible(enemy: Dictionary) -> bool:
	var historical: Dictionary = config.get("historicalBattlefield",{})
	var weather: Dictionary = historical.get("presentationWeather",{})
	var time_of_day: String = str(weather.get("timeOfDay",historical.get("timeOfDay","day")))
	if time_of_day != "night":
		return true
	for torch in config.get("torches", []):
		if enemy.position.distance_to(_point(torch)) < 0.18:
			return true
	for unit in units:
		if enemy.position.distance_to(unit.position) < 0.245:
			return true
	for obj in objectives:
		if enemy.position.distance_to(obj.position) < 0.14:
			return true
	return false

func _complete_wave() -> void:
	if bool(config.get("trainingOnly",false)) or not bool(EnemyModeProfiles.profile_for(config).get("combatEnabled",true)): return
	if finished or wave<=completed_wave or wave<=0: return
	if not _cycle_attackers_cleared(): return
	var generation: int=battle_generation
	# The last enemy can hit the camp in this same combat step. Clearing a
	# finite attack queue must never outrank the loss of the allied objective.
	for objective in objectives:
		if int(objective.hp)<=0:
			_finish(false)
			return
	# Receipt before notifications: reentry cannot repeat rewards or this
	# cycle's completion event, including while the final mission stays active.
	completed_wave=wave
	var cleared_cycle: int=wave
	# Stage01/02 retain their passive/kill economy without a flat stipend.
	var stipend_default: bool=not _stage01_light_replacements() and not advance_mission.enabled
	if bool(config.get("waveGoldBonusEnabled",stipend_default)): gold += 40 + wave * 3
	var supply: Dictionary = _trait().get("waveGold", {})
	if not supply.is_empty() and wave % maxi(1, int(supply.get("every", 1))) == 0:
		var amount: int = maxi(0, int(supply.get("amount", 0)))
		gold += amount
		_event("trait-supply", "작전 보급 · 금화 +%d" % amount)
		if generation!=battle_generation or finished or battle_closed or wave!=cleared_cycle: return
	var final_wave: bool = wave>=total_waves
	_event("waveend","",{"side":"system","final":final_wave,"kills":kills})
	if generation!=battle_generation or finished or battle_closed or wave!=cleared_cycle: return
	if final_wave:
		# Hold, production and physical followup travel continue after the last
		# cycle when required. No timers, enemy refills or repeat clear receipts.
		between_waves=false
		advance_mission.step(0.0)
		if advance_mission.enabled and advance_mission.failed: _finish(false)
		elif not _try_finish_cycles(): _emit_state()
		return
	between_waves = true
	_emit_state()
	if generation!=battle_generation or finished or battle_closed or wave!=cleared_cycle: return
	wave_ended.emit({"wave":wave,"totalWaves":total_waves,"mapId":config.get("id", ""),"kills":kills})

func _finish(won: bool) -> void:
	if finished:
		return
	if won and (bool(config.get("trainingOnly",false)) or not _attack_cycles_cleared()): return
	if won and advance_mission.enabled and not advance_mission.complete and not advance_mission.failed: return
	if won:
		for objective in objectives:
			if float(objective.get("hp",0))<=0: won=false;break
	if advance_mission.enabled:
		if not won and not advance_mission.failed:
			var base_lost: bool=false
			for objective in objectives:
				if float(objective.get("hp",0))<=0: base_lost=true;break
			advance_mission.fail("base_lost" if base_lost else "mission_failed")
		won=won and advance_mission.complete and not advance_mission.failed
	var generation: int=battle_generation
	finished=true
	unit_skills.cancel_ninja_charges()
	battle_support.cease()
	victory = won
	ambush_warnings.clear()
	_cancel_all_recruitment("battle_finished")
	if generation!=battle_generation or battle_closed: return
	cancel_recruit()
	if generation!=battle_generation or battle_closed: return
	_remove_fallen_units()
	if generation!=battle_generation or battle_closed: return
	ground_combat.cease_combat()
	_remove_consumed_units()
	if generation!=battle_generation or battle_closed: return
	running = false
	paused = false
	between_waves = false
	_emit_state()
	battle_finished.emit(snapshot())

func movement_search_range(unit: Dictionary) -> float:
	# Current marching skills change damage/interval, never range. Searching
	# for nearby enemies needs no spear-aura or commander damage roster scan.
	# Other roles retain the complete skill range calculation in _stats.
	if not GroundCombat.is_marching(str(unit.get("type",""))): return float(_read_stats(unit).range)
	var definition: Dictionary=_unit_definition(unit)
	var value: float=float(definition.range)*float(UnitGrowth.factors(unit,definition).range)
	value*=1.0+maxf(0.0,float(unit.get("postRangeBonusPercent",0.0)))/100.0
	for bonus in _trait().get("unitBonuses",[]):
		if str(bonus.get("type","all")) in [str(unit.type),"all"]: value*=float(bonus.get("rangeFactor",1.0))
	if unit.has("position"):
		for aura in _read_active_auras():
			if bool(aura.active) and unit.position.distance_to(_point(aura))<=float(aura.get("r",.1)): value*=float(aura.get("unitRangeFactor",1.0))
	if storm_active: value*=.82
	return value

func _stats(unit: Dictionary) -> Dictionary:
	var result: Dictionary=_read_stats(unit)
	# Keep the existing mutable-copy contract for snapshots and external users.
	return result.duplicate(true) if result.is_read_only() else result

func _read_stats(unit: Dictionary) -> Dictionary:
	var context: Dictionary=unit_skills.read_query_context()
	var actor_id: int=int(unit.get("id",-1))
	if not context.is_empty() and actor_id>=0 and context.stats.has(actor_id):
		var cached: Dictionary=context.stats[actor_id]
		if is_same(cached.actor,unit): return cached.stats
	var result: Dictionary=_calculate_stats(unit)
	if not context.is_empty() and actor_id>=0:
		unit_skills.freeze_query_snapshot(result)
		context.stats[actor_id]={"actor":unit,"stats":result}
	return result

func _calculate_stats(unit: Dictionary) -> Dictionary:
	var definition: Dictionary = _unit_definition(unit)
	var growth: Dictionary = UnitGrowth.factors(unit,definition)
	var attack_range: float = float(definition.range)*float(growth.range)
	attack_range*=1.0+maxf(0.0,float(unit.get("postRangeBonusPercent",0.0)))/100.0
	var damage: float = float(definition.damage)*float(growth.damage)
	var interval: float = float(definition.interval)*float(growth.interval)
	for bonus in _trait().get("unitBonuses", []):
		if str(bonus.get("type", "all")) in [str(unit.type), "all"]:
			damage *= float(bonus.get("damageFactor", 1.0))
			attack_range *= float(bonus.get("rangeFactor", 1.0))
			interval *= float(bonus.get("intervalFactor", 1.0))
	if unit.has("position"):
		for aura in _read_active_auras():
			if bool(aura.active) and unit.position.distance_to(_point(aura)) <= float(aura.get("r", 0.1)):
				damage *= float(aura.get("unitDamageFactor", 1.0))
				attack_range *= float(aura.get("unitRangeFactor", 1.0))
				interval *= float(aura.get("unitIntervalFactor", 1.0))
		var learning_factor: float = 1.0
		for support in learning_supports:
			if float(support.remaining)>0.0 and unit.position.distance_to(_point(support))<=float(support.r):
				learning_factor = maxf(learning_factor,float(support.unitDamageFactor))
		damage *= learning_factor
	if storm_active:
		attack_range *= 0.82
	var modifiers: Dictionary=unit_skills.stat_modifiers(unit)
	damage*=float(modifiers.get("damageFactor",1.0))
	attack_range*=float(modifiers.get("rangeFactor",1.0))
	interval*=float(modifiers.get("intervalFactor",1.0))
	var support: Dictionary = unit_skills.support_stats(unit) if str(unit.type)=="monk" else {}
	var health: float=float(definition.get("hp",UnitGrowth.BASE_HEALTH.get(str(unit.type),105.0)))*float(growth.health)
	return {"damage":damage,"range":attack_range,"interval":maxf(0.25 if unit.has("campaignLevel") and definition.has("cost") else 0.5, interval),"color":definition.color,"health":health,"armor":UnitGrowth.armor(unit,unit_skills.has_skill(unit,"samurai_armor")),"healAmount":float(support.get("healAmount",0.0)),"healInterval":float(support.get("healInterval",1.0)),"supportStats":support}

func _trait() -> Dictionary:
	return config.get("trait", {})

func active_auras() -> Array:
	var result: Array=_read_active_auras()
	return result.duplicate(true) if result.is_read_only() else result

func _read_active_auras() -> Array:
	var context: Dictionary=unit_skills.membership_query_context()
	if context.is_empty(): return _calculate_active_auras()
	var definitions: Array=_trait().get("auras",[])
	var cached: Dictionary=context.get("activeAuraQuery",{})
	if not cached.is_empty() and float(cached.clock)==elapsed and int(cached.count)==definitions.size() and (definitions.is_empty() or is_same(cached.definitions,definitions)): return cached.auras
	var result: Array=_calculate_active_auras()
	unit_skills.freeze_query_snapshot(result)
	context["activeAuraQuery"]={"clock":elapsed,"definitions":definitions,"count":definitions.size(),"auras":result}
	return result

func _calculate_active_auras() -> Array:
	var result: Array = []
	for definition in _trait().get("auras", []):
		var aura: Dictionary = definition.duplicate(true)
		var period: float = maxf(0.1, float(aura.get("period", 20.0)))
		var active_seconds: float = clampf(float(aura.get("activeSeconds", period)), 0.0, period)
		var phase: float = fmod(elapsed + float(aura.get("phaseOffset", 0.0)), period)
		aura["active"] = phase < active_seconds
		aura["phase"] = phase
		aura["remaining"] = active_seconds-phase if bool(aura.active) else period-phase
		result.append(aura)
	return result

func _placement_type(type_name: String = "") -> String:
	return type_name if not type_name.is_empty() else str(pending.get("type","archer"))

func placement_contract(type_name: String) -> Dictionary:
	return GroundCombat.placement_contract(type_name,config)

func _placement_position(p: Vector2, build_zone: Dictionary) -> Vector2:
	if str(build_zone.get("placementRole",""))=="ambush": return build_zone.position
	if str(build_zone.get("placementRole","ranged"))=="ground":
		var path_index: int=int(build_zone.pathIndex)
		var segment: int=int(build_zone.segmentIndex)
		return Geometry2D.get_closest_point_to_segment(p,paths[path_index].points[segment],paths[path_index].points[segment+1])
	return p

func _reserved_position(unit: Dictionary) -> Vector2:
	if GroundCombat.is_marching(str(unit.type)): return unit.position
	return unit.get("homePosition",unit.position)

func deployment_zone_active(zone: Dictionary) -> bool:
	return not bool(zone.get("unlockAfterCapture",false)) or (advance_mission.enabled and advance_mission.captured)

func _eligible_zone(p: Vector2, type_name: String = "") -> Dictionary:
	if p.x < 0.025 or p.x > 0.975 or p.y < 0.04 or p.y > 0.96:
		return {}
	var role: String = str(placement_contract(_placement_type(type_name)).placementRole)
	if role=="ambush" and not ground_combat.land_segment_safe(p,p): return {}
	for obstacle in config.get("obstacles",[]):
		if bool(obstacle.get("blockPlacement",false)) and p.distance_to(_point(obstacle)) <= float(obstacle.get("r",0.0)):
			return {}
	for build_zone in zones:
		if not deployment_zone_active(build_zone): continue
		if not _zone_accepts(build_zone,_placement_type(type_name)): continue
		if p.distance_to(build_zone.position) <= float(build_zone.get("r", 0.08))+.00001:
			if role=="ambush":
				if ground_combat.ambush_position_legal(build_zone.position,build_zone.entryPosition): return build_zone
				continue
			if str(build_zone.get("placementRole",""))=="ranged" and _on_road(p):
				continue
			var projected: Vector2 = _placement_position(p,build_zone)
			if not ground_combat.land_segment_safe(projected,projected,.008): continue
			if structure_placement_clear.is_valid() and not bool(structure_placement_clear.call(projected,.012)):
				continue
			if projected.distance_to(build_zone.position)>float(build_zone.get("r",.08))+.00001: continue
			if role=="ground" and str(config.get("theme",""))=="harbor":
				var water_data: Dictionary=config.get("water",{})
				var water: Rect2=Rect2(float(water_data.get("x",0)),float(water_data.get("y",0)),float(water_data.get("w",0)),float(water_data.get("h",0)))
				if water.has_point(projected): continue
				var landing: int=clampi(int(config.get("landingIndex",2)),0,ground_combat.cumulative[int(build_zone.pathIndex)].size()-1)
				if ground_combat.point_distance(int(build_zone.pathIndex),int(build_zone.segmentIndex),projected)<float(ground_combat.cumulative[int(build_zone.pathIndex)][landing]): continue
			for obstacle in config.get("obstacles",[]):
				if bool(obstacle.get("blockPlacement",false)) and projected.distance_to(_point(obstacle))<=float(obstacle.get("r",0)): return {}
			return build_zone
	return {}

func bind_terrain_navigation(segment_checker: Callable, placement_checker: Callable) -> void:
	enemy_lane_routes.clear()
	structure_placement_clear = placement_checker
	ground_combat.structure_segment_clear = segment_checker
	ground_combat.structure_placement_clear = placement_checker
	if config.is_empty():
		return
	# Refresh derived sites only. Resizing the view must not restart a battle,
	# discard queued recruits, or reset health, waves and existing troops.
	var previous_cursor: int = ground_combat.march_path_cursor
	ground_combat.reset()
	ground_combat.march_path_cursor = previous_cursor
	zones = zones.filter(func(zone: Dictionary) -> bool: return str(zone.get("placementRole","")) != "ambush")
	for site in ground_combat.build_ambush_sites():
		zones.append(site)
	_refresh_placement_hints()

func _on_road(p: Vector2) -> bool:
	for path in paths:
		for i in range(path.points.size() - 1):
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(p, path.points[i], path.points[i + 1])
			if p.distance_to(nearest) < 0.022:
				return true
	return false

func _hint_position_legal(p: Vector2, build_zone: Dictionary, type_name: String = "") -> bool:
	var role: String = str(placement_contract(_placement_type(type_name)).placementRole)
	if not _zone_accepts(build_zone,_placement_type(type_name)): return false
	if p.distance_to(build_zone.position) > float(build_zone.get("r", 0.08)) + 0.00001:
		return false
	if _eligible_zone(p,type_name)!=build_zone:
		return false
	var actual: Vector2 = _placement_position(p,build_zone)
	if int(build_zone.get("slotCapacity",0))>0:
		return not _placed_squad_positions({"type":_placement_type(type_name)},build_zone,actual,1).is_empty()
	for unit in units:
		if GroundCombat.is_marching(str(unit.type)): continue
		if _reserved_position(unit).distance_to(actual) < 0.0521:
			return false
	for job in recruitment_queue:
		if str(job.kind)!="marching" and job.position.distance_to(actual)<.0521: return false
	return true

func _zone_placement_hint(build_zone: Dictionary, type_name: String = "") -> Vector2:
	var role: String = str(placement_contract(_placement_type(type_name)).placementRole)
	if not deployment_zone_active(build_zone): return Vector2(-1,-1)
	if not _zone_accepts(build_zone,_placement_type(type_name)): return Vector2(-1,-1)
	var center: Vector2 = build_zone.position
	if int(build_zone.get("slotCapacity",0))>0:
		var free: Array=_placed_squad_positions({"type":_placement_type(type_name)},build_zone,center,1)
		return free[0] if not free.is_empty() else Vector2(-1,-1)
	if _hint_position_legal(center, build_zone,type_name):
		return _placement_position(center,build_zone)
	var radius: float = float(build_zone.get("r", 0.08))
	for ring in range(1, 6):
		var ring_radius: float = radius * ring / 5.0
		for step in range(24):
			var angle: float = TAU * step / 24.0
			var candidate: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
			if _hint_position_legal(candidate, build_zone,type_name):
				return _placement_position(candidate,build_zone)
	return Vector2(-1, -1)

func _refresh_placement_hints() -> void:
	var started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	placement_hints.clear()
	for build_zone in zones:
		# Keep index correspondence with zones for existing draw consumers.
		placement_hints.append(_zone_placement_hint(build_zone) if deployment_zone_active(build_zone) else Vector2(-1,-1))
	queue_redraw()
	if actor_overlay!=null:
		actor_overlay.queue_redraw()
	_profile_elapsed("placementHints",started,zones.size())

func _selected() -> Dictionary:
	for unit in units:
		if int(unit.id) == selected_id:
			return unit
	return {}

func _objective(id: String) -> Dictionary:
	for obj in objectives:
		if str(obj.id) == id:
			return obj
	return {}

func _index_enemies(context: Dictionary) -> Dictionary:
	var started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	var by_id: Dictionary={}
	var slots: Dictionary={}
	for slot in range(enemies.size()):
		var enemy: Dictionary=enemies[slot]
		var id: int=int(enemy.id)
		if by_id.has(id): continue
		by_id[id]=enemy
		slots[id]=slot
	var index: Dictionary={"generation":battle_generation,"count":enemies.size(),"actors":enemies,"byId":by_id,"slots":slots,"cohorts":{},"cohortsReady":false}
	context["enemyLookup"]=index
	_profile_elapsed("enemyLookupIndex",started,enemies.size())
	return index

func _enemy(id: int) -> Dictionary:
	if id<0: return {}
	var context: Dictionary=unit_skills.membership_query_context()
	if not context.is_empty():
		var index: Dictionary=context.get("enemyLookup",{})
		if index.is_empty() or int(index.generation)!=battle_generation or int(index.count)!=enemies.size() or not is_same(index.actors,enemies): index=_index_enemies(context)
		var cached: Dictionary=index.byId.get(id,{})
		if not cached.is_empty():
			var slot: int=int(index.slots.get(id,-1))
			# A callback may replace an entry without changing the array length.
			# Validate the requested live slot instead of rebuilding every ID on
			# each footstep/hit event. HP and positions remain live dictionaries.
			if slot>=0 and slot<enemies.size() and is_same(enemies[slot],cached) and int(cached.get("id",-1))==id: return cached
			return _index_enemies(context).byId.get(id,{})
		# A new ID can replace another entry in place. Do not cache misses.
		for enemy in enemies:
			if int(enemy.id)==id: return _index_enemies(context).byId.get(id,{})
		return {}
	for enemy in enemies:
		if int(enemy.id) == id:
			return enemy
	return {}

func _point(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Array:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))

func _screen(p: Vector2) -> Vector2:
	if _uses_world_projection():
		var projected: Vector2=render_projection_provider.model_to_field_point(p)
		return get_global_transform_with_canvas().affine_inverse()*render_projection_provider.get_global_transform_with_canvas()*projected
	return field_rect.position + view_point(p) * field_rect.size

func _unit_public(unit: Dictionary) -> Dictionary:
	if unit.is_empty():
		return {}
	var result: Dictionary = {"id":unit.id,"type":unit.type,"name":unit.name,"jp":unit.jp,"reading":unit.reading,"campaignLevel":unit.get("campaignLevel",1),"evolution":unit.get("evolution",0)}
	var stats: Dictionary = _stats(unit)
	result.merge(stats)
	result["dps"] = float(stats.damage) / float(stats.interval)
	var deployed: bool = unit.has("position")
	result["deployed"] = deployed
	result["preview"] = bool(unit.get("preview",false))
	result["paid"] = int(unit.get("paid",0))
	result["cost"] = int(unit.get("cost",unit.get("paid",0)))
	result["affordable"] = not bool(unit.get("preview",false)) or gold>=int(result.cost)
	result.merge(placement_contract(str(unit.type)))
	result["hp"] = float(unit.get("hp",stats.health))
	result["maxHp"] = float(unit.get("maxHp",stats.health))
	result.merge(unit_skills.public_state(unit),true)
	result["blockCount"] = int(unit.get("blockCount",0))
	result["blockCapacity"] = ground_combat.capacity(unit)
	result["hitRange"] = ground_combat.reach(unit) if GroundCombat.is_ground(str(unit.type)) else stats.range
	result["stanceKo"] = ground_combat.stance(unit)
	result["combatState"] = str(unit.get("combatState","guard"))
	result["recoverRemaining"] = float(unit.get("recoverRemaining",0))
	result["postName"] = str(unit.get("postName","사격 진지"))
	result["baseId"] = str(unit.get("baseId",""))
	result["pathId"] = str(unit.get("pathId",""))
	result["pathIndex"] = int(unit.get("postPathIndex",-1))
	result["basePosition"] = _normalized_position(unit.get("basePosition",unit.get("position",Vector2.ZERO)))
	result["spawnPosition"] = _normalized_position(unit.get("spawnPosition",unit.get("position",Vector2.ZERO)))
	result["routeDistance"] = float(unit.get("routeDistance",0))
	result["routeMin"] = float(unit.get("routeMin",0))
	result["routeMax"] = float(unit.get("routeMax",0))
	result["supportArmor"] = float(unit.get("supportArmor",0))
	result["supportedBy"] = int(unit.get("supportedBy",-1))
	result["productionJobId"]=int(unit.get("productionJobId",-1))
	result["gatherRemaining"]=float(unit.get("gatherRemaining",0))
	result["gatherGroupId"]=int(unit.get("gatherGroupId",0))
	result["gatherStartedAt"]=float(unit.get("gatherStartedAt",0.0))
	result["gatherDeadline"]=float(unit.get("gatherDeadline",0.0))
	result["supportPhase"]=str(unit.get("supportPhase",""))
	result["supportEnemyIds"]=unit.get("supportEnemyIds",[]).duplicate()
	result["supportPostId"]=str(unit.get("supportPostId",""))
	result["deploymentZoneId"]=str(unit.get("deploymentZoneId",""))
	result["deploymentSlotIndex"]=int(unit.get("deploymentSlotIndex",-1))
	result["emplacementShooter"]=bool(unit.get("emplacementShooter",false))
	result["deploymentPlacementRole"]=str(unit.get("deploymentPlacementRole",""))
	result["advanceFollowup"]=bool(unit.get("advanceFollowup",false))
	result["contactEnemyIds"]=unit.get("contactEnemyIds",[]).duplicate()
	result["unlimitedMeleeContacts"]=GroundCombat.is_marching(str(unit.type))
	result["supportCohortId"]=str(unit.get("supportCohortKey",""))
	result["supportLockedAt"]=float(unit.get("supportLockedAt",-1.0))
	result["supportEndReason"]=str(unit.get("supportEndReason",""))
	if str(unit.type)=="monk": result["supportRadius"]=float(stats.range)
	if str(unit.type)=="naginata":
		var zone: Dictionary=unit.get("guardZone",{})
		var public_zone: Dictionary={"center":_normalized_position(ground_combat._zone_point(zone.get("center",unit.get("homePosition",Vector2.ZERO)))),"radius":float(zone.get("radius",unit.get("guardRadius",.15))),"polygon":[]}
		for point in zone.get("polygon",[]): public_zone.polygon.append(_normalized_position(ground_combat._zone_point(point)))
		result.merge({"homePosition":_normalized_position(unit.get("homePosition",unit.get("position",Vector2.ZERO))),"guardRadius":float(unit.get("guardRadius",stats.range)),"defenseZone":public_zone,"recognitionRadius":float(stats.range),"occupancyRadius":float(unit.get("occupancyRadius",.008))},true)
	if GroundCombat.is_ambush(str(unit.type)):
		result.merge({"ambushSiteId":str(unit.get("postId","")),"homePosition":_normalized_position(unit.get("homePosition",unit.get("position",Vector2.ZERO))),"ambushRadius":float(stats.range)*2.0,"assassinationRadius":float(stats.range)*2.0,"priorityTargetId":int(unit.get("priorityTargetId",-1)),"consumable":true,"consumed":bool(unit.get("consumed",false)),"consumeReason":str(unit.get("consumeReason",""))})
	if str(unit.type)=="commander":
		result["chargeUnlocked"]=unit_skills.can_charge(unit)
		result["chargeDamage"] = float(stats.damage)*2.2 if bool(result.chargeUnlocked) else 0.0
		result["chargeInterval"] = float(stats.interval)*6.0
		result["chargeCooldownRemaining"] = float(unit.get("chargeCooldown",0))
	var frame: Dictionary = animation_frame_data(unit)
	result["animation"] = frame.state
	result["animationFrame"] = frame.frame
	result["animationRow"] = frame.row
	result["animationClock"] = frame.clock
	result["animationSource"] = frame.source
	result["animationRegion"] = frame.region
	if unit.has("position"):
		result["x"] = unit.position.x
		result["y"] = unit.position.y
	return result

func snapshot() -> Dictionary:
	var scope: Dictionary=unit_skills.begin_query_scope(true)
	var result: Dictionary=_build_snapshot()
	unit_skills.end_query_scope(scope)
	return result

func hud_snapshot() -> Dictionary:
	# The HUD needs counts and the selected actor, not animation/path/skill
	# dictionaries for every combatant. Keep snapshot() complete for observers.
	var scope: Dictionary=unit_skills.begin_query_scope(true)
	var public_objectives: Array=[]
	var hp: int=0
	var maximum: int=0
	for objective in objectives:
		public_objectives.append({"id":objective.id,"label":objective.get("label",""),"hp":objective.hp,"maxHp":objective.maxHp,"x":objective.position.x,"y":objective.position.y})
		hp+=int(objective.hp)
		maximum+=int(objective.maxHp)
	var strong_enemy_present: bool=false
	for enemy in enemies:
		if str(enemy.get("kind","")) in ["commander","heavy"]:
			strong_enemy_present=true
			break
	var jobs: Array=[]
	for job in recruitment_queue:
		jobs.append({"id":int(job.id),"type":str(job.type),"name":str(job.name),"kind":str(job.kind),"pathIndex":int(job.pathIndex),"position":_normalized_position(job.position),"cost":int(job.cost),"quantity":int(job.quantity),"remainingSeconds":float(job.remainingSeconds),"totalSeconds":float(job.totalSeconds),"status":str(job.status)})
	var result: Dictionary={
		"mapId":str(config.get("id","")),"wave":wave,"totalWaves":total_waves,
		"gold":gold,"unitCount":units.size(),"enemyCount":_living_enemy_count(),
		"hp":hp,"maxHp":maximum,"objectives":public_objectives,
		"selected":_unit_public(_selected()),"pending":_unit_public(pending),
		"paused":paused,"betweenWaves":between_waves,"waiting":between_waves,
		"victory":victory,"defeat":finished and not victory,"finished":finished,"running":running,
		"remainingSpawns":spawn_queue.size()+ambush_warnings.size(),"speed":speed,"elapsed":elapsed,
		"battleMode":"cycles","battleMinutes":0,"battleTargetSeconds":0.0,"battleElapsedSeconds":elapsed,
		"completedCycles":completed_wave,"completedWave":completed_wave,"cyclesCleared":_attack_cycles_cleared(),
		"strongEnemyPresent":strong_enemy_present,"recruitmentQueue":jobs
	}
	result["advanceMission"]=advance_mission.snapshot()
	unit_skills.end_query_scope(scope)
	return result

func _build_snapshot() -> Dictionary:
	var started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	var public_objectives: Array = []
	var public_units: Array = []
	var public_enemies: Array = []
	var public_deaths: Array = []
	var hp: int = 0
	var max_hp: int = 0
	for obj in objectives:
		public_objectives.append({"id":obj.id,"label":obj.get("label", ""),"hp":obj.hp,"maxHp":obj.maxHp,"x":obj.position.x,"y":obj.position.y})
		hp += int(obj.hp)
		max_hp += int(obj.maxHp)
	for unit in units:
		public_units.append(_unit_public(unit))
	for enemy in enemies:
		var frame: Dictionary = animation_frame_data(enemy,0.0,true)
		var public: Dictionary={"id":enemy.id,"kind":enemy.kind,"hp":enemy.hp,"maxHp":enemy.maxHp,"x":enemy.position.x,"y":enemy.position.y,"pathIndex":enemy.pathIndex,"animation":frame.state,"animationFrame":frame.frame,"animationSource":frame.source,"blockedBy":enemy.get("blockedBy",-1),"stationaryEnemy":bool(enemy.get("stationaryEnemy",false)),"fortification":bool(enemy.get("fortification",false)),"formationPattern":str(enemy.get("formationPattern","skirmish")),"formationGroup":str(enemy.get("formationGroup","")),"formationLane":int(enemy.get("formationLane",0)),"formationRank":int(enemy.get("formationRank",0))}
		public.merge(enemy_role_contract(str(enemy.kind),enemy),true)
		public["assaultZoneId"]=str(enemy.get("assaultZoneId",""))
		public["advanceGuard"]=bool(enemy.get("advanceGuard",false))
		public["contactUnitIds"]=enemy.get("contactUnitIds",[]).duplicate()
		public["counterTargetIds"]=enemy.get("counterPlans",{}).keys()
		public["counterAttackId"]=str(enemy.get("counterPlan",{}).get("attackId",""))
		public["counterTargetCursor"]=int(enemy.get("counterTargetCursor",-1))
		public["counterCooldown"]=float(enemy.get("attackCooldown",0.0))
		public["transportKind"] = str(enemy.get("transportKind",""))
		public["transportActive"] = bool(enemy.get("transportActive",false))
		public.merge({"pointIndex":int(enemy.pointIndex),"spawnPathIndex":int(enemy.get("spawnPathIndex",enemy.pathIndex)),"routeDistance":float(enemy.get("routeProgress",ground_combat.enemy_distance(enemy))),"routeProjection":ground_combat.enemy_distance(enemy),"ingressActive":bool(enemy.get("ingressActive",false)),"ambushEntranceId":str(enemy.get("ambushEntranceId","")),"targetId":int(enemy.get("stationaryTargetId",-1)),"hunterState":"ingress" if bool(enemy.get("ingressActive",false)) else "returning" if bool(enemy.get("hunterReturning",false)) else "engaged" if int(enemy.get("stationaryTargetId",-1))>=0 else "route"},true)
		public.merge(unit_skills.enemy_state(enemy),true)
		if enemy.get("historicalCommander") is Dictionary:
			public["historicalCommander"]=enemy.historicalCommander.duplicate(true)
			public.historicalCommander.merge({"hp":float(enemy.hp),"maxHp":float(enemy.maxHp),"enemyId":int(enemy.id)},true)
		if bool(enemy.get("transportActive",false)): public["hunterState"] = "transport"
		public_enemies.append(public)
	for actor in death_actors:
		var friendly: bool = bool(actor.get("friendly",false))
		var frame: Dictionary = animation_frame_data(actor,0.0,not friendly)
		public_deaths.append({"id":actor.id,"kind":actor.kind,"type":str(actor.get("type",actor.kind)),"friendly":friendly,"evolution":int(actor.get("evolution",0)),"x":actor.position.x,"y":actor.position.y,"animationFrame":frame.frame,"animationClock":frame.clock,"animationSource":frame.source,"sailing":actor.get("sailing",false),"fortification":bool(actor.get("fortification",false)),"stationaryEnemy":bool(actor.get("stationaryEnemy",false)),"hp":0.0,"maxHp":float(actor.get("maxHp",0))})
	var result: Dictionary = {"mapId":config.get("id", ""),"theme":config.get("theme", ""),"wave":wave,"totalWaves":total_waves,"gold":gold,"recruitCost":config.get("recruitCost", 60),"unitLimit":null,"hp":hp,"maxHp":max_hp,"objectives":public_objectives,"units":public_units,"selected":_unit_public(_selected()),"pending":_unit_public(pending),"paused":paused,"betweenWaves":between_waves,"waiting":between_waves,"victory":victory,"defeat":finished and not victory,"finished":finished,"running":running,"kills":kills,"enemyCount":enemies.size(),"enemies":public_enemies,"deathActors":public_deaths,"remainingSpawns":spawn_queue.size(),"speed":speed,"elapsed":elapsed,"bridge":bridge_index,"bridgeCooldown":bridge_cooldown,"storm":storm_active,"animationTime":animation_time,"animationAssets":animated_textures.keys(),"traitName":_trait().get("nameKO", ""),"activeAuras":active_auras(),"learningSupports":learning_supports.duplicate(true),"routeCycle":bool(_trait().get("cycleRoutes", false)),"tacticsName":config.get("tactics",{}).get("nameKo",""),"tacticsDescription":config.get("tactics",{}).get("descriptionKo","")}
	result.merge({"battleMinutes":0,"battleTargetSeconds":0.0,"battleElapsedSeconds":elapsed,"battleRemainingSeconds":0.0,"battleMode":"cycles","waveRemainingSeconds":0.0,"battleRefillCount":0,"completedCycles":completed_wave,"completedWave":completed_wave,"cyclesCleared":_attack_cycles_cleared(),"enemyCount":_living_enemy_count(),"remainingSpawns":spawn_queue.size()+ambush_warnings.size()})
	result["battleSupports"]=battle_support.snapshot()
	result["advanceMission"]=advance_mission.snapshot()
	result["learningRewardReceipts"]=battle_support.receipt_snapshot()
	result["emplacementProtectionActive"]=emplacement_protection_active()
	result["protectedUnitTypes"]=["archer","gunner","monk","naginata"] if emplacement_protection_active() else []
	var recruit_costs: Dictionary={}
	for definition in recruit_catalog.values() if roster_configured else UNIT_TYPES:
		if not bool(definition.get("active",true)): continue
		recruit_costs[str(definition.id)]=recruit_cost(str(definition.id))
	result["recruitCosts"]=recruit_costs
	var bases: Array=[]
	for base in ground_combat.march_bases:
		bases.append({"baseId":str(base.baseId),"baseNameKo":str(base.baseNameKo),"pathIndex":int(base.pathIndex),"pathId":str(base.pathId),"objectiveId":str(base.objectiveId),"x":base.position.x,"y":base.position.y,"baseDistance":float(base.baseDistance),"routeMin":float(base.routeMin),"routeMax":float(base.routeMax)})
	result["marchBases"]=bases
	result["presentationMirrored"]=presentation_mirrored
	result["fieldMarkers"]=field_markers()
	result["productionWorldIndicators"]=true
	result["productionPreviews"]=production_preview_snapshot()
	result["shootingPositions"]=shooting_position_snapshot()
	result["trainingOnly"]=bool(config.get("trainingOnly",false))
	result["enemyRoles"]=[enemy_role_contract("raider"),enemy_role_contract("enemy_samurai")]
	var warnings: Array=[]
	for warning in ambush_warnings:
		warnings.append({"id":int(warning.id),"kind":str(warning.kind),"x":warning.position.x,"y":warning.position.y,"pathIndex":int(warning.pathIndex),"remainingSeconds":float(warning.remainingSeconds),"entranceId":str(warning.entranceId),"combatRole":ENEMY_EMPLACEMENT_ROLE})
	result["ambushWarnings"]=warnings
	var sites: Array=[]
	for site in ground_combat.ambush_sites:
		sites.append({"id":str(site.id),"nameKo":str(site.nameKo),"x":site.position.x,"y":site.position.y,"pathIndex":int(site.pathIndex),"r":float(site.r),"terrain":str(site.terrain),"placementRole":"ambush"})
	result["ambushSites"]=sites
	var jobs: Array=[]
	for job in recruitment_queue:
		jobs.append({"id":int(job.id),"type":str(job.type),"name":str(job.name),"kind":str(job.kind),"pathIndex":int(job.pathIndex),"position":_normalized_position(job.position),"cost":int(job.cost),"quantity":int(job.quantity),"remainingSeconds":float(job.remainingSeconds),"totalSeconds":float(job.totalSeconds),"status":str(job.status)})
	result["recruitmentQueue"]=jobs
	result["recruitmentCapacity"]=null
	result["emplacementAssaultPlan"]=emplacement_assault_plan()
	result["campaignScenario"]={"stageId":str(config.get("id","")),"missionMode":str(config.get("missionMode","")),"enemyProfile":str(EnemyModeProfiles.profile_for(config).get("id","")),"combatEnabled":bool(EnemyModeProfiles.profile_for(config).get("combatEnabled",true)),"implementationStatus":config.get("scenario",{}).get("implementationStatus",{})}
	result["enemyModeProfile"]=EnemyModeProfiles.profile_for(config).duplicate(true)
	result["combatMode"]=str(config.get("combatMode","defense"))
	result["attackPattern"]=attack_pattern
	result["attackPatternKo"]={"formation":"대형 진입","mounted_vanguard":"기마 선행 · 보병 후속","rush":"분산 난입","skirmish":"소규모 접근"}.get(attack_pattern,"접근")
	_profile_elapsed("snapshot",started,units.size()+enemies.size())
	return result

func actor_states() -> Array:
	var started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	var scope: Dictionary=unit_skills.begin_query_scope(true)
	var result: Array=_build_actor_states()
	unit_skills.end_query_scope(scope)
	_profile_elapsed("actorStates",started,result.size())
	return result

func _build_actor_states() -> Array:
	var states: Array = []
	states.append_array(battle_support.actor_states())
	for unit in units:
		states.append({"id":unit.id,"type":unit.type,"friendly":true,"dead":false,"x":unit.position.x,"y":unit.position.y,"aimX":unit.aim.x,"aimY":unit.aim.y,"animation":unit.get("animation","idle"),"animationClock":unit.get("animationClock",0.0),"animationPhase":unit.get("animationPhase",0.0),"motionTime":animation_time,"campaignLevel":unit.get("campaignLevel",1),"evolution":unit.get("evolution",0),"attackDuration":unit.get("attackDuration",_animation_duration("attack")),"hitClock":unit.get("hitClock",0.0),"sailing":false,"deploying":unit.get("deploying",false),"combatState":unit.get("combatState","guard"),"hp":unit.get("hp",0),"maxHp":unit.get("maxHp",0)})
		states.back().merge(unit_skills.public_state(unit),true)
	for enemy in enemies:
		if not _enemy_visible(enemy):
			continue
		var model_type: String=str(enemy.kind) if str(enemy.kind) in ["enemy_archer","enemy_gunner","enemy_cavalry","enemy_samurai"] else "enemy_heavy" if str(enemy.kind) in ["shield","heavy","commander"] else "enemy_light"
		states.append({"id":enemy.id,"type":model_type,"kind":enemy.kind,"friendly":false,"hostile":true,"side":"enemy","dead":false,"x":enemy.position.x,"y":enemy.position.y,"aimX":enemy.aim.x,"aimY":enemy.aim.y,"animation":enemy.get("animation","walk"),"animationClock":enemy.get("animationClock",0.0),"animationPhase":enemy.get("animationPhase",0.0),"motionTime":animation_time,"hitClock":enemy.get("hitClock",0.0),"sailing":_sailing_visual(enemy),"fortification":bool(enemy.get("fortification",false)),"stationaryEnemy":bool(enemy.get("stationaryEnemy",false)),"ingressActive":bool(enemy.get("ingressActive",false)),"hp":float(enemy.hp),"maxHp":float(enemy.maxHp)})
		states.back().merge(enemy_role_contract(str(enemy.kind),enemy),true)
		states.back()["transportKind"] = str(enemy.get("transportKind",""))
		states.back()["transportActive"] = bool(enemy.get("transportActive",false))
		states.back()["hunterState"] = "transport" if bool(enemy.get("transportActive",false)) else "ingress" if bool(enemy.get("ingressActive",false)) else "returning" if bool(enemy.get("hunterReturning",false)) else "approach" if int(enemy.get("stationaryTargetId",-1))>=0 else "route"
		states.back().merge(unit_skills.enemy_state(enemy),true)
	for actor in death_actors:
		var friendly: bool=bool(actor.get("friendly",false))
		var actor_type: String=str(actor.get("type","spear")) if friendly else str(actor.kind) if str(actor.kind) in ["enemy_archer","enemy_gunner","enemy_cavalry","enemy_samurai"] else "enemy_heavy" if str(actor.kind) in ["shield","heavy","commander"] else "enemy_light"
		states.append({"id":actor.id,"type":actor_type,"kind":actor.kind,"friendly":friendly,"hostile":not friendly,"side":"friendly" if friendly else "enemy","dead":true,"evolution":int(actor.get("evolution",0)),"campaignLevel":int(actor.get("campaignLevel",1)),"x":actor.position.x,"y":actor.position.y,"aimX":actor.aim.x,"aimY":actor.aim.y,"animation":"death","animationClock":actor.animationClock,"animationPhase":0.0,"motionTime":animation_time,"hitClock":0.0,"sailing":actor.get("sailing",false),"fortification":bool(actor.get("fortification",false)),"stationaryEnemy":bool(actor.get("stationaryEnemy",false)),"hp":0.0,"maxHp":float(actor.get("maxHp",0))})
	return states

func _sailing_visual(enemy: Dictionary) -> bool:
	if bool(enemy.get("transportActive",false)) and str(enemy.get("transportKind",""))=="boat": return true
	if str(config.get("theme","")) != "harbor":
		return false
	var landing: int = int(config.get("landingIndex",2))
	var next_point: int = int(enemy.pointIndex)
	if next_point < landing:
		return true
	if next_point > landing:
		return false
	var points: Array = paths[int(enemy.pathIndex)].points
	if landing < 1 or landing >= points.size():
		return false
	var start: Vector2 = points[landing-1]
	var end: Vector2 = points[landing]
	var fraction: float = start.distance_to(enemy.position)/maxf(0.0001,start.distance_to(end))
	# The landing node is on the pier. The final fifth of its approach belongs
	# to the disembarkation stance; movement and the route remain unchanged.
	return fraction < float(config.get("landingVisualFraction",0.80))

func _emit_state() -> void:
	var started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	if not state_changed.get_connections().is_empty():
		var state: Dictionary=snapshot()
		var suspended: Dictionary=unit_skills.suspend_query_scopes()
		state_changed.emit(state)
		unit_skills.resume_query_scopes(suspended)
		enemy_lane_routes.clear()
	if not hud_state_changed.get_connections().is_empty():
		var hud_state: Dictionary=hud_snapshot()
		var hud_suspended: Dictionary=unit_skills.suspend_query_scopes()
		hud_state_changed.emit(hud_state)
		unit_skills.resume_query_scopes(hud_suspended)
		enemy_lane_routes.clear()
	# This includes synchronous UI subscribers, so HQ can distinguish
	# snapshot construction from the full state publication cost.
	_profile_elapsed("statePublication",started)

func _normalized_position(position: Vector2) -> Dictionary:
	return {"x":position.x,"y":position.y}

func _base_archetype(objective: Dictionary = {}) -> String:
	if bool(objective.get("mobile",false)):
		return "command_post"
	match str(objective.get("presentation","")):
		"castle_gate": return "castle_gate"
		"field_camp": return "command_post"
		"defense_line": return "barracks"
	var terrain_key: String=str(config.get("historicalBattlefield",{}).get("terrain",{}).get("key",""))
	var theme: String=str(config.get("theme","forest"))
	if theme in ["convoy","night","harbor"]: return "command_post"
	if theme in ["siege","town"] or "castle" in terrain_key or "fort" in terrain_key or "gate" in terrain_key: return "castle_gate"
	return "barracks"

func field_markers() -> Array:
	var markers: Array=[]
	for objective in objectives:
		markers.append({"id":"objective:"+str(objective.id),"markerKind":"objective","labelKo":"아군 기지","objectiveId":str(objective.id),"x":objective.position.x,"y":objective.position.y,"archetype":_base_archetype(objective),"presentation":"supply_cart" if bool(objective.get("mobile",false)) else str(objective.get("presentation","castle_gate")),"mobile":bool(objective.get("mobile",false)),"hp":int(objective.hp),"maxHp":int(objective.maxHp),"flagColor":"257dd2","outlineColor":"e9c676"})
	for base in ground_combat.march_bases:
		markers.append({"id":str(base.baseId),"markerKind":"march_base","labelKo":"출진 %d" % (int(base.pathIndex)+1),"objectiveId":str(base.objectiveId),"pathIndex":int(base.pathIndex),"x":base.position.x,"y":base.position.y,"archetype":_base_archetype(_objective(str(base.objectiveId))),"mobile":false,"flagColor":"257dd2","outlineColor":"e9c676"})
	return markers

func field_marker_layouts() -> Array:
	var layouts: Array=[]
	var label_bounds: Array=[]
	var font: Font=ui_font if ui_font!=null else ThemeDB.fallback_font
	for marker in field_markers():
		# Each rendered gate already represents its shared production origin.
		# Keep route data, but avoid stacking drawn toy buildings over the gate.
		if three_d_enabled and str(marker.markerKind)=="march_base": continue
		var center: Vector2=_screen(_point(marker))
		var objective: bool=str(marker.markerKind)=="objective"
		var scale: float=clampf(field_rect.size.y/620.0,.80,1.15)*(1.0 if objective else .76)
		var font_size: int=20 if objective else 18
		var label_size: Vector2=Vector2(ceilf(font.get_string_size(str(marker.labelKo),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)+12,ceilf(font.get_height(font_size))+8)
		var model_rect: Rect2=Rect2(center+Vector2(-38,-78)*scale,Vector2(76,96)*scale)
		var candidates: Array=[center+Vector2(-label_size.x*.5,22*scale),center+Vector2(42*scale,-label_size.y*.5),center+Vector2(-42*scale-label_size.x,-label_size.y*.5)]
		for offset in range(1,5): candidates.append(center+Vector2(-label_size.x*.5,22*scale+float(offset)*(label_size.y+10)))
		candidates.append(center+Vector2(-label_size.x*.5,-84*scale-label_size.y))
		var label_rect: Rect2=Rect2(candidates[0],label_size)
		for candidate in candidates:
			var rect: Rect2=Rect2(candidate,label_size)
			if objective: rect.size.y+=14
			if not field_rect.grow(-3).encloses(rect): continue
			var overlap: bool=false
			for occupied in label_bounds:
				if rect.grow(3).intersects(occupied): overlap=true;break
			if not overlap: label_rect=Rect2(candidate,label_size);break
		label_rect.position.x=clampf(label_rect.position.x,field_rect.position.x+3,field_rect.end.x-label_size.x-3)
		label_rect.position.y=clampf(label_rect.position.y,field_rect.position.y+3,field_rect.end.y-label_size.y-(17 if objective else 3))
		var health_space: Rect2=Rect2(Vector2(label_rect.position.x,label_rect.end.y+2),Vector2(label_rect.size.x,HEALTHBAR_ANCHOR_HEIGHT)) if objective else Rect2()
		var health_rect: Rect2=Rect2(Vector2(health_space.position.x,health_space.get_center().y-HEALTHBAR_HEIGHT*.5),Vector2(health_space.size.x,HEALTHBAR_HEIGHT)) if objective else Rect2()
		label_bounds.append(label_rect.merge(health_space) if objective else label_rect)
		layouts.append({"marker":marker,"center":center,"scale":scale,"fontSize":font_size,"labelRect":label_rect,"labelBaseline":label_rect.position+Vector2(6,4+font.get_ascent(font_size)),"modelRect":model_rect,"healthRect":health_rect,"flagRect":Rect2(center+Vector2(-9,-76)*scale,Vector2(35,31)*scale)})
	return layouts

func _marker_polygon(canvas: Node2D, center: Vector2, scale: float, offsets: Array, fill: Color, outline: Color = Color("d9ba79")) -> void:
	var points: PackedVector2Array=PackedVector2Array()
	for offset in offsets: points.append(center+Vector2(offset)*scale)
	canvas.draw_colored_polygon(points,fill)
	points.append(points[0])
	canvas.draw_polyline(points,outline,1.6,true)

func _draw_field_marker_model(canvas: Node2D, layout: Dictionary) -> void:
	if three_d_enabled: return
	var marker: Dictionary=layout.marker
	var p: Vector2=layout.center
	var scale: float=float(layout.scale)
	var gold: Color=Color(str(marker.outlineColor))
	var ink: Color=Color("14232c")
	var footprint: PackedVector2Array=PackedVector2Array()
	for index in range(33):
		var angle: float=TAU*float(index)/32.0
		footprint.append(p+Vector2(cos(angle)*38,sin(angle)*13)*scale)
	canvas.draw_colored_polygon(footprint,Color(.035,.065,.09,.79))
	canvas.draw_polyline(footprint,Color(.10,.17,.21,.95),5.0,true)
	canvas.draw_polyline(footprint,gold,2.6,true)
	if bool(marker.mobile):
		for wheel in [-18,18]: canvas.draw_circle(p+Vector2(wheel,8)*scale,6*scale,ink)
		canvas.draw_rect(Rect2(p+Vector2(-28,-22)*scale,Vector2(56,26)*scale),Color("866640"))
		_marker_polygon(canvas,p,scale,[Vector2(-32,-22),Vector2(-24,-36),Vector2(24,-36),Vector2(32,-22)],Color("bcc4b0"))
	else:
		match str(marker.archetype):
				"castle_gate":
					canvas.draw_rect(Rect2(p+Vector2(-34,-8)*scale,Vector2(68,17)*scale),Color("7c8889"))
					canvas.draw_rect(Rect2(p+Vector2(-27,-33)*scale,Vector2(54,34)*scale),Color("a79266"))
					canvas.draw_rect(Rect2(p+Vector2(-10,-25)*scale,Vector2(20,28)*scale),ink)
					for x in [-24,-16,16,24]: canvas.draw_line(p+Vector2(x,-30)*scale,p+Vector2(x,-2)*scale,Color("4a4031"),2.0*scale,true)
					_marker_polygon(canvas,p,scale,[Vector2(-37,-35),Vector2(0,-49),Vector2(37,-35),Vector2(32,-29),Vector2(-32,-29)],Color("253740"))
				"command_post":
					canvas.draw_rect(Rect2(p+Vector2(-29,-26)*scale,Vector2(58,31)*scale),Color("d3c1a0"))
					canvas.draw_rect(Rect2(p+Vector2(-10,-21)*scale,Vector2(20,26)*scale),ink)
					_marker_polygon(canvas,p,scale,[Vector2(-35,-27),Vector2(0,-42),Vector2(35,-27),Vector2(29,-22),Vector2(-29,-22)],Color("33618a"))
					for x in [-29,29]: canvas.draw_line(p+Vector2(x,-26)*scale,p+Vector2(x,8)*scale,Color("876b41"),3.0*scale,true)
				_:
					canvas.draw_rect(Rect2(p+Vector2(-27,-23)*scale,Vector2(54,27)*scale),Color("ae9163"))
					_marker_polygon(canvas,p,scale,[Vector2(-34,-23),Vector2(0,-44),Vector2(34,-23)],Color("495b66"))
					canvas.draw_rect(Rect2(p+Vector2(-8,-20)*scale,Vector2(16,25)*scale),ink)
					for x in [-23,-15,15,23]: canvas.draw_line(p+Vector2(x,-20)*scale,p+Vector2(x,3)*scale,Color("64503a"),1.8*scale,true)
	canvas.draw_line(p+Vector2(-9,4)*scale,p+Vector2(-9,-76)*scale,ink,5.0*scale,true)
	canvas.draw_line(p+Vector2(-9,4)*scale,p+Vector2(-9,-76)*scale,gold,2.6*scale,true)
	_marker_polygon(canvas,p,scale,[Vector2(-9,-76),Vector2(26,-73),Vector2(26,-46),Vector2(-9,-49)],Color(str(marker.flagColor)),gold)
	canvas.draw_circle(p+Vector2(8,-61)*scale,6.5*scale,gold)
	canvas.draw_circle(p+Vector2(8,-61)*scale,3.5*scale,Color(str(marker.flagColor)))
	# The small threshold identifies the exact world anchor, not a production timer.
	canvas.draw_line(p+Vector2(-6,0)*scale,p+Vector2(6,0)*scale,Color("84cfff"),2.5*scale,true)

func _draw_field_markers(canvas: Node2D) -> void:
	if painted_field.is_ready():
		for objective in objectives:
			var point: Vector2 = _screen(objective.position)+Vector2(-38,-48)*field_rect.size.y/620.0
			var bar: Rect2 = Rect2(point,Vector2(84,5))
			canvas.draw_rect(bar,Color("17272d"))
			canvas.draw_rect(Rect2(bar.position+Vector2.ONE,Vector2(82*clampf(float(objective.hp)/maxf(1,float(objective.maxHp)),0,1),3)),Color("48b5df"))
		return
	var layouts: Array=field_marker_layouts()
	for layout in layouts: _draw_field_marker_model(canvas,layout)
	var font: Font=ui_font if ui_font!=null else ThemeDB.fallback_font
	for layout in layouts:
		var marker: Dictionary=layout.marker
		var rect: Rect2=layout.labelRect
		var nearest: Vector2=rect.get_center().clamp(rect.position,rect.end)
		canvas.draw_line(layout.center,nearest,Color(.77,.88,.97,.65),1.2,true)
		canvas.draw_string_outline(font,layout.labelBaseline,str(marker.labelKo),HORIZONTAL_ALIGNMENT_LEFT,-1,int(layout.fontSize),3,Color("101410"))
		canvas.draw_string(font,layout.labelBaseline,str(marker.labelKo),HORIZONTAL_ALIGNMENT_LEFT,-1,int(layout.fontSize),Color("fff3c7"))
		if str(marker.markerKind)=="objective":
			var health: Rect2=layout.healthRect
			canvas.draw_rect(health,Color(HEALTHBAR_BACKGROUND_COLOR))
			canvas.draw_rect(Rect2(health.position+Vector2(1,0),Vector2((health.size.x-2)*clampf(float(marker.hp)/maxf(1,float(marker.maxHp)),0,1),HEALTHBAR_HEIGHT)),Color(HEALTHBAR_FRIENDLY_COLOR))

func _weapon(type_name: String) -> String:
	return {"archer":"bow","gunner":"matchlock","spear":"spear","samurai":"katana","naginata":"naginata","monk":"staff","ninja":"dagger","commander":"charge","raider":"spear","runner":"spear","shield":"spear","heavy":"katana","enemy_archer":"bow","enemy_gunner":"matchlock","enemy_cavalry":"charge"}.get(type_name,"katana")

func _combat_event(type: String, actor: Dictionary, victim: Dictionary = {}, extra: Dictionary = {}) -> void:
	if type=="shot" and not actor.has("kind") and not victim.is_empty() and not can_friendly_target_enemy(actor,victim): return
	var side: String = "enemy" if actor.has("kind") else "friendly"
	var unit_type: String = str(actor.get("type",actor.get("kind","")))
	var data: Dictionary = {"side":side,"unitType":unit_type,"enemyKind":str(actor.get("kind","")),"weapon":_weapon(unit_type),"actorId":actor.get("id",-1)}
	if side=="enemy":
		data["sailing"] = bool(actor.sailing) if actor.has("sailing") else _sailing_visual(actor)
		data.merge(enemy_role_contract(unit_type,actor),true)
		if actor.has("combatRole"): data["combatRole"]=str(actor.combatRole)
		if unit_type=="commander": data["weapon"]="katana"
	if actor.has("position"):
		data["position"] = _normalized_position(actor.position)
		data["sourcePosition"] = _normalized_position(actor.position)
	if not victim.is_empty():
		data["victimId"] = victim.get("id",-1)
		data["victimSide"] = "enemy" if victim.has("kind") else "friendly"
		data["victimPosition"] = _normalized_position(victim.position)
		data["victimType"] = str(victim.get("type",victim.get("kind","")))
		if victim.has("kind"): data["victimSailing"]=_sailing_visual(victim)
	for key in extra: data[key] = extra[key]
	_event(type,str(data.get("message","")),data)

func _track_footstep(actor: Dictionary, previous: Vector2, side: String) -> void:
	if actor.position.distance_to(previous)<.000001 or (side=="enemy" and _sailing_visual(actor)): return
	var distance: float = float(actor.get("footstepDistance",0))+actor.position.distance_to(previous)
	var step_length: float = .042 if str(actor.get("type",""))=="commander" else .022
	if distance>=step_length:
		_combat_event("footstep",actor,{}, {"side":side})
		distance = fmod(distance,step_length)
	actor["footstepDistance"] = distance

func _event(type: String, message: String, payload: Dictionary = {}) -> void:
	var data: Dictionary = {"type":type,"action":{"recruited":"recruit","placed":"deploy","wave":"wavebegin"}.get(type,type),"eventId":next_event_id,"mapId":str(config.get("id","")),"wave":wave,"time":elapsed}
	next_event_id += 1
	for key in payload: data[key] = payload[key]
	if not message.is_empty(): data["message"] = message
	presentation_event.emit(data)
	if not game_event.get_connections().is_empty():
		var suspended: Dictionary=unit_skills.suspend_query_scopes()
		game_event.emit(data)
		unit_skills.resume_query_scopes(suspended)
		enemy_lane_routes.clear()

func _draw() -> void:
	var started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	var scope: Dictionary=unit_skills.begin_query_scope(true)
	_draw_contents()
	unit_skills.end_query_scope(scope)
	_profile_elapsed("fieldDraw",started,units.size()+enemies.size())

func _draw_contents() -> void:
	if field_rect.size.x <= 1.0 or config.is_empty():
		return
	if not three_d_enabled:
		if painted_field.is_ready():
			painted_field.draw_to(self,field_rect,presentation_mirrored)
		elif background != null:
			var image_rect: Rect2=Rect2(Vector2(field_rect.end.x,field_rect.position.y),Vector2(-field_rect.size.x,field_rect.size.y)) if presentation_mirrored else field_rect
			draw_texture_rect(background, image_rect, false)
		else:
			draw_rect(field_rect, Color(str(config.get("color", "#334333"))))
		if not painted_field.is_ready(): draw_rect(field_rect, Color(0.03, 0.04, 0.03, 0.11))
	if not painted_field.is_ready(): _draw_roads()
	_draw_trait_auras()
	if not three_d_enabled:
		_draw_zones(self)
		_draw_advance_mission_marker()
	if str(config.get("theme", "")) == "night":
		_draw_torches()
	render_sprite_cursor = 0
	if not three_d_enabled and not painted_actors.is_ready():
		var actors: Array = render_actor_list()
		if actor_material != null:
			actor_material.set_shader_parameter("saturation",float(visual_profile().get("actorSaturation",0.70)))
		for actor in actors:
			if bool(actor.get("dead", false)):
				_draw_death_actor(actor.data)
			elif actor.friendly:
				var unit: Dictionary = actor.data
				var pulse: float = 1.0 + sin(float(unit.get("pulseClock",0.0))*PI/0.8)*0.065
				_draw_soldier(_screen(actor.position),Color(str(_read_stats(unit).color)),str(unit.type),unit.aim,float(actor.sizeFactor)*pulse,0.0,true,unit,float(actor.phaseOffset))
			else:
				_draw_enemy(actor.data)
		for data in battle_support.actor_states():
			var supporter: Dictionary=data.duplicate(true)
			supporter.position=Vector2(float(data.x),float(data.y))

			_draw_soldier(_screen(supporter.position),Color("79a7a8"),"matchlock",Vector2(data.aimX,data.aimY),1.0,float(data.animationClock),true,supporter)
	if not three_d_enabled and painted_actors.is_ready():
		painted_actors.render(self,self)
		if painted_actors.has_method("draw_production_previews"): painted_actors.draw_production_previews(self,field_rect,production_preview_snapshot(true),presentation_mirrored)
	for index in range(render_sprite_cursor,render_sprites.size()):
		render_sprites[index].visible = false
	if actor_overlay != null:
		actor_overlay.queue_redraw()
	if storm_active:
		_draw_storm()
	_draw_edge_markers()

func _depth_scale(normalized_y: float) -> float:
	var perspective: Dictionary = visual_profile().get("perspective", {})
	return lerpf(float(perspective.get("farScale",0.74)),float(perspective.get("nearScale",1.08)),clampf(normalized_y,0.0,1.0))

func sprite_geometry(ground: Vector2, size_factor: float = 1.0) -> Dictionary:
	var normalized: Vector2 = (ground-field_rect.position)/field_rect.size
	var perspective: Dictionary = visual_profile().get("perspective", {})
	var size: float = 35.0 * size_factor * _depth_scale(normalized.y) * clampf(field_rect.size.y/620.0,0.75,1.25)
	var dimensions: Vector2 = Vector2(size,size*float(perspective.get("verticalCompression",0.88)))
	var anchor_data: Dictionary = animation_manifest.get("anchor", {})
	var anchor: Vector2 = Vector2(float(anchor_data.get("x",0.5)),float(anchor_data.get("y",float(animation_manifest.get("baselineY",228))/float(animation_manifest.get("cellHeight",256)))))
	return {"size":dimensions,"anchor":anchor,"offset":-dimensions*anchor,"ground":ground,"depth":normalized.y}

func render_actor_list() -> Array:
	var actors: Array = []
	for unit in units:
		var ground: Vector2 = unit.position
		var size: float = float(sprite_geometry(_screen(ground)).size.x)
		var seed_offset: float = sin(float(unit.id)*2.17)
		var offsets: Array = [Vector2(-0.32,0.08),Vector2(0.34,0.24),Vector2(0.03,-0.22)]
		for member in range(3):
			var offset: Vector2 = offsets[member]*size
			offset += Vector2(sin(float(unit.id)*1.37+member)*1.4,cos(float(unit.id)*1.91+member)*0.9)
			if str(unit.get("animation","idle")) == "walk":
				offset.y += maxf(0.0,0.35-float(unit.get("animationClock",0.0)))*9.0
			var member_position: Vector2 = ground+offset/field_rect.size
			var phase: float = [0.17,0.37,0.0][member]+seed_offset*0.015
			if str(unit.get("animation","idle")) == "attack":
				phase = [0.018,0.036,0.0][member]
			actors.append({"data":unit,"friendly":true,"position":member_position,"member":member,"sizeFactor":[0.93,0.96,1.0][member],"phaseOffset":phase})
	for enemy in enemies:
		if _enemy_visible(enemy):
			actors.append({"data":enemy,"friendly":false,"position":enemy.position})
	for actor in death_actors:
		actors.append({"data":actor,"friendly":bool(actor.get("friendly",false)),"dead":true,"position":actor.position})
	actors.sort_custom(func(a, b):
		if not is_equal_approx(float(a.position.y),float(b.position.y)):
			return a.position.y < b.position.y
		return int(a.data.id) < int(b.data.id)
	)
	return actors

func _draw_roads() -> void:
	for index in range(paths.size()):
		var path: Dictionary = paths[index]
		var points_screen: PackedVector2Array = PackedVector2Array()
		for point_norm in path.points:
			points_screen.append(_screen(point_norm))
		if not objectives.is_empty() and str(config.get("theme", "")) == "convoy":
			points_screen[-1] = _screen(objectives[0].position)
		var opacity: float = float(visual_profile().get("roadOpacity",0.16))
		var route_color: Color = Color(0.80,0.73,0.57,opacity)
		if not pending.is_empty():
			draw_polyline(points_screen,route_color,2.0,true)
		for i in range(points_screen.size() - 1):
			var direction: Vector2 = (points_screen[i + 1] - points_screen[i]).normalized()
			var midpoint: Vector2 = points_screen[i].lerp(points_screen[i + 1], 0.5)
			var arrow_color: Color = Color(0.91,0.85,0.68,opacity*1.4)
			draw_line(midpoint - direction.rotated(0.6) * 4.0, midpoint,arrow_color,1.0,true)
			draw_line(midpoint - direction.rotated(-0.6) * 4.0, midpoint,arrow_color,1.0,true)
	if str(config.get("theme", "")) == "river":
		for index in range(config.get("bridges", []).size()):
			var bridge: Dictionary = config.bridges[index]
			var normalized_rect: Rect2=BattlefieldPresentation.rect_to_view(Rect2(_point(bridge),Vector2(float(bridge.w),float(bridge.h))),presentation_mirrored)
			var rect: Rect2 = Rect2(field_rect.position+normalized_rect.position*field_rect.size,normalized_rect.size*field_rect.size)
			var bridge_color: Color = Color("b9aa87") if index == bridge_index else Color("64635a")
			bridge_color.a = 0.30 if not pending.is_empty() else 0.10
			draw_rect(rect,bridge_color,false,1.0)

func _draw_advance_mission_marker() -> void:
	if not advance_mission.enabled: return
	var center: Vector2=advance_mission.capture_point
	var radius: float=advance_mission.capture_radius
	var color: Color=Color(.46,.78,.58,.62) if advance_mission.captured else Color(.88,.72,.38,.52)
	_draw_world_circle(center,radius,Color(0,0,0,0),color,self,1.6)
	if advance_mission.captured or advance_mission.hold_seconds<=0.0: return
	var progress: float=clampf(advance_mission.hold_seconds/advance_mission.hold_required,0.0,1.0)
	var arc: PackedVector2Array=PackedVector2Array()
	var segments: int=maxi(2,ceili(48.0*progress))
	for index in range(segments+1):
		var angle: float=-PI*.5+TAU*progress*float(index)/float(segments)
		arc.append(_screen(center+Vector2(cos(angle),sin(angle))*radius))
	draw_polyline(arc,Color(.94,.79,.43,.9),3.0,true)

func _draw_zones(target: Node2D = null) -> void:
	var canvas: Node2D=target if target!=null else self
	for index in range(zones.size()):
		var build_zone: Dictionary = zones[index]
		if not deployment_zone_active(build_zone): continue
		if str(build_zone.get("placementRole",""))=="ambush" and (pending.is_empty() or str(pending.type)!="ninja"): continue
		if not pending.is_empty() and str(build_zone.get("placementRole","ranged"))!=str(placement_contract(str(pending.type)).placementRole):
			continue
		var hint_position: Vector2 = placement_hints[index] if index < placement_hints.size() else Vector2(-1, -1)
		var has_slot: bool = hint_position.x >= 0.0
		if has_slot and bool(pending.get("preview",false)):
			has_slot=bool(placement_preview(hint_position).valid)
		var opacity: float = 0.48 if not pending.is_empty() else 0.045
		if not has_slot:
			opacity *= 0.25
		var ground: bool=str(build_zone.get("placementRole","ranged"))=="ground"
		var zone_color: Color=Color("b997ff") if str(build_zone.get("placementRole",""))=="ambush" else Color("73e5d2") if ground else Color("ffda87")
		var fill: Color=zone_color
		fill.a=opacity*.2
		var outline: Color=zone_color
		outline.a=.86 if not pending.is_empty() and has_slot else opacity
		if not pending.is_empty() and has_slot:
			_draw_world_circle(build_zone.position,float(build_zone.r),Color(0,0,0,0),Color(.03,.04,.04,.58),canvas,3.6)
		_draw_world_circle(build_zone.position,float(build_zone.r),fill,outline,canvas,2.0 if not pending.is_empty() and has_slot else 1.2)
		if not pending.is_empty() and has_slot:
			var center: Vector2 = _screen(hint_position)
			canvas.draw_circle(center,10,Color(0.04,0.065,0.055,.84))
			canvas.draw_arc(center,12,0,TAU,33,Color(zone_color,.75),1.3,true)
			zone_color.a=1.0
			canvas.draw_line(center + Vector2(-7,0),center + Vector2(7,0),zone_color,2.5)
			canvas.draw_line(center + Vector2(0,-7),center + Vector2(0,7),zone_color,2.5)
	_draw_placement_ghost(canvas)

func _draw_placement_ghost(canvas: Node2D) -> void:
	if pending.is_empty() or not placement_cursor_visible or not input_enabled or finished or ui_deployment_active:
		return
	var preview: Dictionary = placement_preview(placement_cursor)
	var valid: bool = bool(preview.valid)
	var actual: Vector2 = _point(preview.position)
	if not actual.is_finite() or not field_rect.has_point(_screen(actual)): return
	var p: Vector2 = _screen(actual)
	var color: Color = Color("b997ff") if str(preview.placementRole)=="ambush" else Color("73e5d2") if str(preview.placementRole)=="ground" else Color("ffda87")
	if not valid: color=Color("f28c79")
	var footprint: PackedVector2Array = PackedVector2Array()
	for index in range(33):
		var angle: float = TAU*index/32.0
		footprint.append(p+Vector2(cos(angle)*22,sin(angle)*8))
	canvas.draw_colored_polygon(footprint,Color(.025,.04,.03,.72))
	canvas.draw_polyline(footprint,color,2.4,true)
	var requested_screen: Vector2 = _screen(placement_cursor)
	if valid and requested_screen.distance_to(p)>3:
		canvas.draw_line(requested_screen,p,Color(color,.65),1.0,true)
		canvas.draw_circle(requested_screen,2.0,Color(color,.65))
	if not three_d_enabled and painted_actors.is_ready():
		painted_actors.draw_actor(canvas,{"type":str(pending.type),"animation":"idle"},p,true,painted_actors.body_height_screen*field_rect.size.y/620.0,Vector2(1,-1))
	elif not (external_placement_ghost and three_d_enabled):
		var key: String = str(pending.type)+"-"+str(pending.evolution)
		if not placement_art.has(key):
			var source: Dictionary = StandingPortrait.resolve_source(str(pending.type),int(pending.evolution))
			var texture: AtlasTexture = StandingPortrait.first_frame_texture(str(pending.type),int(pending.evolution))
			var anchor: Dictionary = source.get("anchor",{"x":.5,"y":.890625})
			if not source.get("frameAnchors",[]).is_empty(): anchor=source.frameAnchors[0]
			placement_art[key] = {"texture":texture,"anchor":Vector2(float(anchor.get("x",.5)),float(anchor.get("y",.890625)))}
		var art: Dictionary = placement_art[key]
		if art.texture!=null:
			var height: float = 52.0*_depth_scale(actual.y)*clampf(field_rect.size.y/620.0,.8,1.25)*(.70 if three_d_enabled else 1.0)
			var size: Vector2 = Vector2(height,height)
			canvas.draw_texture_rect(art.texture,Rect2(p-size*art.anchor,size),false,Color(1,1,1,.62 if valid else .30))
		else:
			canvas.draw_circle(p+Vector2(0,-20),4,Color(color,.55))
			canvas.draw_line(p+Vector2(0,-15),p+Vector2(0,-5),Color(color,.55),6.0)
	if valid:
		canvas.draw_line(p+Vector2(-6,0),p+Vector2(-1,5),Color("f3efda"),2.4,true)
		canvas.draw_line(p+Vector2(-1,5),p+Vector2(8,-5),Color("f3efda"),2.4,true)
	else:
		canvas.draw_line(p+Vector2(-7,-6),p+Vector2(7,6),Color(.04,.03,.02,.9),4.5,true)
		canvas.draw_line(p+Vector2(7,-6),p+Vector2(-7,6),Color(.04,.03,.02,.9),4.5,true)
		canvas.draw_line(p+Vector2(-7,-6),p+Vector2(7,6),color,2.4,true)
		canvas.draw_line(p+Vector2(7,-6),p+Vector2(-7,6),color,2.4,true)
	if ui_font!=null:
		var label: String = "배치 %d" % int(preview.cost) if valid else "배치 불가"
		var label_width: float = ui_font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		var label_position: Vector2 = Vector2(clampf(p.x-label_width*.5,field_rect.position.x+4,field_rect.end.x-label_width-4),clampf(p.y+22,field_rect.position.y+ui_font.get_ascent(16)+4,field_rect.end.y-ui_font.get_descent(16)-4))
		canvas.draw_string_outline(ui_font,label_position,label,HORIZONTAL_ALIGNMENT_LEFT,-1,16,2,Color(.03,.04,.03,.90))
		canvas.draw_string(ui_font,label_position,label,HORIZONTAL_ALIGNMENT_LEFT,-1,16,color)

func _cache_circle_floor() -> void:
	circle_floor_faces.clear()
	var geometry: Variant=config.get("worldGeometry",{})
	if not geometry is Dictionary or geometry.is_empty(): return
	var bounds: Variant=geometry.get("simulationBounds",{})
	if not bounds is Dictionary: return
	for key in ["x","z","width","depth"]:
		var value: Variant=bounds.get(key)
		if not (value is int or value is float) or not is_finite(float(value)): return
	var width: float=float(bounds.get("width",0))
	var depth: float=float(bounds.get("depth",0))
	if width<=0 or depth<=0: return
	var extents: Vector2=Vector2(width,depth)
	if not extents.is_finite() or extents.x<=0 or extents.y<=0: return
	width=extents.x; depth=extents.y
	var vertices: Variant=geometry.get("vertices",[])
	var indices: Variant=geometry.get("triangles",[])
	if not vertices is Array or not indices is Array or indices.size()%3!=0: return
	var origin: Vector2=Vector2(float(bounds.x),float(bounds.z))
	var faces: Array=[]
	for offset in range(0,indices.size()-2,3):
		var polygon: PackedVector2Array=PackedVector2Array()
		for corner in range(3):
			var raw_index: Variant=indices[offset+corner]
			if not (raw_index is int or raw_index is float) or not is_finite(float(raw_index)) or float(raw_index)!=floorf(float(raw_index)): return
			var index: int=int(raw_index)
			if index<0 or index>=vertices.size(): return
			var vertex: Variant=vertices[index]
			if not vertex is Dictionary: return
			for key in ["x","z"]:
				var value: Variant=vertex.get(key)
				if not (value is int or value is float) or not is_finite(float(value)): return
			# Match the authored mesh's float32 X/Z and scalar normalization.
			var world_xz: Vector2=Vector2(float(vertex.x),float(vertex.z))
			var point: Vector2=Vector2((world_xz.x-origin.x)/width,(world_xz.y-origin.y)/depth)
			if not point.is_finite(): return
			polygon.append(point)
		var twice_area: float=absf((float(polygon[1].x)-float(polygon[0].x))*(float(polygon[2].y)-float(polygon[0].y))-(float(polygon[1].y)-float(polygon[0].y))*(float(polygon[2].x)-float(polygon[0].x)))
		var longest_edge: float=maxf(polygon[0].distance_to(polygon[1]),maxf(polygon[1].distance_to(polygon[2]),polygon[2].distance_to(polygon[0])))
		if twice_area==0 or longest_edge==0: return
		# Native clipping rounds on a 1e-5 grid. Thin authored faces need direct
		# half-plane clipping so their visible range pieces cannot collapse.
		faces.append({"polygon":polygon,"rect":Rect2(polygon[0],Vector2.ZERO).expand(polygon[1]).expand(polygon[2]),"thin":twice_area/longest_edge<=.00008,"winding":signf((float(polygon[1].x)-float(polygon[0].x))*(float(polygon[2].y)-float(polygon[0].y))-(float(polygon[1].y)-float(polygon[0].y))*(float(polygon[2].x)-float(polygon[0].x)))})
	circle_floor_faces=faces

func _circle_points_on_face(points: PackedVector2Array, face: PackedVector2Array) -> PackedVector2Array:
	# Geometry2D's clipping grid can move an edge beyond the original triangle.
	# Restore only those displayed points to that same authored face; physics,
	# placement and navigation tolerances remain independent of this correction.
	var a: Vector2=face[0]; var b: Vector2=face[1]; var c: Vector2=face[2]
	var ab_x: float=float(b.x)-float(a.x); var ab_y: float=float(b.y)-float(a.y)
	var ac_x: float=float(c.x)-float(a.x); var ac_y: float=float(c.y)-float(a.y)
	var denominator: float=ab_x*ac_y-ab_y*ac_x
	if not is_finite(denominator) or denominator==0: return PackedVector2Array()
	var world_projection: bool=_uses_world_projection()
	var restored: PackedVector2Array=PackedVector2Array()
	for point in points:
		var ap_x: float=float(point.x)-float(a.x); var ap_y: float=float(point.y)-float(a.y)
		var second: float=(ap_x*ac_y-ap_y*ac_x)/denominator
		var third: float=(ab_x*ap_y-ab_y*ap_x)/denominator
		var first: float=1-second-third
		if first>=0 and second>=0 and third>=0 and (not world_projection or render_projection_provider.model_to_field_point(point).is_finite()):
			restored.append(point)
			continue
		# Euclidean edge projection stays local even for thin triangles; clamped
		# barycentric weights could move a near-edge point far along that edge.
		var nearest: Vector2=point
		var nearest_distance: float=INF
		var geometric_distance: float=INF
		var candidates: Array=[]
		for edge in range(3):
			var start: Vector2=face[edge]; var end: Vector2=face[(edge+1)%3]
			var edge_x: float=float(end.x)-float(start.x); var edge_y: float=float(end.y)-float(start.y)
			var length_squared: float=edge_x*edge_x+edge_y*edge_y
			if length_squared==0: continue
			var along: float=clampf(((float(point.x)-float(start.x))*edge_x+(float(point.y)-float(start.y))*edge_y)/length_squared,0,1)
			var projected: Vector2=Vector2(float(start.x)+edge_x*along,float(start.y)+edge_y*along)
			var distance: float=point.distance_squared_to(projected)
			geometric_distance=minf(geometric_distance,distance)
			candidates.append({"point":projected,"distance":distance})
		# Recheck float32 reconstruction through the real height-backed provider.
		# A different far edge must not replace an unrepresentable nearby point.
		var local_limit: float=pow(sqrt(geometric_distance)+.000001,2)
		for candidate in candidates:
			if float(candidate.distance)>local_limit: continue
			if world_projection and not render_projection_provider.model_to_field_point(candidate.point).is_finite(): continue
			if float(candidate.distance)<nearest_distance:
				nearest=candidate.point; nearest_distance=float(candidate.distance)
		if not is_finite(nearest_distance): return PackedVector2Array()
		restored.append(nearest)
	return restored

func _circle_edge_distance(point: Vector2, face: Dictionary, edge: int) -> float:
	var a: Vector2=face.polygon[edge]; var b: Vector2=face.polygon[(edge+1)%3]
	return float(face.winding)*((float(b.x)-float(a.x))*(float(point.y)-float(a.y))-(float(b.y)-float(a.y))*(float(point.x)-float(a.x)))

func _circle_interpolate(a: Vector2, b: Vector2, fraction: float) -> Vector2:
	return Vector2(float(a.x)+(float(b.x)-float(a.x))*fraction,float(a.y)+(float(b.y)-float(a.y))*fraction)

func _circle_clip_thin_disk(disk: PackedVector2Array, face: Dictionary) -> PackedVector2Array:
	var polygon: PackedVector2Array=disk
	for edge in range(3):
		if polygon.is_empty(): break
		var clipped: PackedVector2Array=PackedVector2Array()
		var previous: Vector2=polygon[polygon.size()-1]
		var previous_distance: float=_circle_edge_distance(previous,face,edge)
		for point in polygon:
			var distance: float=_circle_edge_distance(point,face,edge)
			if (distance>=0)!=(previous_distance>=0):
				clipped.append(_circle_interpolate(previous,point,previous_distance/(previous_distance-distance)))
			if distance>=0: clipped.append(point)
			previous=point; previous_distance=distance
		polygon=clipped
	return _circle_points_on_face(polygon,face.polygon)

func _circle_clip_thin_arc(a: Vector2, b: Vector2, face: Dictionary) -> PackedVector2Array:
	var lower: float=0; var upper: float=1
	for edge in range(3):
		var start: float=_circle_edge_distance(a,face,edge)
		var end: float=_circle_edge_distance(b,face,edge)
		if start<0 and end<0: return PackedVector2Array()
		if start<0: lower=maxf(lower,start/(start-end))
		elif end<0: upper=minf(upper,start/(start-end))
		if lower>=upper: return PackedVector2Array()
	return _circle_points_on_face(PackedVector2Array([_circle_interpolate(a,b,lower),_circle_interpolate(a,b,upper)]),face.polygon)

func _world_circle_surface_layout(center: Vector2, radius: float, include_fill: bool = true) -> Dictionary:
	var result: Dictionary={"fills":[],"arcs":[]}
	if not center.is_finite() or not is_finite(radius) or radius<=0: return result
	var perimeter: PackedVector2Array=PackedVector2Array()
	for index in range(49):
		var angle: float = TAU * index / 48.0
		perimeter.append(center+Vector2(cos(angle),sin(angle))*radius)
	var disk: PackedVector2Array=perimeter.slice(0,48)
	var bounds: Rect2=Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2)
	for face in circle_floor_faces:
		if not bounds.intersects(face.rect,true): continue
		if bool(face.thin):
			if include_fill:
				var polygon: PackedVector2Array=_circle_clip_thin_disk(disk,face)
				if polygon.size()>=3: result.fills.append(polygon)
			for index in range(perimeter.size()-1):
				var arc: PackedVector2Array=_circle_clip_thin_arc(perimeter[index],perimeter[index+1],face)
				if arc.size()>=2: result.arcs.append(arc)
			continue
		# Clip the disk and its open perimeter independently. Floor boundaries
		# close only filled regions; they must never become range-outline chords.
		if include_fill:
			for polygon in Geometry2D.intersect_polygons(disk,face.polygon):
				result.fills.append(_circle_points_on_face(polygon,face.polygon))
		for arc in Geometry2D.intersect_polyline_with_polygon(perimeter,face.polygon):
			result.arcs.append(_circle_points_on_face(arc,face.polygon))
	return result

func _project_circle_points(model_points: PackedVector2Array) -> PackedVector2Array:
	var projected: PackedVector2Array=PackedVector2Array()
	for point in model_points:
		var pixel: Vector2=_screen(point)
		if not pixel.is_finite(): return PackedVector2Array()
		projected.append(pixel)
	return projected

func _prepare_circle_fill(points: PackedVector2Array) -> PackedVector2Array:
	if points.size()<3: return PackedVector2Array()
	var origin: Vector2=points[0]
	var local_points: PackedVector2Array=PackedVector2Array()
	for point in points:
		if not point.is_finite(): return PackedVector2Array()
		var local: Vector2=point-origin
		if local_points.is_empty() or local!=local_points[local_points.size()-1]: local_points.append(local)
	if local_points.size()>1 and local_points[0]==local_points[local_points.size()-1]: local_points.remove_at(local_points.size()-1)
	# Small clipped pieces at large screen coordinates can lose their signed
	# area in canvas triangulation. Translate for tessellation, then restore
	# that exact origin in the draw command; no range area is scaled or hidden.
	if local_points.size()<3 or Geometry2D.triangulate_polygon(local_points).is_empty(): return PackedVector2Array()
	return local_points

func _draw_world_circle(center: Vector2, radius: float, fill: Color, outline: Color, target: Node2D = null, line_width: float = 1.2) -> void:
	var canvas: Node2D=target if target!=null else self
	if _uses_world_projection():
		var layout: Dictionary=_world_circle_surface_layout(center,radius,fill.a>0)
		for polygon in layout.fills:
			var projected: PackedVector2Array=_project_circle_points(polygon)
			var local_points: PackedVector2Array=_prepare_circle_fill(projected)
			if local_points.size()>=3:
				canvas.draw_set_transform(projected[0])
				canvas.draw_colored_polygon(local_points,fill)
				canvas.draw_set_transform(Vector2.ZERO)
		for arc in layout.arcs:
			var projected: PackedVector2Array=_project_circle_points(arc)
			if projected.size()>=2: canvas.draw_polyline(projected,outline,line_width,true)
		return
	var points: PackedVector2Array=PackedVector2Array()
	for index in range(49):
		var angle: float=TAU*index/48.0
		points.append(_screen(center+Vector2(cos(angle),sin(angle))*radius))
	canvas.draw_colored_polygon(points,fill)
	canvas.draw_polyline(points,outline,line_width,true)

func enemy_role_marker_geometry(enemy: Dictionary) -> Dictionary:
	var scale: float=_depth_scale(float(enemy.position.y))*(three_d_actor_scale if three_d_enabled else 1.0)
	var health: Rect2=healthbar_layout(enemy,false).rect
	var role: Dictionary=enemy_role_contract(str(enemy.kind))
	return {"center":Vector2(health.position.x-9,health.get_center().y),"radius":clampf(5.5*scale,4.5,7.0),"shape":str(role.roleMarker),"color":str(role.roleColor),"combatRole":str(role.combatRole)}

func visible_field_rect_local() -> Rect2:
	# Layout is fixed within a synchronous simulation phase, unlike actor HP
	# and buffs. Signal callbacks and layout setters invalidate this cache.
	var context: Dictionary=unit_skills.membership_query_context()
	if not context.is_empty() and context.has("visibleFieldRect"): return context.visibleFieldRect
	var result: Rect2=_calculate_visible_field_rect_local()
	if not context.is_empty(): context["visibleFieldRect"]=result
	return result

func _calculate_visible_field_rect_local() -> Rect2:
	var visible: Rect2=field_rect
	var inverse: Transform2D=get_global_transform_with_canvas().affine_inverse()
	var ancestor: Node=get_parent()
	while ancestor!=null:
		if ancestor is Control and ancestor.clip_contents:
			var transform: Transform2D=inverse*ancestor.get_global_transform_with_canvas()
			var first: Vector2=transform*Vector2.ZERO
			var local: Rect2=Rect2(first,Vector2.ZERO)
			for corner in [Vector2(ancestor.size.x,0),ancestor.size,Vector2(0,ancestor.size.y)]: local=local.expand(transform*corner)
			visible=visible.intersection(local)
		ancestor=ancestor.get_parent()
	return visible

func healthbar_layout(actor: Dictionary, friendly: bool) -> Dictionary:
	var context: Dictionary=unit_skills.read_query_context()
	var actor_id: int=int(actor.get("id",-1))
	if context.is_empty() or actor_id<0: return _calculate_healthbar_layout(actor,friendly)
	if not context.has("healthLayouts"): context["healthLayouts"]={true:{},false:{}}
	var cache: Dictionary=context.healthLayouts[friendly]
	if cache.has(actor_id):
		var record: Dictionary=cache[actor_id]
		if is_same(record.actor,actor): return record.layout.duplicate(true)
	var result: Dictionary=_calculate_healthbar_layout(actor,friendly)
	cache[actor_id]={"actor":actor,"layout":result.duplicate(true)}
	return result

func _calculate_healthbar_layout(actor: Dictionary, friendly: bool) -> Dictionary:
	var anchor: Vector2=_screen(actor.position)
	var projected: bool=false
	var flags: Dictionary={}
	if three_d_enabled and is_instance_valid(render_projection_provider):
		var actual: Dictionary=render_projection_provider.health_anchor_for(int(actor.id))
		if not actual.is_empty():
			anchor=get_global_transform_with_canvas().affine_inverse()*(render_projection_provider.get_global_transform_with_canvas()*actual.headPosition)
			flags=actual.get("flags",{})
			projected=true
	if not projected:
		if not three_d_enabled and painted_actors.is_ready():
			anchor+=painted_actors.actor_visual_offset(actor,painted_actors.body_height_screen*clampf(field_rect.size.y/620.0,.65,1.5))
		anchor.y-=(painted_actors.body_height_screen*field_rect.size.y/620.0 if not three_d_enabled and painted_actors.is_ready() else float(sprite_geometry(_screen(actor.position)).size.y))+5.0
		flags=unit_skills.public_state(actor).get("flags",{}) if friendly else unit_skills.enemy_state(actor).get("flags",{})
	var width: float=58.0 if str(actor.get("type",actor.get("kind",""))) in ["commander","enemy_cavalry"] else 46.0
	if not three_d_enabled and painted_actors.is_ready(): width = 26.0 if friendly else 23.0
	# Retain the previous bar centre, edge clamping and name-label reservation.
	# Fixed shooters use an inset six-pixel bar; foot/head anchors stay fixed.
	var fixed_shooter: bool=friendly and (str(actor.get("type",""))=="archer" or bool(actor.get("emplacementShooter",false)))
	var bar_height: float=6.0 if fixed_shooter else HEALTHBAR_HEIGHT
	var frame_height: float=maxf(HEALTHBAR_ANCHOR_HEIGHT,bar_height+4.0)
	var anchor_rect: Rect2=Rect2(Vector2(anchor.x-width*.5,anchor.y-frame_height),Vector2(width,frame_height))
	var visible: Rect2=visible_field_rect_local()
	if visible.has_point(_screen(actor.position)) and visible.size.x>width+25 and visible.size.y>40:
		anchor_rect.position.x=clampf(anchor_rect.position.x,visible.position.x+13,visible.end.x-width-3)
		anchor_rect.position.y=clampf(anchor_rect.position.y,visible.position.y+3,visible.end.y-anchor_rect.size.y-3)
	var rect: Rect2=Rect2(Vector2(anchor_rect.position.x,anchor_rect.get_center().y-bar_height*.5),Vector2(width,bar_height))
	var ratio: float=clampf(float(actor.get("hp",0))/maxf(1,float(actor.get("maxHp",0))),0,1)
	return {"anchor":anchor,"anchorRect":anchor_rect,"rect":rect,"fillRect":Rect2(rect.position+Vector2(1,1 if fixed_shooter else 0),Vector2((width-2)*ratio,bar_height-2 if fixed_shooter else bar_height)),"fixedShooter":fixed_shooter,"ratio":ratio,"color":HEALTHBAR_FRIENDLY_COLOR if friendly else HEALTHBAR_HOSTILE_COLOR,"backgroundColor":HEALTHBAR_BACKGROUND_COLOR,"text":"","projected":projected,"flags":flags,"clamped":rect.get_center().distance_to(Vector2(anchor.x,anchor.y-HEALTHBAR_ANCHOR_HEIGHT*.5))>.01}

func _draw_actor_health(actor: Dictionary, friendly: bool, canvas: Node2D) -> void:
	var layout: Dictionary=healthbar_layout(actor,friendly)
	var rect: Rect2=layout.rect
	if bool(layout.clamped): canvas.draw_line(layout.anchor,Vector2(rect.get_center().x,rect.end.y),Color(.91,.95,.96,.75),1.3,true)
	canvas.draw_rect(rect,Color(str(layout.backgroundColor)))
	canvas.draw_rect(layout.fillRect,Color(str(layout.color)))
	var status_index: int=0
	for status in ["burning","poisoned","armorWeakened","invulnerable","talisman"]:
		if not bool(layout.flags.get(status,false)): continue
		var color: Color=Color("f4b352") if status=="burning" else Color("a4d87d") if status=="poisoned" else Color("f3e69e") if status=="invulnerable" else Color("bb9bf0") if status=="armorWeakened" else Color("84ebda")
		var point: Vector2=Vector2(rect.end.x+5+status_index*7,rect.get_center().y)
		canvas.draw_circle(point,3.4,Color("14212a"))
		canvas.draw_circle(point,2.3,color)
		status_index+=1

var selected_name_text_cache: Dictionary = {}

func set_floating_label_style(style: StyleBox) -> void:
	floating_label_style=style
	selected_name_text_cache.clear()
	queue_redraw()
	if actor_overlay!=null: actor_overlay.queue_redraw()

func _floating_label_padding() -> Vector4:
	if floating_label_style==null: return Vector4(8,8,8,8)
	return Vector4(maxf(8.0,floating_label_style.get_content_margin(SIDE_LEFT)),maxf(8.0,floating_label_style.get_content_margin(SIDE_TOP)),maxf(8.0,floating_label_style.get_content_margin(SIDE_RIGHT)),maxf(8.0,floating_label_style.get_content_margin(SIDE_BOTTOM)))

func _selected_name_text_layout(unit: Dictionary) -> Dictionary:
	var font: Font = GameFonts.japanese()
	var jp: String=str(unit.get("jp",""))
	var reading: String=str(unit.get("reading",""))
	var definition: Dictionary = recruit_catalog.get(str(unit.get("type","")),{})
	var meaning: String=str(unit.get("ko",unit.get("name",definition.get("name",""))))
	var key: String = str(font.get_instance_id())+":"+jp+":"+reading+":"+meaning+":"+JSON.stringify(unit.get("parts",[]))
	if selected_name_text_cache.has(key): return selected_name_text_cache[key]
	var label: Control = RubyText.new()
	label.font = font
	label.ink = Color("fff9ec")
	label.reading_ink = Color("fff9ec")
	label.meaning_ink = Color("fff9ec")
	label.reading_group_palette[0] = Color("ffe6a3")
	label.reading_group_palette[1] = Color("9fe7ff")
	label.size = Vector2(592,100)
	label.set_word({"jp":jp,"reading":reading,"ko":meaning,"parts":unit.get("parts",[])},20,true)
	var measured: Dictionary = label.get_text_layout()
	var bounds: Rect2 = Rect2()
	var first: bool = true
	for run in measured.runs:
		var run_font: Font=label.reading_font if str(run.role)=="reading" else label.meaning_font if str(run.role)=="meaning" else font
		var glyph_size: Vector2=run_font.get_string_size(str(run.text),HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size))
		var glyph_bounds: Rect2=Rect2(run.position-Vector2(0,run_font.get_ascent(int(run.size))),Vector2(glyph_size.x,run_font.get_height(int(run.size))))
		var actual_bounds: Rect2=run.bounds.merge(glyph_bounds).grow(3.0)
		bounds=actual_bounds if first else bounds.merge(actual_bounds)
		first=false
	var padding: Vector4=_floating_label_padding()
	var inset: Vector2=Vector2(padding.x,padding.y)
	var runs: Array = []
	for source_run in measured.runs:
		var run: Dictionary = source_run.duplicate()
		run["position"] = run.position-bounds.position+inset
		run["bounds"] = Rect2(run.bounds.position-bounds.position+inset,run.bounds.size)
		run["font"] = label.reading_font if str(run.role)=="reading" else label.meaning_font if str(run.role)=="meaning" else font
		if str(run.role)=="meaning": run["color"]=label.meaning_ink
		runs.append(run)
	var result: Dictionary = {"runs":runs,"size":bounds.size+Vector2(padding.x+padding.z,padding.y+padding.w),"padding":padding,"colouredGroups":measured.colouredGroups}
	selected_name_text_cache[key] = result
	label.free()
	return result

func floating_word_label_layout(word: Dictionary, anchor: Vector2) -> Dictionary:
	var layout: Dictionary=_selected_name_text_layout(word)
	var size: Vector2=layout.size
	var visible: Rect2=visible_field_rect_local()
	var rect: Rect2=Rect2(anchor-Vector2(size.x*.5,size.y),size)
	if visible.size.x>size.x+6: rect.position.x=clampf(rect.position.x,visible.position.x+3,visible.end.x-size.x-3)
	if visible.size.y>size.y+6: rect.position.y=clampf(rect.position.y,visible.position.y+3,visible.end.y-size.y-3)
	var runs: Array=[]
	for source in layout.runs:
		var run: Dictionary=source.duplicate()
		run.position=source.position+rect.position
		run.bounds=Rect2(source.bounds.position+rect.position,source.bounds.size)
		runs.append(run)
	return {"rect":rect,"runs":runs,"padding":layout.padding,"style":floating_label_style}

func selected_unit_label_layout(unit: Dictionary) -> Dictionary:
	var text_layout: Dictionary = _selected_name_text_layout(unit)
	var label_size: Vector2 = text_layout.size
	var health: Rect2=healthbar_layout(unit,true).anchorRect
	var visible: Rect2=visible_field_rect_local()
	var name_top: float=health.position.y-3
	var rect: Rect2=Rect2(Vector2(health.get_center().x-label_size.x*.5,name_top-label_size.y-6),label_size)
	if rect.position.y<visible.position.y+3: rect.position.y=health.end.y+7
	if visible.size.x>label_size.x+6: rect.position.x=clampf(rect.position.x,visible.position.x+3,visible.end.x-label_size.x-3)
	if visible.size.y>label_size.y+6: rect.position.y=clampf(rect.position.y,visible.position.y+3,visible.end.y-label_size.y-3)
	var runs: Array = []
	var jp_baseline: Vector2 = rect.position
	var reading_baseline: Vector2 = rect.position
	var found_body: bool = false
	var found_reading: bool = false
	for source_run in text_layout.runs:
		var run: Dictionary = source_run.duplicate()
		run["position"] = run.position+rect.position
		run["bounds"] = Rect2(run.bounds.position+rect.position,run.bounds.size)
		if str(run.role)=="body" and not found_body: jp_baseline=run.position;found_body=true
		if str(run.role)=="reading" and not found_reading: reading_baseline=run.position;found_reading=true
		runs.append(run)
	return {"rect":rect,"runs":runs,"jpBaseline":jp_baseline,"readingBaseline":reading_baseline,"fontSize":20,"readingSize":16,"colouredGroups":text_layout.colouredGroups}

func _draw_enemy_role_marker(enemy: Dictionary, canvas: Node2D) -> void:
	var marker: Dictionary=enemy_role_marker_geometry(enemy)
	var p: Vector2=marker.center
	var radius: float=float(marker.radius)
	if not field_rect.grow(-radius-1).has_point(p): return
	var ink: Color=Color("1d1716")
	var color: Color=Color(str(marker.color))
	if str(marker.shape)=="target":
		canvas.draw_circle(p,radius+2,ink)
		canvas.draw_arc(p,radius,0,TAU,20,color,2.0,true)
		canvas.draw_circle(p,1.8,color)
		canvas.draw_line(p+Vector2(-radius-2,0),p+Vector2(-radius+1,0),color,1.5,true)
		canvas.draw_line(p+Vector2(radius-1,0),p+Vector2(radius+2,0),color,1.5,true)
	else:
		var arrow: PackedVector2Array=PackedVector2Array([p+Vector2(-radius,-radius*.6),p+Vector2(radius,-radius*.6),p+Vector2(0,radius)])
		canvas.draw_colored_polygon(arrow,color)
		arrow.append(arrow[0])
		canvas.draw_polyline(arrow,ink,2.2,true)

func ambush_warning_geometry(warning: Dictionary) -> Dictionary:
	var remaining: float = clampf(float(warning.get("remainingSeconds", 2.0)), 0.0, 2.0)
	var pulse: float = .5 + .5 * sin((2.0 - remaining) * TAU * 2.0)
	return {"center":_screen(warning.position),"shape":"pulse","radius":11.0 + pulse * 7.0,"alpha":.35 + pulse * .45,"label":"기습!"}

func _draw_actor_overlay() -> void:
	var started: int=Time.get_ticks_usec() if performance_profiling_enabled else 0
	var scope: Dictionary=unit_skills.begin_query_scope(true)
	_draw_actor_overlay_contents()
	unit_skills.end_query_scope(scope)
	_profile_elapsed("actorOverlay",started,units.size()+enemies.size())

func _draw_actor_overlay_contents() -> void:
	if actor_overlay == null or config.is_empty():
		return
	var visual_scale: float = three_d_actor_scale if three_d_enabled else 1.0
	if three_d_enabled:
		_draw_zones(actor_overlay)
	for warning in ambush_warnings:
		var marker: Dictionary = ambush_warning_geometry(warning)
		var center: Vector2 = marker.center
		actor_overlay.draw_circle(center, 5.0, Color(.94,.52,.22,float(marker.alpha)))
		actor_overlay.draw_arc(center, float(marker.radius), 0, TAU, 32, Color(1.0,.70,.35,float(marker.alpha)), 2.4, true)
		if ui_font!=null:
			actor_overlay.draw_string_outline(ui_font,center+Vector2(-20,-21),str(marker.label),HORIZONTAL_ALIGNMENT_LEFT,-1,18,3,Color("201914"))
			actor_overlay.draw_string(ui_font,center+Vector2(-20,-21),str(marker.label),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("ffe2a5"))
	_draw_field_markers(actor_overlay)
	_draw_learning_support_overlay()
	_draw_battle_reward_overlay()
	# Match the painted body's generous viewport cull before preparing health
	# and status dictionaries. Keep all near-edge labels and separate markers.
	var painted_overlay_cull: bool=not three_d_enabled and painted_actors.is_ready()
	var overlay_bounds: Rect2=visible_field_rect_local().grow(128.0)
	for unit in units:
		var p: Vector2 = _screen(unit.position)
		if painted_overlay_cull and int(unit.id)!=selected_id and not overlay_bounds.has_point(p): continue
		var scale_factor: float = _depth_scale(float(unit.position.y))*clampf(field_rect.size.y/620.0,0.75,1.25)*visual_scale
		if running and not between_waves and not finished and float(unit.get("hp",0))>0: _draw_actor_health(unit,true,actor_overlay)
		if int(unit.id) == selected_id:
			var ring: PackedVector2Array = PackedVector2Array()
			for index in range(41):
				var angle: float = TAU*index/40.0
				ring.append(p+Vector2(cos(angle)*14.0,sin(angle)*4.5)*scale_factor)
			actor_overlay.draw_polyline(ring,Color(0.87,0.81,0.60,0.64),1.0,true)
			if ui_font and _selected_name_visible(unit):
				var names: Dictionary=selected_unit_label_layout(unit)
				if floating_label_style!=null: actor_overlay.draw_style_box(floating_label_style,names.rect)
				for run in names.runs:
					actor_overlay.draw_string_outline(run.font,run.position,run.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size),3,Color("101410"))
					actor_overlay.draw_string(run.font,run.position,run.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size),Color(run.color))
	for enemy in enemies:
		if float(enemy.hp)<=0 or not _enemy_visible(enemy): continue
		if painted_overlay_cull and not overlay_bounds.has_point(_screen(enemy.position)): continue
		_draw_enemy_role_marker(enemy,actor_overlay)
		if running and not between_waves and not finished: _draw_actor_health(enemy,false,actor_overlay)
	for shot in ([] if external_combat_feedback else projectiles):
		var p: Vector2 = _screen(shot.position)
		if three_d_enabled:
			p.y -= field_rect.size.x/22.0*0.42*_depth_scale(float(shot.position.y))*visual_scale
		var direction: Vector2 = (shot.targetPos-shot.position).normalized()
		actor_overlay.draw_line(p-direction*7.0*visual_scale,p,Color(0.86,0.77,0.58,0.82),1.2,true)
	for effect in ([] if external_combat_feedback else effects):
		var alpha: float = 1.0-float(effect.time)/float(effect.duration)
		var effect_color: Color = effect.color
		effect_color.a = alpha*0.64
		var effect_position: Vector2 = _screen(effect.position)
		if three_d_enabled and str(effect.kind) == "hit":
			effect_position.y -= field_rect.size.x/22.0*0.36*_depth_scale(float(effect.position.y))*visual_scale
		actor_overlay.draw_arc(effect_position,3.0+float(effect.time)*18.0,0,TAU,18,effect_color,1.2,true)
		if str(effect.kind) == "deploy":
			for index in range(6):
				var angle: float = TAU*index/6.0+float(effect.time)
				var offset: Vector2 = Vector2(cos(angle),sin(angle))*float(effect.time)*20.0
				actor_overlay.draw_circle(_screen(effect.position)+offset,1.4*alpha,effect_color)

func _selected_name_visible(unit: Dictionary) -> bool:
	if not running or between_waves or finished:
		return true
	return str(unit.get("animation","idle"))!="attack" and str(unit.get("combatState","guard")) not in ["engaged","charge","impact"]

func _draw_enemy(enemy: Dictionary) -> void:
	var p: Vector2 = _screen(enemy.position)
	var kind: String = str(enemy.kind)
	var depth: float = _depth_scale(float(enemy.position.y))
	if not three_d_enabled and _sailing_visual(enemy):
		var boat: PackedVector2Array = PackedVector2Array([p+Vector2(-14,-4)*depth,p+Vector2(15,-4)*depth,p+Vector2(9,6)*depth,p+Vector2(-8,6)*depth])
		draw_colored_polygon(boat,Color("694c35"))
		draw_polyline(boat,Color("be986e"),1.0,true)
		draw_line(p+Vector2(-8,-3),p+Vector2(-15,11),Color("cfb781"),1.5)
	var tint: Color = Color("886653") if kind == "raider" else Color("79565b") if kind == "runner" else Color("68555b")
	var scale_factor: float = 1.2 if kind == "heavy" else 1.35 if kind == "commander" else 1.0
	_draw_soldier(p,tint,"shield" if kind == "shield" else "spear",enemy.aim,scale_factor,sin(elapsed*7.0+enemy.id)*1.5,false,enemy)
	if kind == "commander" and not three_d_enabled:
		draw_line(p+Vector2(-4,-10)*depth,p+Vector2(-4,-27)*depth,Color("8f907a"),1.0)
		draw_rect(Rect2(p+Vector2(-4,-27)*depth,Vector2(8,9)*depth),Color("7f4439"))

func _draw_death_actor(actor: Dictionary) -> void:
	if bool(actor.get("friendly",false)):
		_draw_soldier(_screen(actor.position),Color("aeb795"),_weapon(str(actor.type)),actor.aim,1.0,0.0,true,actor)
		return
	var scale_factor: float = 1.2 if str(actor.kind) == "heavy" else 1.35 if str(actor.kind) == "commander" else 1.0
	_draw_soldier(_screen(actor.position),Color("795b54"),"shield" if str(actor.kind) in ["shield","heavy","commander"] else "spear",actor.aim,scale_factor,0.0,false,actor)

func actor_tint(position_norm: Vector2, actor: Dictionary = {}) -> Color:
	var profile: Dictionary = visual_profile()
	var ambient: Color = Color(str(profile.get("actorTint",profile.get("ambientTint","#dedbcb"))))
	var brightness: float = clampf(float(profile.get("actorBrightness",0.92)),0.4,1.05)
	var tint: Color = Color(ambient.r*brightness,ambient.g*brightness,ambient.b*brightness,1.0)
	var fog: Color = Color(str(profile.get("fogTint","#b7c2ba")))
	var fog_amount: float = clampf(float(profile.get("fogStrength",0.05))*(1.0-clampf(position_norm.y,0.0,1.0)),0.0,0.18)
	tint = tint.lerp(fog,fog_amount)
	if str(config.get("theme","")) == "night":
		var warmth: float = 0.0
		for torch in config.get("torches", []):
			warmth = maxf(warmth,clampf(1.0-position_norm.distance_to(_point(torch))/0.17,0.0,1.0))
		tint = tint.lerp(Color(0.96,0.76,0.49,1.0),warmth*0.35)
	if float(actor.get("hitClock",0.0)) > 0.0:
		tint = tint.lerp(Color(1.0,0.80,0.59,1.0),0.30)
	tint.a = 1.0
	return tint

func _draw_ground_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var polygon: PackedVector2Array = PackedVector2Array()
	for index in range(33):
		var angle: float = TAU*index/32.0
		polygon.append(center+Vector2(cos(angle),sin(angle))*radii)
	draw_colored_polygon(polygon,color)

func _draw_soldier_shadow(texture: Texture2D, region: Rect2, geometry: Dictionary, actor: Dictionary, alpha: float) -> void:
	var profile: Dictionary = visual_profile()
	var ground: Vector2 = geometry.ground
	var direction_data: Dictionary = profile.get("shadowDirection", {"x":0.65,"y":0.35})
	var direction: Vector2 = _point(direction_data).normalized()
	if direction.length_squared() < 0.01:
		direction = Vector2(0.65,0.35).normalized()
	direction=BattlefieldPresentation.direction_to_view(direction,presentation_mirrored)
	var opacity: float = clampf(float(profile.get("shadowOpacity",0.24)),0.0,0.5)*alpha
	var color: Color = Color(str(profile.get("shadowTint","#151811")))
	var cast_color: Color = color
	cast_color.a = opacity*0.58
	draw_set_transform(ground,direction.angle()+PI/2.0,Vector2(0.64,float(profile.get("shadowLength",0.34))))
	draw_texture_rect_region(texture,Rect2(geometry.offset,geometry.size),region,cast_color)
	draw_set_transform(Vector2.ZERO)
	var width: float = 8.5 if str(actor.get("type","")) == "commander" else 6.0
	var size: Vector2 = geometry.size
	var scale_factor: float = size.x/35.0
	var radii: Vector2 = Vector2(width,2.0)*scale_factor
	color.a = opacity*0.35
	_draw_ground_ellipse(ground+Vector2(0,0.35),radii*1.25,color)
	color.a = opacity*0.70
	_draw_ground_ellipse(ground,radii,color)
	color.a = opacity
	_draw_ground_ellipse(ground,radii*0.66,color)

func _draw_soldier(p: Vector2, armor: Color, type: String, direction: Vector2, scale_factor: float, motion: float, friendly: bool, actor: Dictionary = {}, phase_offset: float = 0.0) -> void:
	if three_d_enabled:
		return
	direction=BattlefieldPresentation.direction_to_view(direction,presentation_mirrored)
	var frame: Dictionary = animation_frame_data(actor,phase_offset,not friendly)
	var texture_key: String = str(frame.textureKey)
	if animated_textures.has(texture_key):
		var texture: Texture2D = animated_textures[texture_key]
		var region_data: Dictionary = frame.region
		var region: Rect2 = Rect2(float(region_data.x),float(region_data.y),float(region_data.w),float(region_data.h))
		var body_factors: Dictionary = {"archer":1.0,"spear":1.15,"samurai":0.96,"commander":1.12,"enemy_light":1.16,"enemy_heavy":0.94}
		var geometry: Dictionary = sprite_geometry(p,scale_factor*float(body_factors.get(texture_key,1.0)))
		var tint: Color = actor_tint(model_point((p-field_rect.position)/field_rect.size),actor)
		if str(frame.state) == "death":
			tint.a = clampf((_animation_duration("death")-float(frame.clock))*8.0,0.0,1.0)
		_draw_soldier_shadow(texture,region,geometry,actor,tint.a)
		var sprite: Sprite2D
		if render_sprite_cursor >= render_sprites.size():
			sprite = Sprite2D.new()
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_filter_clip_enabled = true
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			sprite.material = actor_material
			add_child(sprite)
			render_sprites.append(sprite)
		else:
			sprite = render_sprites[render_sprite_cursor]
		sprite.visible = true
		sprite.texture = texture
		sprite.region_rect = region
		sprite.position = p
		sprite.offset = -Vector2(region.size.x,region.size.y)*geometry.anchor
		sprite.scale = geometry.size/region.size
		sprite.flip_h = direction.x < 0
		sprite.modulate = tint
		sprite.z_index = render_sprite_cursor+1
		render_sprite_cursor += 1
		return
	if sprite_atlas != null:
		var index: int = 0
		match type:
			"spear": index = 1
			"samurai": index = 2
			"commander": index = 3
		if not friendly:
			index = 5 if type == "shield" or scale_factor > 1.1 else 4
		var sprite_size: float = 49.0 * scale_factor
		var rect: Rect2 = Rect2(p + Vector2(-sprite_size * 0.5, -sprite_size * 0.88 + motion * 0.2), Vector2(sprite_size, sprite_size))
		var region: Rect2 = Rect2((index % 3) * 512, (index / 3) * 512, 512, 512)
		if direction.x < 0:
			draw_set_transform(p,0,Vector2(-1,1))
			rect.position = Vector2(-sprite_size * 0.5, -sprite_size * 0.88 + motion * 0.2)
		draw_texture_rect_region(sprite_atlas, rect, region)
		draw_set_transform(Vector2.ZERO)
		return
	var s: float = scale_factor
	draw_set_transform(p,0,Vector2(s,s))
	draw_colored_polygon(PackedVector2Array([Vector2(-8,3),Vector2(-2,0),Vector2(9,4),Vector2(3,7)]),Color(0.03,0.04,0.03,0.34))
	draw_line(Vector2(-2,-1),Vector2(-3+motion,6),Color("343732"),3,true)
	draw_line(Vector2(2,-1),Vector2(3-motion,6),Color("2c302b"),3,true)
	draw_colored_polygon(PackedVector2Array([Vector2(-5,-13),Vector2(5,-13),Vector2(4,-2),Vector2(-4,-2)]),armor.darkened(0.15))
	draw_line(Vector2(-5,-8),Vector2(5,-8),armor.lightened(0.1),1.1)
	draw_line(Vector2(-4,-5),Vector2(4,-5),armor.darkened(0.35),1.0)
	draw_line(Vector2(-5,-11),Vector2(-7,-5),Color("b89a7e"),2.2,true)
	draw_line(Vector2(5,-11),Vector2(7,-6),Color("b89a7e"),2.2,true)
	draw_circle(Vector2(0,-16),3.4,Color("bfa186"))
	draw_arc(Vector2(0,-17),4.6,PI,TAU,9,Color("303936"),3.0,true)
	draw_line(Vector2(-5,-15),Vector2(5,-15),Color("29302d"),2,true)
	if friendly:
		draw_line(Vector2(0,-22),Vector2(-3,-18),Color("d4bd7c"),1.2,true)
	var facing: float = 1.0 if direction.x >= 0 else -1.0
	match type:
		"archer":
			draw_arc(Vector2(8*facing,-8),7.0,-PI/2,PI/2,10,Color("bda27a"),1.5,true)
			draw_line(Vector2(8*facing,-15),Vector2(8*facing,-1),Color("d4c9ae"),0.8,true)
		"gunner":
			draw_line(Vector2(-3*facing,-9),Vector2(15*facing,-11),Color("252c2c"),2.7,true)
			draw_line(Vector2(-3*facing,-8),Vector2(6*facing,-9),Color("856747"),3,true)
		"banner":
			draw_line(Vector2(6,-2),Vector2(6,-30),Color("b6a27d"),1.5)
			draw_rect(Rect2(6,-30,11,15),Color("b6a159"))
			draw_circle(Vector2(11,-24),2.5,Color("694332"))
		"samurai":
			draw_line(Vector2(6*facing,-8),Vector2(16*facing,-20),Color("d4d4c4"),1.7,true)
			draw_line(Vector2(6*facing,-8),Vector2(4*facing,-6),Color("9b8562"),2.5,true)
		"shield":
			draw_rect(Rect2(-8,-12,7,14),Color("675c47"))
			draw_rect(Rect2(-8,-12,7,14),Color("a59976"),false,1)
			draw_line(Vector2(6,-5),Vector2(11,-23),Color("c4b693"),1.3,true)
		_:
			draw_line(Vector2(6*facing,-3),Vector2(10*facing,-29),Color("b8a581"),1.4,true)
			draw_line(Vector2(10*facing,-29),Vector2(11*facing,-34),Color("c5c8b8"),1.8,true)
	draw_set_transform(Vector2.ZERO)

func _draw_learning_support_overlay() -> void:
	# Both render modes share this upper canvas. The opaque 3D photo viewport
	# must not cover newly earned learning support, or duplicate it in 2D.
	for support in learning_supports:
		var color: Color = Color("b7c89b") if bool(support.hinted) else Color("dac18b")
		color.a = 0.68
		var fill: Color = color
		fill.a = 0.035
		var ring: PackedVector2Array = PackedVector2Array()
		for index in range(49):
			var angle: float = TAU*index/48.0
			ring.append(_screen(_point(support)+Vector2(cos(angle),sin(angle))*float(support.r)))
		actor_overlay.draw_colored_polygon(ring,fill)
		actor_overlay.draw_polyline(ring,color,1.4,true)
		var p: Vector2 = _screen(_point(support))
		actor_overlay.draw_arc(p,10.0,-PI*.5,-PI*.5+TAU*float(support.remaining)/float(support.duration),36,color,2.0,true)
		actor_overlay.draw_line(p+Vector2(-4,0),p+Vector2(4,0),color,1.5,true)
		actor_overlay.draw_line(p+Vector2(0,-4),p+Vector2(0,4),color,1.5,true)
		if ui_font != null:
			var seconds: String = str(int(ceilf(float(support.remaining))))
			var text_layout: Dictionary = _selected_name_text_layout({"jp":"支援 "+seconds+"秒","reading":"しえん"+seconds+"びょう","ko":"지원 "+seconds+"초","parts":[{"text":"支","reading":"し"},{"text":"援","reading":"えん"},{"text":" "+seconds,"reading":""},{"text":"秒","reading":"びょう"}]})
			var label_position: Vector2 = p+Vector2(17,-text_layout.size.y)
			label_position.x = clampf(label_position.x,field_rect.position.x+7,field_rect.end.x-text_layout.size.x-7)
			label_position.y = clampf(label_position.y,field_rect.position.y+7,field_rect.end.y-text_layout.size.y-7)
			if floating_label_style!=null: actor_overlay.draw_style_box(floating_label_style,Rect2(label_position,text_layout.size))
			for run in text_layout.runs:
				actor_overlay.draw_string_outline(run.font,label_position+run.position,run.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size),3,Color("101410"))
				actor_overlay.draw_string(run.font,label_position+run.position,run.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size),run.color)

func _draw_battle_reward_overlay() -> void:
	for job in battle_support.jobs:
		if not bool(job.started) or str(job.receipt.kind)!="march_drum": continue
		var phase: float=fposmod(float(job.age)*1.5,1.0)
		var color: Color=Color("80bbd2")
		color.a=(1.0-phase)*.55
		var center: Vector2=_screen(job.origin)
		actor_overlay.draw_arc(center,8.0+phase*34.0,0,TAU,32,color,1.4,true)
		actor_overlay.draw_line(center+Vector2(-4,-7),center+Vector2(4,7),color,2.0,true)
	if three_d_enabled: return
	for data in battle_support.actor_states():
		var actor: Dictionary=data.duplicate(true)
		actor.position=Vector2(float(data.x),float(data.y))

		actor_overlay.draw_line(_screen(actor.position)+Vector2(5,-20),_screen(actor.position)+Vector2(5,-7),Color("67c6ff"),2.0,true)
	for rock in battle_support.rock_states():
		var point: Vector2=_screen(rock.point)+Vector2(0,-float(rock.height)*22.0)
		actor_overlay.draw_circle(point,3.0+float(rock.radius)*12.0,Color("797368"))

func _draw_trait_auras() -> void:
	for aura in _read_active_auras():
		var beneficial: bool = float(aura.get("unitDamageFactor",1.0)) > 1.0 or float(aura.get("unitRangeFactor",1.0)) > 1.0 or float(aura.get("enemySpeedFactor",1.0)) < 1.0
		var color: Color = Color("b8ce91") if beneficial else Color("ce9476")
		color.a = 0.45 if bool(aura.active) else 0.12
		var fill: Color = color
		fill.a = 0.08 if bool(aura.active) else 0.025
		_draw_world_circle(_point(aura),float(aura.get("r",0.1)),fill,color)
		if bool(aura.active):
			var p: Vector2 = _screen(_point(aura))
			draw_arc(p,6.0+sin(animation_time*2)*2,0,TAU,20,color,1.6,true)

func _draw_healthbar(position_screen: Vector2, width: float, ratio: float, color: Color) -> void:
	draw_rect(Rect2(position_screen,Vector2(width,4)),Color(0.03,0.03,0.03,0.85))
	draw_rect(Rect2(position_screen+Vector2(1,1),Vector2((width-2)*clampf(ratio,0,1),2)),color)

func _draw_torches() -> void:
	for torch in config.get("torches", []):
		var p: Vector2 = _screen(_point(torch))
		if not three_d_enabled:
			_draw_world_circle(_point(torch),0.18,Color(0.98,0.58,0.17,0.06),Color(0.98,0.68,0.26,0.12))
		draw_line(p,p+Vector2(0,-14),Color("a79265"),2)
		draw_circle(p+Vector2(0,-17),5+sin(elapsed*6)*0.8,Color(0.96,0.57,0.16,0.8))
		draw_circle(p+Vector2(0,-18),2.5,Color("f7d88a"))

func _draw_storm() -> void:
	draw_rect(field_rect,Color(0.67,0.80,0.89,0.12))
	for i in range(65):
		var px: float = fmod(i*0.173+elapsed*0.045,1.0)
		var py: float = fmod(i*0.327+elapsed*0.06,1.0)
		draw_line(_screen(Vector2(px,py)),_screen(Vector2(px,py))+BattlefieldPresentation.direction_to_view(Vector2(-5,9),presentation_mirrored),Color(0.91,0.96,1,0.4),1.0)
	var storm_zone: Dictionary = config.get("stormZone", {})
	if not storm_zone.is_empty():
		_draw_world_circle(_point(storm_zone),float(storm_zone.r),Color(0.70,0.83,0.92,0.2),Color(0.91,0.96,1,0.45))

func _draw_edge_markers() -> void:
	for index in range(paths.size()):
		var start: Vector2 = _screen(paths[index].points[0])
		draw_circle(start,8,Color(0.42,0.13,0.10,0.85))
		draw_arc(start,10,0,TAU,20,Color("c88960"),1.2,true)
		if ui_font:
			draw_string(ui_font,start+Vector2(-3,4),"!",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("edd49d"))
