extends Node2D

signal state_changed(state: Dictionary)
signal game_event(event: Dictionary)
signal wave_ended(info: Dictionary)
signal wave_started(info: Dictionary)
signal battle_finished(result: Dictionary)

const UNIT_TYPES = [
	{"id":"archer","name":"궁병","jp":"弓兵","reading":"きゅうへい","damage":15.0,"range":0.205,"interval":0.85,"color":"87a48f","weight":40},
	{"id":"spear","name":"창병","jp":"槍兵","reading":"そうへい","damage":16.0,"range":0.145,"interval":0.60,"color":"adb697","weight":32},
	{"id":"samurai","name":"사무라이","jp":"侍","reading":"さむらい","damage":31.0,"range":0.145,"interval":0.76,"color":"bd8064","weight":20},
	{"id":"commander","name":"장수","jp":"武将","reading":"ぶしょう","damage":26.0,"range":0.19,"interval":1.0,"color":"d1b865","weight":8},
]
const ANIMATION_ROWS = {"idle":0,"walk":1,"attack":2,"death":3}
const ANIMATION_FPS = {"idle":5.0,"walk":9.0,"attack":12.0,"death":9.0}
const ANIMATED_UNIT_KEYS = ["archer","spear","samurai","commander","enemy_light","enemy_heavy"]
const ACTOR_COLOR_SHADER = "shader_type canvas_item; render_mode unshaded; uniform float saturation = 0.72; varying vec4 sprite_tint; void vertex() { sprite_tint = COLOR; } void fragment() { vec4 texel = texture(TEXTURE, UV); float grey = dot(texel.rgb, vec3(0.2126, 0.7152, 0.0722)); texel.rgb = mix(vec3(grey), texel.rgb, saturation); COLOR = texel * sprite_tint; }"
const GroundCombat = preload("res://native/ground_combat.gd")
const BattleDuration = preload("res://native/battle_duration.gd")
const StandingPortrait = preload("res://native/barracks_portrait.gd")
const UnitSkills = preload("res://native/unit_skills.gd")
const BattleSupport = preload("res://native/battle_support.gd")
const BattlefieldPresentation = preload("res://native/battlefield_presentation.gd")
const RubyText = preload("res://native/ruby_label.gd")
const GameFonts = preload("res://native/game_fonts.gd")
var presentation_mirrored: bool = false
const UnitGrowth = preload("res://native/unit_growth.gd")
const MAX_SIMULATION_STEP: float = .05
const ENGAGED_MARCH_FACTOR: float = 1.35
const RECRUITMENT_CAPACITY: int = 24
# Input tolerance matches the existing field actor pickup radius. Recruitment
# origins have positions, not authored build zones; this does not add terrain.
const MARCH_DEPLOYMENT_PICK_RADIUS: float = .055
const ENEMY_PATH_ROLE: String = "path_assault"
const ENEMY_EMPLACEMENT_ROLE: String = "emplacement_assault"
const EMPLACEMENT_ENEMY_KINDS: Array = ["enemy_archer","enemy_gunner","enemy_samurai"]
const HUNTER_ACQUIRE_RADIUS: float = .23
const HUNTER_RELEASE_RADIUS: float = .31
const HUNTER_LOST_GRACE: float = .75
const FIRST_STAGE_ENEMY_HP_FACTOR: float = .95

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
var next_id: int = 1
var recruits: int = 0
var spawn_queue: Array = []
var spawn_source_waves: Array = []
var spawn_metadata: Array = []
var spawn_plan_cursor: int = 0
var attack_pattern: String = "skirmish"
var campaign_story_index: Dictionary = {}
var campaign_story_loaded: bool = false
var friendly_casualties_pending: bool = false
var wave_spawn_schedule: Array = []
var spawn_clock: float = 0.0
var elapsed: float = 0.0
var wave_time: float = 0.0
var state_clock: float = 0.0
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
var ground_combat = GroundCombat.new()
var structure_placement_clear: Callable
var unit_skills = UnitSkills.new()
var battle_support = BattleSupport.new()
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

func configure_roster(catalog: Array, unlocked: Array, levels: Dictionary) -> void:
	roster_configured = true
	recruit_catalog.clear()
	unlocked_roster.clear()
	campaign_levels = levels.duplicate(true)
	for definition in catalog:
		if definition is Dictionary and not str(definition.get("id","")).is_empty():
			recruit_catalog[str(definition.id)] = definition.duplicate(true)
	for id in unlocked:
		if recruit_catalog.has(str(id)):
			unlocked_roster[str(id)] = true
	if not config.is_empty():
		_emit_state()

func emplacement_protection_active() -> bool:
	# Early campaign players cannot yet recruit the soldier who guards fixed
	# emplacements. Real roster unlocks, rather than stage numbers, end safety.
	# Unconfigured legacy fixtures retain their original combat contract.
	return roster_configured and not unlocked_roster.has("naginata")

func can_enemy_target_unit(unit: Dictionary) -> bool:
	if unit.is_empty() or float(unit.get("hp",0))<=0 or bool(unit.get("consumed",false)): return false
	return not emplacement_protection_active() or str(unit.get("type","")) not in ["archer","gunner","monk","naginata"]

func enemy_role_contract(kind: String) -> Dictionary:
	var emplacement: bool=kind in EMPLACEMENT_ENEMY_KINDS
	return {"combatRole":ENEMY_EMPLACEMENT_ROLE if emplacement else ENEMY_PATH_ROLE,"roleKo":"진지 공격" if emplacement else "경로 공격","roleMarker":"target" if emplacement else "route_arrow","roleColor":"f0ac57" if emplacement else "e45d54"}

func can_enemy_engage_unit(enemy: Dictionary, unit: Dictionary, contact: bool = false) -> bool:
	if not can_enemy_target_unit(unit): return false
	if str(enemy.get("combatRole",enemy_role_contract(str(enemy.get("kind","raider"))).combatRole))==ENEMY_EMPLACEMENT_ROLE:
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
	if ResourceLoader.exists("res://assets/units-atlas.png"):
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
	queue_redraw()

func bind_render_projection(provider: Control) -> void:
	render_projection_provider=provider

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
	return battle_minutes>0 and not battle_plan.is_empty()

func _timed_wave() -> Dictionary:
	if not _is_timed_battle() or wave<=0 or wave>battle_plan.waves.size(): return {}
	return battle_plan.waves[wave-1]

func _combat_wave_level() -> int:
	return int(_timed_wave().get("sourceWave",wave))

func load_map(map_config: Dictionary, duration_minutes: int = 0) -> void:
	# Never carry another battlefield's physical geometry into this map.
	structure_placement_clear = Callable()
	ground_combat.structure_segment_clear = Callable()
	ground_combat.structure_placement_clear = Callable()
	battle_generation+=1
	_cancel_all_recruitment("map_change",false)
	config = map_config.duplicate(true)
	_cache_circle_floor()
	presentation_mirrored = BattlefieldPresentation.mirror_for_stage(config)
	battle_minutes = BattleDuration.normalize_minutes(duration_minutes) if duration_minutes!=0 else 0
	battle_plan.clear()
	battle_refill_clock = 0.0
	battle_refill_count = 0
	battle_refill_cursor = 0
	completed_wave = 0
	running = false
	paused = false
	between_waves = false
	finished = false
	battle_closed=false
	victory = false
	gold = int(config.get("initialGold", 280))
	wave = 0
	total_waves = int(config.get("totalWaves", 10))
	kills = 0
	units.clear()
	enemies.clear()
	projectiles.clear()
	effects.clear()
	death_actors.clear()
	learning_supports.clear()
	learning_attempts.clear()
	battle_support.bind(self)
	battle_support.reset()
	animation_time = 0.0
	spawn_queue.clear()
	spawn_source_waves.clear()
	spawn_metadata.clear()
	spawn_plan_cursor=0
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
	if battle_minutes>0:
		battle_plan=BattleDuration.build(config,_build_base_wave_schedule(total_waves),battle_minutes)
		total_waves=int(battle_plan.totalWaves)
		wave_spawn_schedule=_build_wave_schedule()
	_refresh_placement_hints()
	var background_path: String = str(config.get("background", ""))
	background=null
	if not three_d_enabled and not background_path.is_empty() and ResourceLoader.exists(background_path): background=load(background_path)
	_emit_state()
	queue_redraw()

func start_battle() -> void:
	if config.is_empty() or finished or battle_closed or running:
		return
	paused = false
	running = true
	if wave == 0:
		_begin_wave()
	_emit_state()

func pause_battle() -> void:
	if not running or finished or between_waves:
		return
	paused = not paused
	_emit_state()

func set_speed(value: float) -> void:
	speed = 2.0 if value>=2.0 else 1.0
	_emit_state()

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
	var cost: int = recruit_cost(unit_type)
	if GroundCombat.is_marching(unit_type):
		return _dispatch_marching(choice,cost,clampi(int(campaign_levels.get(unit_type,1)),1,10),path_index)
	if recruitment_queue.size()>=RECRUITMENT_CAPACITY:
		_event("limit","생산 대기열이 가득 찼습니다. 완료되거나 주문을 취소한 뒤 소집하십시오.")
		return false
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
	if recruitment_queue.size()>=RECRUITMENT_CAPACITY:
		_event("limit","생산 대기열이 가득 찼습니다.")
		return false
	if gold+int(pending.get("paid",0))<cost:
		_event("gold","출진에 필요한 금화가 부족합니다.")
		return false
	var base: Dictionary=ground_combat.select_march_base(path_index)
	if base.is_empty():
		_event("route","출진할 수 있는 육지 경로를 선택하십시오.")
		return false
	# Validate the complete action before releasing an old preview or spending.
	gold+=int(pending.get("paid",0))
	pending.clear()
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
	if definition.is_empty(): return {}
	var permanent_level: int = clampi(int(campaign_levels.get(unit_id,1)),1,10)
	var evolution: Dictionary = _evolution_for(definition,permanent_level)
	return {"id":-1,"type":unit_id,"name":evolution.name,"jp":evolution.jp,"reading":evolution.reading,"paid":0,"cost":recruit_cost(unit_id),"preview":true,"campaignLevel":permanent_level,"evolution":int(evolution.stage),"definition":definition.duplicate(true)}

func _deployment_rejected(result: Dictionary, message: String) -> Dictionary:
	result["ok"] = false
	result["valid"] = false
	result["message"] = message
	result["reason"] = message
	return result

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
	result.merge({"cost":cost,"affordable":gold>=cost,"quantity":unit_skills.recruit_quantity(unit_id,int(template.campaignLevel)),"evolution":int(template.evolution),"campaignLevel":int(template.campaignLevel),"name":str(template.name),"jp":str(template.jp),"reading":str(template.reading),"range":float(_stats(template).range)})
	if recruitment_queue.size()>=RECRUITMENT_CAPACITY: return _deployment_rejected(result,"생산 대기열이 가득 찼습니다.")
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
	var base: Dictionary = ground_combat.select_march_base(path_index)
	if base.is_empty(): return _deployment_rejected(result,"출진할 수 있는 육지 경로를 선택하십시오.")
	result.merge({"position":_normalized_position(base.position),"basePosition":_normalized_position(base.position),"baseId":str(base.baseId),"baseNameKo":str(base.baseNameKo),"pathId":str(base.pathId),"pathIndex":int(base.pathIndex),"dropRadius":MARCH_DEPLOYMENT_PICK_RADIUS})
	if position_norm.distance_to(base.position)>MARCH_DEPLOYMENT_PICK_RADIUS or not ground_combat.land_segment_safe(position_norm,position_norm,0.0):
		return _deployment_rejected(result,"선택한 출진로의 아군 기지에 놓으십시오.")
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
	if template.is_empty() or destination.is_empty(): return _deployment_rejected(result,"배치 조건이 바뀌었습니다. 다시 선택하십시오.")
	var job_id: int = next_recruitment_id
	if not _enqueue_recruitment(template,destination,_point(result.position)):
		return _deployment_rejected(result,"배치 조건이 바뀌었습니다. 다시 선택하십시오.")
	result["jobId"] = job_id
	queue_redraw()
	return result

func placement_preview(position_norm: Vector2) -> Dictionary:
	if pending.is_empty(): return {"active":false,"valid":false,"visible":false,"reason":""}
	return _stationary_placement_preview(pending,position_norm,placement_cursor_visible and not ui_deployment_active)

func _stationary_placement_preview(template: Dictionary, position_norm: Vector2, cursor_visible: bool) -> Dictionary:
	var cost: int = int(template.get("cost",template.get("paid",0)))
	var affordable: bool = not bool(template.get("preview",false)) or gold>=cost
	var result: Dictionary = {"active":true,"valid":false,"visible":cursor_visible and input_enabled and not finished,"affordable":affordable,"type":str(template.type),"evolution":int(template.get("evolution",0)),"campaignLevel":int(template.get("campaignLevel",1)),"cost":cost,"requestedPosition":_normalized_position(position_norm),"position":_normalized_position(position_norm),"range":float(_stats(template).range),"reason":""}
	result.merge(placement_contract(str(template.type)))
	if finished: result.reason="전투가 종료되었습니다.";return result
	if not position_norm.is_finite(): result.reason="유효한 위치를 선택하십시오.";return result
	if recruitment_queue.size()>=RECRUITMENT_CAPACITY: result.reason="생산 대기열이 가득 찼습니다.";return result
	if roster_configured and (not recruit_catalog.has(str(template.type)) or not unlocked_roster.has(str(template.type))): result.reason="아직 해금되지 않은 병력입니다.";return result
	if not affordable: result.reason="배치에 필요한 금화가 부족합니다.";return result
	var build_zone: Dictionary = _eligible_zone(position_norm,str(template.type))
	if build_zone.is_empty(): result.reason=str(result.placementHintKo);return result
	var actual: Vector2 = _placement_position(position_norm,build_zone)
	result.position = _normalized_position(actual)
	if str(build_zone.get("placementRole",""))=="ambush":
		result.merge({"ambushSiteId":str(build_zone.id),"siteNameKo":str(build_zone.nameKo),"homePosition":_normalized_position(actual),"ambushRadius":float(_stats(template).range)})
	for unit in units:
		if GroundCombat.is_marching(str(unit.type)): continue
		if _reserved_position(unit).distance_to(actual)<.052 or (bool(template.get("preview",false)) and unit.position.distance_to(actual)<.052):
			result.reason="다른 병력과 조금 떨어뜨려 배치하십시오."
			return result
	for job in recruitment_queue:
		if str(job.kind)=="marching": continue
		if job.position.distance_to(actual)<.0521:
			result.reason="생산 중인 병력의 예약 지점입니다. 다른 곳을 선택하십시오."
			return result
	var probe: Dictionary = template.duplicate()
	probe.position = actual
	probe.elevation = int(build_zone.get("elevation",0))
	result.range = float(_stats(probe).range)
	result.valid = true
	return result

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
	if finished or battle_closed or recruitment_queue.size()>=RECRUITMENT_CAPACITY or cost<=0 or gold<cost: return false
	var definition: Dictionary=_unit_definition(template)
	var duration: float=float(definition.get("recruitSeconds",clampf(float(cost)*.035,2.0,5.5)))
	if not is_finite(duration) or duration<=0: duration=clampf(float(cost)*.035,2.0,5.5)
	var quantity: int=unit_skills.recruit_quantity(str(template.type),int(template.get("campaignLevel",1)))
	var kind: String=str(placement_contract(str(template.type)).deploymentKind)
	var job: Dictionary={"id":next_recruitment_id,"type":str(template.type),"name":str(template.name),"kind":kind,"pathIndex":int(destination.get("pathIndex",-1)),"position":position,"cost":cost,"quantity":quantity,"remainingSeconds":duration,"totalSeconds":duration,"status":"queued","template":template.duplicate(true),"destination":destination.duplicate(true)}
	next_recruitment_id+=1
	gold-=cost
	recruitment_queue.append(job)
	pending.clear()
	placement_cursor_visible=false
	if kind=="marching": ground_combat.commit_march_base(destination)
	recruits+=1
	_refresh_placement_hints()
	_event("recruitment_queued","%s 생산 대기 · %.1f초" % [job.name,duration],{"side":"friendly","unitType":str(job.type),"cost":cost,"jobId":int(job.id),"quantity":quantity,"pathIndex":int(job.pathIndex),"position":_normalized_position(position)})
	_emit_state()
	return true

func cancel_recruitment(job_id: int) -> bool:
	for index in range(recruitment_queue.size()):
		var job: Dictionary=recruitment_queue[index]
		if int(job.id)!=job_id: continue
		recruitment_queue.remove_at(index)
		gold+=int(job.cost)
		_refresh_placement_hints()
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
		job.status="producing" if float(job.remainingSeconds)>.0000001 else "waiting_capacity"
		if float(job.remainingSeconds)<=.0000001: ready.append({"job":job,"completionOffset":previous_remaining})
	ready.sort_custom(func(a: Dictionary,b: Dictionary):
		return int(a.job.id)<int(b.job.id) if is_equal_approx(float(a.completionOffset),float(b.completionOffset)) else float(a.completionOffset)<float(b.completionOffset)
	)
	for completed in ready:
		var job: Dictionary=completed.job
		var queue_index: int=recruitment_queue.find(job)
		if queue_index<0 or units.size()+int(job.quantity)>int(config.get("unitLimit",14)): continue
		recruitment_queue.remove_at(queue_index)
		var created: Array=[]
		for index in range(int(job.quantity)):
			var unit: Dictionary=job.template.duplicate(true)
			unit.erase("preview")
			unit.merge({"id":next_id,"paid":int(job.cost)/int(job.quantity)+(int(job.cost)%int(job.quantity) if index==0 else 0),"position":job.position,"cooldown":0.0,"healClock":8.0,"elevation":int(job.destination.get("elevation",0)),"aim":Vector2.RIGHT,"animation":"idle","animationClock":0.0,"animationPhase":fmod(float(next_id)*.173,1.0),"deployDuration":.35,"attackPlan":{},"pulseClock":0.0,"hitClock":0.0,"productionJobId":int(job.id)},true)
			next_id+=1
			if str(job.kind)=="marching":
				ground_combat.initialize_marching_unit(unit,job.destination)
				unit.merge({"combatState":"gather","gatherRemaining":2.5,"gatherGroupId":0},true)
				unit.animation="idle"
			else:
				ground_combat.initialize_unit(unit,job.destination)
				unit.deploying=not GroundCombat.is_frontline(str(unit.type))
				if bool(unit.deploying): unit.animation="walk"
			unit_skills.initialize_unit(unit)
			units.append(unit)
			created.append(int(unit.id))
			selected_id=int(unit.id)
			effects.append({"position":unit.position,"time":0.0,"duration":.55,"color":Color("73e5d2"),"kind":"deploy"})
		var first: Dictionary=ground_combat._unit(int(created[0]))
		produced=true
		_combat_event("recruited" if str(job.kind)=="marching" else "placed",first,{}, {"cost":int(job.cost),"quantity":int(job.quantity),"jobId":int(job.id),"actorIds":created,"deploymentKind":str(job.kind),"pathIndex":int(job.pathIndex),"message":"%s 생산 완료" % job.name})
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
	if not ground_combat.is_tower_attacker(target):
		result.reasonKo="살아 있는 적 고정 타워형 진지를 지정하십시오.";return result
	var radius: float=float(_stats(unit).range)*2.0
	if int(target.pathIndex)!=int(unit.postPathIndex) or unit.homePosition.distance_to(target.position)>radius:
		result.reasonKo="엄폐 지점과 같은 길의 가까운 적 사격진지만 암살할 수 있습니다.";return result
	if not ground_combat.ninja_mission_target_valid(unit,target) or not ground_combat.ninja_route_valid(unit,target):
		result.reasonKo="물이나 막힌 지형을 건너 적 사격진지로 갈 수 없습니다.";return result
	if int(unit.get("priorityTargetId",-1))==enemy_id:
		result.reasonKo="이미 그 사격진지를 암살 대상으로 지정했습니다.";result["duplicate"]=true;return result
	if int(unit.get("priorityTargetId",-1))>=0:
		result.reasonKo="소모성 닌자는 한 번 지정한 암살 임무를 다른 대상으로 바꿀 수 없습니다.";return result
	unit["priorityTargetId"]=enemy_id
	unit["targetId"]=enemy_id
	unit["ambushStrikeDone"]=false
	unit["combatState"]="ambush_approach"
	result.merge({"accepted":true,"unitId":int(unit.id),"targetId":enemy_id,"assassinationRadius":radius,"reasonKo":"적 타워형 진지를 암살합니다. 임무가 끝나거나 표적을 잃으면 퇴장하며 재사용할 수 없습니다."},true)
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

func _update_learning_supports(delta: float) -> void:
	var active: Array[Dictionary] = []
	for support in learning_supports:
		support["remaining"] = maxf(0.0,float(support.remaining)-delta)
		if float(support.remaining)>0.00001:
			active.append(support)
	learning_supports = active

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
			_emit_state()
			queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_recruit()

func _process(delta: float) -> void:
	var frame_delta: float = maxf(0.0,delta)
	if running and not paused and not between_waves and not finished:
		advance_simulation(minf(frame_delta, 0.25) * speed)
	elif (finished or between_waves) and not paused and not death_actors.is_empty():
		# Only the already-defeated bodies finish their fall. Battle, support,
		# recovery and cooldown clocks remain suspended during study or results.
		_update_death_actors(minf(frame_delta, 0.15) * speed)
	state_clock += frame_delta
	if state_clock >= 0.25:
		state_clock = 0.0
		_emit_state()
	queue_redraw()

func advance_simulation(delta: float) -> void:
	if not running or paused or between_waves or finished:
		return
	var remaining: float = maxf(0.0,delta)
	while remaining>.0000001 and running and not paused and not between_waves and not finished:
		var step: float = minf(remaining,MAX_SIMULATION_STEP)
		if _is_timed_battle():
			var deadline: float = minf(float(_timed_wave().get("endSeconds",battle_plan.targetSeconds)),float(battle_plan.targetSeconds))
			var until_deadline: float = maxf(0.0,deadline-elapsed)
			if until_deadline<=.0000001:
				elapsed=deadline
				_complete_wave()
				break
			step=minf(step,until_deadline)
		_advance_simulation_step(step)
		remaining -= step

func _advance_simulation_step(delta: float) -> void:
	var generation: int=battle_generation
	elapsed += delta
	animation_time += delta
	wave_time += delta
	_advance_recruitment(delta)
	if generation!=battle_generation or finished or battle_closed: return
	_advance_ambush_warnings(delta)
	if generation!=battle_generation or finished or battle_closed: return
	unit_skills.step(delta)
	battle_support.step(delta)
	_update_learning_supports(delta)
	_advance_actor_animations(delta)
	if generation!=battle_generation or finished or battle_closed: return
	bridge_cooldown = maxf(0.0, bridge_cooldown - delta)
	_update_map_mode(delta)
	battle_refill_clock=maxf(0.0,battle_refill_clock-delta)
	spawn_clock -= delta
	if battle_support.departure_delay>0.0: spawn_clock=maxf(spawn_clock,.025)
	var active_count: int = 0
	var active_cap: int = int(_timed_wave().get("activeCap",BattleDuration.ACTIVE_ENEMY_CAP))
	if _is_timed_battle():
		for enemy in enemies:
			if float(enemy.hp)>0.0: active_count+=1
		active_count+=ambush_warnings.size()
	while spawn_clock <= 0.0 and not spawn_queue.is_empty():
		if _is_timed_battle() and active_count>=active_cap:
			# A capped spawn waits; it never accumulates missed spawns to release
			# together when a defender finally opens room in the active roster.
			spawn_clock=0.0
			break
		var options: Dictionary=spawn_metadata.pop_front() if spawn_metadata.size()==spawn_queue.size() else {}
		var source_wave: int = int(spawn_source_waves.pop_front()) if spawn_source_waves.size()==spawn_queue.size() else wave
		_queue_enemy_spawn(str(spawn_queue.pop_front()),source_wave,options)
		active_count+=1
		spawn_clock += _spawn_interval()
	if _is_timed_battle() and spawn_queue.is_empty(): spawn_clock=maxf(0.0,spawn_clock)
	ground_combat.step(delta)
	_remove_consumed_units()
	if generation!=battle_generation or finished or battle_closed: return
	movement_ranges.clear()
	for unit in units:
		if ground_combat.active_support(unit): movement_ranges[int(unit.id)] = float(_stats(unit).range)+.025
	for enemy in enemies:
		if float(enemy.hp) <= 0.0:
			continue
		_move_enemy(enemy, delta)
		if finished: break
	_remove_fallen_units()
	if finished:
		return
	_update_units(delta)
	_update_projectiles(delta)
	_remove_consumed_units()
	if generation!=battle_generation or finished or battle_closed: return
	if friendly_casualties_pending:
		_remove_fallen_units()
		friendly_casualties_pending=false
	var survivors: Array = []
	for enemy in enemies:
		if float(enemy.hp) <= 0.0:
			if not bool(enemy.get("escaped", false)):
				kills += 1
				gold += int(enemy.reward)
				var last_hit: Dictionary = enemy.get("lastHit",{})
				var killer: Dictionary = {"id":last_hit.get("actorId",-1),"type":last_hit.get("unitType",""),"position":last_hit.get("sourcePosition",enemy.position)}
				unit_skills.on_enemy_killed(enemy,killer)
				_combat_event("killed",killer,enemy,{"reward":int(enemy.reward),"position":_normalized_position(enemy.position),"side":"friendly"})
				death_actors.append({"id":enemy.id,"position":enemy.position,"aim":enemy.aim,"kind":enemy.kind,"animation":"death","animationClock":0.0,"animationPhase":0.0,"sailing":_sailing_visual(enemy),"fortification":bool(enemy.get("fortification",false)),"stationaryEnemy":bool(enemy.get("stationaryEnemy",false)),"hp":0.0,"maxHp":float(enemy.maxHp),"historicalCommander":enemy.get("historicalCommander",{}).duplicate(true)})
				effects.append({"position":enemy.position,"time":0.0,"duration":0.4,"color":Color("dcb36d"),"kind":"hit"})
		else:
			survivors.append(enemy)
	enemies = survivors
	_update_death_actors(delta)
	for effect in effects:
		effect["time"] = float(effect.time) + delta
	effects = effects.filter(func(effect): return float(effect.time) < float(effect.duration))
	if finished:
		return
	if _is_timed_battle():
		if elapsed>=float(_timed_wave().get("endSeconds",battle_plan.targetSeconds))-.0000001:
			elapsed=minf(float(battle_plan.targetSeconds),float(_timed_wave().get("endSeconds",battle_plan.targetSeconds)))
			_complete_wave()
		else:
			_refill_timed_wave()
	elif spawn_queue.is_empty() and enemies.is_empty() and ambush_warnings.is_empty():
		_complete_wave()

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
			if int(enemy.get("blockedBy",-1))==int(unit.id):
				enemy["blockedBy"]=-1
				enemy["counterPlan"]={}
			if int(enemy.get("stationaryTargetId",-1))==int(unit.id):
				_begin_hunter_return(enemy)
		if selected_id==int(unit.id): selected_id=-1
	if departed.is_empty(): return
	units=survivors
	_refresh_placement_hints()
	# Consumption is an irreversible departure, not a casualty or a refund.
	for unit in departed:
		_combat_event("unit_consumed",unit,{}, {"side":"friendly","consumeReason":str(unit.get("consumeReason","mission_ended")),"targetId":int(unit.get("consumedTargetId",-1)),"deploymentKind":"ambush","message":"%s 임무 종료 · 소모" % unit.name})
		if generation!=battle_generation or (battle_closed and not was_closed): return

func _remove_fallen_units() -> void:
	var previous_count: int=units.size()
	var survivors: Array=[]
	for unit in units:
		if float(unit.get("hp",0))>0:
			survivors.append(unit)
			continue
		for enemy in enemies:
			if int(enemy.get("blockedBy",-1))==int(unit.id):
				enemy["blockedBy"]=-1
				enemy["counterPlan"]={}
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
	units=survivors
	if units.size()!=previous_count: _refresh_placement_hints()

func _refill_timed_wave() -> void:
	if not _is_timed_battle() or finished or between_waves or battle_refill_clock>0.0 or not spawn_queue.is_empty(): return
	var plan: Dictionary = _timed_wave()
	if float(plan.get("endSeconds",0.0))-elapsed<=.8 or enemies.size()+ambush_warnings.size()>=int(plan.get("refillThreshold",2)): return
	var entries: Array = plan.get("entries",[])
	if entries.is_empty(): return
	# Supply a small group within the same wave. This does not complete a wave,
	# grant its stipend, or create another learning question.
	for index in range(int(plan.get("refillCount",1))):
		var entry: Dictionary = entries[battle_refill_cursor%entries.size()]
		battle_refill_cursor+=1
		_append_spawn_entry(str(entry.kind),int(entry.sourceWave))
	battle_refill_count+=1
	battle_refill_clock=2.0
	spawn_clock=minf(maxf(0.0,spawn_clock),_spawn_interval())

func _begin_wave() -> void:
	if wave >= total_waves:
		if not _is_timed_battle() or elapsed>=float(battle_plan.targetSeconds)-.0000001: _finish(true)
		return
	wave += 1
	wave_time = 0.0
	spawn_plan_cursor=0
	attack_pattern="skirmish" if wave<=2 else ["formation","mounted_vanguard","rush"][(wave-3)%3]
	if not _is_timed_battle() or spawn_queue.is_empty(): spawn_clock = _spawn_delay()
	if not _is_timed_battle():
		spawn_queue.clear()
		spawn_source_waves.clear()
		spawn_metadata.clear()
	if spawn_metadata.size()!=spawn_queue.size():
		spawn_metadata.clear()
		for _entry in spawn_queue: spawn_metadata.append({})
	battle_refill_clock=2.0
	battle_refill_cursor=0
	if wave_spawn_schedule.is_empty(): wave_spawn_schedule=_build_wave_schedule()
	var entries: Array=wave_spawn_schedule[wave-1].duplicate(true)
	if attack_pattern=="formation":
		entries.sort_custom(func(a,b): return (0 if str(a.kind) in ["shield","heavy"] else 1)<(0 if str(b.kind) in ["shield","heavy"] else 1))
	elif attack_pattern=="mounted_vanguard" and int(config.get("stageNumber",1))>=9:
		entries.sort_custom(func(a,b): return (0 if str(a.kind)=="runner" else 1)<(0 if str(b.kind)=="runner" else 1))
	for entry in entries: _append_spawn_entry(str(entry.kind),int(entry.sourceWave))
	if wave % 5 == 0 or wave == total_waves:
		_append_spawn_entry("commander",_combat_wave_level())
	var extra: Dictionary = _trait().get("reinforcements", {})
	if not extra.is_empty() and wave % maxi(1, int(extra.get("every", 1))) == 0:
		var kind: String = str(extra.get("kind", "raider"))
		if kind in ["raider","runner","shield","heavy","commander"]:
			for index in range(clampi(int(extra.get("count", 1)), 0, 8)):
				_append_spawn_entry(kind,_combat_wave_level())
	_event("wave", "제 %d 파상 공격 · 적 %d기" % [wave, spawn_queue.size()],{"side":"system","count":spawn_queue.size(),"spawnDelay":spawn_clock,"spawnInterval":_spawn_interval()})
	_emit_state()
	wave_started.emit({"wave":wave,"mapId":str(config.get("id",""))})

func _ninja_unlock_stage() -> int:
	return int(recruit_catalog.get("ninja",{}).get("unlockClears",14))+1

func _append_spawn_entry(origin: String, source_wave: int) -> void:
	var ordinal: int=spawn_plan_cursor
	spawn_plan_cursor+=1
	var kind: String=origin
	var stage: int=int(config.get("stageNumber",1))
	if wave>=3 and origin!="commander":
		if origin=="runner" and stage>=9: kind="enemy_cavalry"
		elif stage>=6 and origin in ["shield","heavy"] and ordinal%3==2 and (attack_pattern!="formation" or ordinal%6>=3): kind="enemy_gunner"
		elif stage>=2 and origin=="raider" and ordinal%6 in [3,4]: kind="enemy_archer"
		elif stage>=5 and origin=="heavy" and ordinal%2==1: kind="enemy_samurai"
	var fortification: bool=stage>=_ninja_unlock_stage() and wave>=3 and ordinal==0 and origin!="commander"
	if fortification: kind="enemy_gunner" if wave%2==0 else "enemy_archer"
	if emplacement_protection_active():
		if kind in EMPLACEMENT_ENEMY_KINDS: kind=origin
		fortification=false
	var group: int=ordinal/6
	var path_index: int=-1
	if not paths.is_empty() and (attack_pattern=="formation" or bool(_trait().get("cycleRoutes",false))):
		# Rotate the first cohort, not the whole army into one road. Every
		# successive six-soldier group retains its own authored route.
		var route_offset: int=(maxi(1,wave)-1)%paths.size() if bool(_trait().get("cycleRoutes",false)) else 0
		path_index=(group+route_offset)%paths.size()
	var lane: int=ordinal%3-1 if attack_pattern=="formation" else (ordinal*3+wave)%5-2 if attack_pattern=="rush" else 0
	spawn_queue.append(kind)
	spawn_source_waves.append(source_wave)
	spawn_metadata.append({"originKind":origin,"combatRole":str(enemy_role_contract(kind).combatRole),"formationPattern":attack_pattern,"formationGroup":"w%d:g%d" % [wave,group],"formationRank":(ordinal%6)/3,"formationLane":lane,"pathIndex":path_index,"fortification":fortification})

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
		if not ground_combat.land_segment_safe(position,position,.015): continue
		var reachable: bool=false
		for site in ground_combat.ambush_sites:
			if int(site.pathIndex)==path_index and site.position.distance_to(position)<=float(recruit_catalog.get("ninja",{}).get("range",.15))*2.0 and ground_combat.land_route_safe(path_index,float(site.homeDistance),distance): reachable=true;break
		if not reachable: continue
		var occupied: bool=false
		for enemy in enemies:
			if bool(enemy.get("fortification",false)) and float(enemy.hp)>0 and enemy.position.distance_to(position)<.055: occupied=true;break
		if occupied: continue
		var point_index: int=1
		for index in range(1,ground_combat.cumulative[path_index].size()):
			if distance<=float(ground_combat.cumulative[path_index][index]): point_index=index;break
		return {"position":position,"distance":distance,"pointIndex":point_index}
	return {}

func _original_wave_kind(wave_number: int, index: int) -> String:
	var kind: String = "raider"
	if wave_number>=2 and index%5==3: kind="runner"
	if wave_number>=3 and index%6==4: kind="shield"
	if wave_number>=6 and index%9==7: kind="heavy"
	# Historical terrain changes should not silently replace the original roster.
	var encounter_theme: String = str(config.get("historicalBattlefield",{}).get("legacyEncounterTheme",config.get("theme","")))
	if encounter_theme=="siege" and index%5==4: kind="shield"
	return kind

func _build_wave_schedule() -> Array:
	if _is_timed_battle():
		var timed_schedule: Array=[]
		for plan in battle_plan.waves:
			timed_schedule.append(plan.entries.duplicate(true))
		return timed_schedule
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
	if _is_timed_battle():
		return clampf(float(_combat_wave_level()-1)/maxf(1,float(battle_plan.baseTotalWaves-1)),0,1)
	return clampf(float(wave-1)/maxf(1,float(total_waves-1)),0,1)

func _spawn_delay() -> float:
	return 3.0 if wave<=1 else 2.0 if wave==2 else 1.0

func _spawn_interval() -> float:
	if _is_timed_battle():
		return 1.50 if wave<=1 else 1.35 if wave==2 else lerpf(1.15,0.62,clampf(float(_combat_wave_level()-3)/maxf(1,float(battle_plan.baseTotalWaves-3)),0,1))
	return 1.50 if wave<=1 else 1.35 if wave==2 else lerpf(1.15,0.62,clampf(float(wave-3)/maxf(1,float(total_waves-3)),0,1))

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

func _spawn_enemy(kind: String, source_wave: int = -1, options: Dictionary = {}) -> Dictionary:
	if paths.is_empty():
		return {}
	var origin_kind: String=str(options.get("originKind",{"enemy_archer":"raider","enemy_gunner":"shield","enemy_cavalry":"runner","enemy_samurai":"heavy"}.get(kind,kind)))
	if emplacement_protection_active() and kind in EMPLACEMENT_ENEMY_KINDS: kind=origin_kind
	var path_index: int=_spawn_path_index(options)
	var path: Dictionary = paths[path_index]
	var difficulty: float = float(config.get("difficulty", 1.0))
	if str(config.get("id", "")) == "basic-forest" and int(config.get("stageNumber", 0)) == 1:
		difficulty *= FIRST_STAGE_ENEMY_HP_FACTOR
	var difficulty_wave: int = wave if source_wave<0 else source_wave
	var base_hp: float = (32.0 + difficulty_wave * 10.0) * difficulty
	var move_speed: float = 0.020 + difficulty_wave * 0.00035
	var armor: float = 0.0
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
			reward = 15
		"commander":
			base_hp *= 6.0
			move_speed *= 0.62
			armor = 0.3
			damage = 5
			reward = 45
	for bonus in _trait().get("enemyBonuses", []):
		if str(bonus.get("kind", "all")) in [kind,origin_kind,"all"]:
			base_hp *= float(bonus.get("hpFactor", 1.0))
			move_speed *= float(bonus.get("speedFactor", 1.0))
	var enemy: Dictionary = {"id":next_id,"kind":kind,"sourceWave":difficulty_wave,"hp":base_hp,"maxHp":base_hp,"speed":move_speed,"armor":armor,"damage":damage,"reward":reward,"pathIndex":path_index,"pointIndex":1,"position":path.points[0],"aim":Vector2.RIGHT,"escaped":false,"animation":"walk","animationClock":0.0,"animationPhase":fmod(float(next_id)*0.117,1.0),"hitClock":0.0}
	enemy.merge(enemy_role_contract(kind),true)
	enemy["spawnPathIndex"]=path_index
	enemy["routeProgress"]=0.0
	enemy.merge({"originKind":origin_kind,"formationPattern":str(options.get("formationPattern","skirmish")),"formationGroup":str(options.get("formationGroup","")),"formationRank":int(options.get("formationRank",0)),"formationLane":int(options.get("formationLane",0)),"stationaryEnemy":false,"fortification":false})
	if kind in ["enemy_archer","enemy_gunner"]:
		enemy["attackRange"]=.205 if kind=="enemy_archer" else .14
		enemy["attackInterval"]=.85 if kind=="enemy_archer" else 1.55
		enemy["rangedPlan"]={}
		enemy["attackCooldown"]=0.0
		if bool(options.get("fortification",false)) and int(config.get("stageNumber",1))>=_ninja_unlock_stage():
			var station: Dictionary=_fortification_position(path_index)
			if not station.is_empty():
				enemy.merge({"position":station.position,"pointIndex":int(station.pointIndex),"stationaryEnemy":true,"fortification":true,"animation":"idle","formationLane":0,"fortificationPosition":station.position},true)
	if kind=="commander":
		var story: Dictionary=campaign_story_index.get(str(config.get("id","")),{})
		if not story.is_empty() and bool(story.get("opponentOnField",true)) and story.get("opponent") is Dictionary:
			var commander: Dictionary=story.opponent.duplicate(true)
			commander.merge({"id":str(commander.get("id",story.get("battleEventId","opponent"))),"battleEventId":str(story.get("battleEventId","")),"year":int(story.get("year",0))},true)
			enemy["historicalCommander"]=commander
	if not bool(enemy.stationaryEnemy): enemy.position=_enemy_lane_point(enemy,0)
	if options.has("ambushEntry") and str(enemy.combatRole)==ENEMY_EMPLACEMENT_ROLE:
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
	if _is_timed_battle(): enemy["counterWave"]=difficulty_wave
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
	if kind not in EMPLACEMENT_ENEMY_KINDS or emplacement_protection_active():
		_spawn_enemy(kind,source_wave,options)
		return
	var path_index: int=_spawn_path_index(options)
	var metadata: Dictionary=options.duplicate(true)
	metadata["pathIndex"]=path_index
	var entry: Dictionary=metadata.get("ambushEntry",{})
	if int(entry.get("pathIndex",-1))!=path_index or not entry.has_all(["points","joinDistance","pointIndex","id"]) or entry.get("points",[]).size()<2:
		entry=_prepared_ambush_entry(path_index)
	if entry.is_empty():
		# A missing/blocked authored flank never produces a teleporting hunter.
		_spawn_enemy(str(options.get("originKind",{"enemy_archer":"raider","enemy_gunner":"shield","enemy_samurai":"heavy"}.get(kind,"raider"))),source_wave,metadata)
		return
	metadata["ambushEntry"]=entry
	var departure: Vector2 = entry.transportPoints[0] if str(entry.get("transportKind",""))=="boat" and not entry.get("transportPoints",[]).is_empty() else entry.points[0]
	var warning: Dictionary={"id":next_ambush_id,"kind":kind,"sourceWave":source_wave,"options":metadata,"remainingSeconds":2.0,"position":departure,"pathIndex":path_index,"entranceId":str(entry.id)}
	next_ambush_id+=1
	ambush_warnings.append(warning)
	_event("ambush_warning","적진 별동대 · 2초 뒤 출발",{"side":"enemy","combatRole":ENEMY_EMPLACEMENT_ROLE,"warningId":int(warning.id),"position":_normalized_position(warning.position),"pathIndex":path_index,"duration":2.0})

func _advance_ambush_warnings(delta: float) -> void:
	var active: int=0
	for enemy in enemies:
		if float(enemy.hp)>0: active+=1
	var cap: int=int(_timed_wave().get("activeCap",BattleDuration.ACTIVE_ENEMY_CAP)) if _is_timed_battle() else 1000000
	var keep: Array=[]
	for warning in ambush_warnings:
		warning.remainingSeconds=maxf(0,float(warning.remainingSeconds)-delta)
		if float(warning.remainingSeconds)>0.0000001 or active>=cap: keep.append(warning);continue
		_spawn_enemy(str(warning.kind),int(warning.sourceWave),warning.options)
		active+=1
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
	enemy["counterPlan"]={}

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
		if bool(enemy.get("stationaryEnemy",false)): enemy.animation="idle"
	return true

func _enemy_lane_point(enemy: Dictionary, point_index: int) -> Vector2:
	var points: Array=paths[int(enemy.pathIndex)].points
	var index: int=clampi(point_index,0,points.size()-1)
	var direction: Vector2=points[mini(index+1,points.size()-1)]-points[maxi(0,index-1)]
	var offset: float=float(enemy.get("formationLane",0))*.009
	var candidate: Vector2=points[index]+direction.normalized().orthogonal()*offset
	if not _sailing_visual(enemy) and not ground_combat.land_segment_safe(candidate,candidate,0): return points[index]
	return candidate

func _enemy_ranged_step(enemy: Dictionary, delta: float) -> bool:
	if str(enemy.kind) not in ["enemy_archer","enemy_gunner"]: return false
	var plan: Dictionary=enemy.get("rangedPlan",{})
	enemy["attackCooldown"]=maxf(0,float(enemy.get("attackCooldown",0))-delta)
	var target: Dictionary=_hunter_target(enemy,delta)
	if not plan.is_empty() and (target.is_empty() or int(plan.targetId)!=int(target.id) or not can_enemy_engage_unit(enemy,target)):
		enemy["rangedPlan"]={}
		plan={}
		enemy["animation"]="idle" if bool(enemy.get("stationaryEnemy",false)) else "walk"
	if not plan.is_empty():
		if float(enemy.animationClock)>=float(plan.releaseTime):
			if can_enemy_engage_unit(enemy,target) and enemy.position.distance_to(target.position)<=float(enemy.attackRange) and ground_combat.land_segment_safe(enemy.position,target.position):
				projectiles.append({"position":enemy.position,"targetId":int(target.id),"targetPos":target.position,"damage":float(plan.damage),"type":str(enemy.kind),"victimSide":"friendly","sourceId":int(enemy.id),"sourcePosition":enemy.position,"sourceActor":{"id":int(enemy.id),"kind":str(enemy.kind),"combatRole":str(enemy.combatRole),"position":enemy.position,"pathIndex":int(enemy.pathIndex),"pointIndex":int(enemy.pointIndex),"sailing":_sailing_visual(enemy)},"speed":.65 if str(enemy.kind)=="enemy_archer" else 2.7,"age":0.0})
				_combat_event("shot",enemy,target)
			enemy["rangedPlan"]={}
		if float(enemy.animationClock)<.5: return true
	if str(enemy.get("animation","idle"))=="attack" and float(enemy.animationClock)<.5: return true
	if target.is_empty():
		if bool(enemy.get("stationaryEnemy",false)): enemy.animation="idle";return true
		return bool(enemy.get("hunterReturning",false))
	if enemy.position.distance_to(target.position)>float(enemy.attackRange):
		if not bool(enemy.get("stationaryEnemy",false)):
			var destination: Vector2=target.position+(enemy.position-target.position).normalized()*float(enemy.attackRange)*.85
			_enemy_threat_walk(enemy,destination,delta)
		else: enemy.animation="idle"
		return true
	_turn_enemy(enemy,target.position-enemy.position,delta)
	if float(enemy.attackCooldown)<=0:
		enemy["animation"]="attack"
		enemy["animationClock"]=0.0
		enemy["attackCooldown"]=float(enemy.attackInterval)
		enemy["rangedPlan"]={"targetId":int(target.id),"releaseTime":.25,"damage":(4.0+float(enemy.get("counterWave",wave))*.6)*float(enemy.damage)}
	else: enemy["animation"]="idle"
	return true

func _turn_enemy(enemy: Dictionary, direction: Vector2, delta: float) -> void:
	if direction.length_squared()<.00000001: return
	var desired: Vector2=direction.normalized()
	var previous: Vector2=enemy.get("aim",desired)
	if previous.length_squared()<.00000001: enemy.aim=desired;return
	var angle: float=previous.angle()+clampf(previous.angle_to(desired),-8.0*delta,8.0*delta)
	enemy.aim=Vector2.from_angle(angle)

func _hunter_target(enemy: Dictionary, delta: float) -> Dictionary:
	if bool(enemy.get("transportActive",false)) or str(enemy.combatRole)!=ENEMY_EMPLACEMENT_ROLE or bool(enemy.get("hunterReturning",false)): return {}
	var target: Dictionary=ground_combat._unit(int(enemy.get("stationaryTargetId",-1)))
	if not target.is_empty() and can_enemy_engage_unit(enemy,target):
		var anchor: Vector2=enemy.get("threatAnchor",enemy.position)
		var stationary: bool=bool(enemy.get("stationaryEnemy",false))
		var leash: float=float(enemy.get("attackRange",HUNTER_ACQUIRE_RADIUS))*1.35 if stationary else HUNTER_RELEASE_RADIUS
		var reachable: bool=anchor.distance_to(target.position)<=leash and ground_combat.land_segment_safe(enemy.position,target.position) and ground_combat.land_segment_safe(anchor,target.position)
		enemy["targetLostClock"]=0.0 if reachable else float(enemy.get("targetLostClock",0.0))+delta
		if float(enemy.targetLostClock)<HUNTER_LOST_GRACE: return target
	if not target.is_empty() or enemy.has("threatAnchor"):
		_begin_hunter_return(enemy)
		return {}
	enemy["stationThreatClock"]=maxf(0,float(enemy.get("stationThreatClock",0))-delta)
	if float(enemy.stationThreatClock)>0: return {}
	enemy.stationThreatClock=.35
	var best: Dictionary={}
	var best_priority: int=10
	var acquire_radius: float=float(enemy.get("attackRange",HUNTER_ACQUIRE_RADIUS)) if bool(enemy.get("stationaryEnemy",false)) else HUNTER_ACQUIRE_RADIUS
	var closest: float=acquire_radius
	for unit in units:
		if not can_enemy_engage_unit(enemy,unit) or not ground_combat.land_segment_safe(enemy.position,unit.position): continue
		var distance: float=enemy.position.distance_to(unit.position)
		var priority: int=0 if str(unit.type) in ["archer","gunner","monk","naginata"] else 1
		if distance<=acquire_radius and (priority<best_priority or (priority==best_priority and distance<closest)):
			best=unit;closest=distance;best_priority=priority
	if not best.is_empty():
		enemy["stationaryTargetId"]=int(best.id)
		enemy["threatAnchor"]=enemy.position
		enemy["pursuitRouteDistance"]=ground_combat.enemy_distance(enemy)
		enemy["targetCommitTime"]=elapsed
		enemy["targetLostClock"]=0.0
		enemy["counterPlan"]={}
	return best

func _begin_hunter_return(enemy: Dictionary) -> void:
	enemy["stationaryTargetId"]=-1
	enemy["counterPlan"]={}
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

func _enemy_threat_walk(enemy: Dictionary, destination: Vector2, delta: float, margin: float = .008) -> bool:
	var previous: Vector2=enemy.position
	var next: Vector2=previous.move_toward(destination,float(enemy.speed)*ENGAGED_MARCH_FACTOR*delta)
	if not ground_combat.land_segment_safe(previous,next,margin) or (not bool(enemy.get("hunterReturning",false)) and not ground_combat.land_segment_safe(next,enemy.get("threatAnchor",previous))): return false
	enemy.position=next
	if next.distance_squared_to(previous)>.000000001:
		_turn_enemy(enemy,next-previous,delta)
		if str(enemy.animation)!="walk": enemy.animation="walk";enemy.animationClock=0.0
		_track_footstep(enemy,previous,"enemy")
	else: enemy.animation="idle"
	return next.distance_squared_to(destination)<.00000001

func _enemy_stationary_threat(enemy: Dictionary, delta: float) -> bool:
	if str(enemy.get("combatRole",enemy_role_contract(str(enemy.kind)).combatRole))!=ENEMY_EMPLACEMENT_ROLE: return false
	if str(enemy.kind) in ["enemy_archer","enemy_gunner"] or bool(enemy.get("stationaryEnemy",false)) or _sailing_visual(enemy): return false
	var target: Dictionary=_hunter_target(enemy,delta)
	if target.is_empty(): return bool(enemy.get("hunterReturning",false))
	var distance: float=enemy.position.distance_to(target.position)
	if distance>.032:
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
	enemy["counterPlan"] = {}
	enemy["rangedPlan"] = {}
	if int(enemy.transportIndex)>=points.size():
		enemy.position = points[-1]
		enemy.transportActive = false
		enemy["ingressTargetClock"] = 0.0
	return true

func _move_enemy(enemy: Dictionary, delta: float) -> void:
	# Waterborne troops finish their authored landing before any ground
	# blocker, emplacement pursuit, attack or main-route escape is evaluated.
	if _enemy_transport_step(enemy,delta): return
	# Physical marching blockers may delay a hunter's return, but a destroyed
	# emplacement must never remain its committed target during that delay.
	if str(enemy.get("combatRole",""))==ENEMY_EMPLACEMENT_ROLE and int(enemy.get("stationaryTargetId",-1))>=0:
		var committed: Dictionary=ground_combat._unit(int(enemy.stationaryTargetId))
		if committed.is_empty() or not can_enemy_engage_unit(enemy,committed): _begin_hunter_return(enemy)
	if ground_combat.blocked(enemy):
		enemy["rangedPlan"]={}
		ground_combat.counterattack(enemy,delta)
		return
	if _enemy_ingress_step(enemy,delta): return
	if _hunter_return_step(enemy,delta): return
	if _enemy_stationary_threat(enemy,delta): return
	enemy["blockedBy"] = -1
	enemy["counterPlan"] = {}
	if not _sailing_visual(enemy) and _enemy_ranged_step(enemy,delta): return
	if bool(enemy.get("stationaryEnemy",false)): return
	var path: Dictionary = paths[int(enemy.pathIndex)]
	var previous: Vector2 = enemy.position
	var multiplier: float = _approach_march_factor()
	for unit in units:
		if movement_ranges.has(int(unit.id)) and unit.position.distance_to(enemy.position)<=float(movement_ranges[int(unit.id)]):
			multiplier = ENGAGED_MARCH_FACTOR
			break
	if float(enemy.get("slowClock",0.0)) > 0.0:
		multiplier *= float(enemy.get("slowFactor",0.75))
	for aura in active_auras():
		if bool(aura.active) and enemy.position.distance_to(_point(aura)) <= float(aura.get("r", 0.1)):
			multiplier *= float(aura.get("enemySpeedFactor", 1.0))
	if str(config.get("theme", "")) == "harbor" and int(enemy.pointIndex) <= int(config.get("landingIndex", 2)):
		multiplier *= 1.6
	if storm_active:
		multiplier *= 0.62
		var storm_zone: Dictionary = config.get("stormZone", {})
		if not storm_zone.is_empty() and enemy.position.distance_to(_point(storm_zone)) < float(storm_zone.get("r", 0.11)):
			multiplier = 0.0
	var next_animation: String = "idle" if multiplier <= 0.0 else "walk"
	if str(enemy.get("animation", "walk")) != next_animation:
		enemy["animation"] = next_animation
		enemy["animationClock"] = 0.0
	var remaining: float = float(enemy.speed) * multiplier * delta
	if str(enemy.get("formationPattern",""))=="formation" and not str(enemy.get("formationGroup","")).is_empty():
		var own_distance: float=ground_combat.enemy_distance(enemy)
		for leader in enemies:
			if int(leader.id)==int(enemy.id) or float(leader.hp)<=0 or bool(leader.get("stationaryEnemy",false)) or int(leader.pathIndex)!=int(enemy.pathIndex) or str(leader.get("formationGroup",""))!=str(enemy.formationGroup) or int(leader.get("formationLane",0))!=int(enemy.formationLane) or int(leader.get("formationRank",0))>=int(enemy.formationRank): continue
			remaining=minf(remaining,maxf(0,ground_combat.enemy_distance(leader)-own_distance-.032))
	var guard: int = 0
	while remaining > 0.0 and guard < 10:
		guard += 1
		var point_index: int = int(enemy.pointIndex)
		if point_index >= path.points.size():
			_escape_enemy(enemy, str(path.get("objectiveId", "main")))
			break
		var target: Vector2 = _enemy_lane_point(enemy,point_index)
		if point_index == path.points.size() - 1:
			# A fixed camp can have several defended contact points sharing HP.
			# Hunters returning to their own route must keep that route's endpoint.
			target=path.points[-1]
			if str(enemy.combatRole)!=ENEMY_PATH_ROLE:
				var obj: Dictionary = _objective(str(path.get("objectiveId", "main")))
				if not obj.is_empty() and bool(obj.get("mobile",false)): target=obj.position
		var offset: Vector2 = target - enemy.position
		var distance: float = offset.length()
		var next_position: Vector2 = target if remaining >= distance else enemy.position + offset.normalized() * remaining
		# Authored bridge and landing segments keep their existing water rules.
		# Every ordinary ground step still respects this scene's real walls.
		if not _sailing_visual(enemy) and ground_combat.structure_segment_clear.is_valid() and not bool(ground_combat.structure_segment_clear.call(enemy.position,next_position,.008)):
			enemy["animation"] = "idle"
			break
		if remaining >= distance:
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
		var stats: Dictionary = _stats(unit)
		var target: Dictionary = {}
		var best_progress: float = -1.0
		if GroundCombat.is_frontline(str(unit.type)):
			target = ground_combat.attack_target(unit)
		else:
			for enemy in enemies:
				if float(enemy.hp) <= 0.0 or not _enemy_visible(enemy): continue
				if unit.position.distance_to(enemy.position) > float(stats.range): continue
				var progress: float = float(enemy.pointIndex) / paths[int(enemy.pathIndex)].points.size()
				if progress > best_progress: best_progress=progress;target=enemy
		if target.is_empty() or not ground_combat.primary_target_allowed(unit,target,"prepare"):
			continue
		unit["aim"] = (target.position - unit.position).normalized()
		unit["cooldown"] = float(stats.interval)
		var damage: float = float(stats.damage)
		unit["animation"] = "attack"
		unit["animationClock"] = 0.0
		var duration: float = minf(_animation_duration("attack"),float(stats.interval)*0.95) if str(unit.type) in ["ninja","spear"] else _animation_duration("attack")
		unit["attackDuration"] = duration
		unit["attackPlan"] = unit_skills.prepare_attack(unit,target,damage,_impact_time(str(unit.type))*duration/_animation_duration("attack"))

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
			if not plan.is_empty() and float(unit.animationClock) >= float(plan.get("releaseTime", 0.25)):
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
		enemy["animationClock"] = float(enemy.get("animationClock", 0.0)) + delta
		enemy["hitClock"] = maxf(0.0, float(enemy.get("hitClock", 0.0)) - delta)
		enemy["slowClock"] = maxf(0.0, float(enemy.get("slowClock", 0.0)) - delta)

func _release_unit_attack(unit: Dictionary, plan: Dictionary) -> void:
	if str(unit.type)=="monk" or float(unit.get("hp",0))<=0 or bool(unit.get("consumed",false)): return
	if not plan.get("skillMeta",{}).is_empty() and not unit_skills._valid_meta(plan.skillMeta): return
	if bool(plan.get("nativeReleaseConsumed",false)): return
	var generation: int=battle_generation
	plan["nativeReleaseConsumed"]=true
	var ground: bool = GroundCombat.is_ground(str(unit.type))
	var frontline: bool = GroundCombat.is_frontline(str(unit.type))
	if frontline and not ground_combat.can_fight(unit): return
	var target: Dictionary = _enemy(int(plan.targetId))
	var stats: Dictionary = _stats(unit)
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
				if float(candidate.hp) > 0.0 and _enemy_visible(candidate) and unit.position.distance_to(candidate.position) <= float(stats.range):
					target = candidate
					break
	if target.is_empty():
		return
	unit["aim"] = (target.position - unit.position).normalized()
	var damage: float = float(plan.damage)
	var source: Dictionary=_attack_source(unit,plan)
	if ground:
		if not ground_combat.shares_contact_front(unit,target) or unit.position.distance_to(target.position) > ground_combat.reach(unit)*1.1 or not ground_combat.land_segment_safe(unit.position,target.position):
			return
		_combat_event("shot",unit,target,_skill_event_fields(plan))
		if generation!=battle_generation or battle_closed: return
		var actual_damage: float = _damage_enemy(target, damage, str(unit.type),source)
		if generation!=battle_generation or battle_closed: return
		if bool(plan.get("charge",false)):
			_combat_event("charge_impact",unit,target,{"damage":actual_damage,"position":_normalized_position(target.position)})
			if generation!=battle_generation or battle_closed: return
		effects.append({"position":target.position,"time":0.0,"duration":0.18,"color":Color("e8d8b4"),"kind":"hit"})
		unit_skills.after_release(unit,target,plan)
		if str(unit.type)=="ninja" and float(target.hp)<=0:
			ground_combat.mark_ninja_consumed(unit,"target_defeated")
		if bool(plan.get("guardDash",false)):
			unit_skills.finish_guard_dash(unit,true)
			unit.guardDashData={}
	else:
		if str(unit.type)=="gunner" and (int(target.pathIndex)!=int(unit.postPathIndex) or unit.position.distance_to(target.position)>float(stats.range) or not _enemy_visible(target) or _sailing_visual(target)):
			return
		var shot: Dictionary={"position":unit.position,"targetId":target.id,"targetPos":target.position,"damage":damage,"type":unit.type,"sourceId":unit.id,"sourcePosition":unit.position,"sourceUnit":source,"speed":2.7 if str(unit.type)=="gunner" else .65,"age":0.0}
		projectiles.append(unit_skills.decorate_projectile(shot,unit,plan))
		_combat_event("shot",unit,target,_skill_event_fields(plan))
		if generation!=battle_generation or battle_closed: return
		unit_skills.after_release(unit,target,plan)

func _skill_event_fields(context: Dictionary) -> Dictionary:
	var fields: Dictionary={}
	for key in ["skillId","skillIds","flags","effectKind","skillMeta"]:
		if context.has(key):
			var value: Variant=context[key]
			fields[key]=value.duplicate(true) if value is Dictionary or value is Array else value
	return fields

func _attack_source(unit: Dictionary, context: Dictionary = {}) -> Dictionary:
	var source: Dictionary={"id":int(unit.id),"type":str(unit.type),"position":unit.position,"campaignLevel":int(unit.get("campaignLevel",1))}
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
				var source: Dictionary={"id":int(shot.get("sourceId",-1)),"type":str(shot.type),"position":shot.get("sourcePosition",shot.position),"campaignLevel":int(shot.get("campaignLevel",1))}
				source.merge(_skill_event_fields(shot),true)
				var actual_damage: float=_damage_enemy(target,float(shot.damage),str(shot.type),source) if target_alive else 0.0
				unit_skills.after_projectile_hit(shot,target if target_alive else {},actual_damage)
			effects.append({"position":impact_position,"time":0.0,"duration":0.15,"color":Color("edc585"),"kind":"hit"})
		else:
			shot["position"] = shot.position + offset.normalized() * step
			remaining.append(shot)
	projectiles.append_array(remaining)

func _damage_friendly(unit: Dictionary, amount: float, source: Dictionary) -> float:
	if not can_enemy_engage_unit(source,unit,true): return 0.0
	var armor: float=UnitGrowth.base_armor(str(unit.type))
	var modified: Dictionary=unit_skills.modify_incoming(unit,amount,armor)
	var before: float=float(unit.hp)
	unit["hp"]=maxf(0,before-maxf(0,float(modified.get("amount",amount*(1.0-armor)))))
	unit["hitClock"]=.12
	var fields: Dictionary=_skill_event_fields(modified)
	fields.merge({"position":_normalized_position(unit.position),"damage":before-float(unit.hp),"hpBefore":before,"hpAfter":float(unit.hp),"armor":float(modified.get("armor",armor)),"blocked":bool(modified.get("blocked",false))},true)
	_combat_event("hit",source,unit,fields)
	if float(unit.hp)<=0:
		ground_combat._on_unit_injured(unit)
		friendly_casualties_pending=true
	return before-float(unit.hp)

func _damage_enemy(enemy: Dictionary, amount: float, unit_type: String, source: Dictionary = {}) -> float:
	if float(enemy.hp)<=0 or bool(enemy.get("escaped",false)): return 0.0
	var previous_health: float = float(enemy.hp)
	var armor: float = unit_skills.modify_enemy_armor(enemy,float(enemy.armor))
	var modified: Dictionary=unit_skills.modify_outgoing(enemy,amount,unit_type,source)
	amount=maxf(0,float(modified.get("amount",amount)))
	if unit_type == "samurai" or unit_type == "commander":
		armor *= 0.4
	elif unit_type == "gunner":
		armor *= 0.3
	if unit_type == "ninja" and float(enemy.hp) <= float(enemy.maxHp)*0.30:
		amount *= 1.5
	enemy["hp"] = 0.0 if bool(modified.get("instant",false)) else maxf(0,float(enemy.hp)-amount*(1.0-armor))
	var actual_damage: float = previous_health-maxf(0,float(enemy.hp))
	if actual_damage<=0.0: return 0.0
	var attacker: Dictionary = source if not source.is_empty() else {"type":unit_type,"id":-1,"position":enemy.position}
	enemy["lastHit"] = {"actorId":attacker.get("id",-1),"unitType":unit_type,"sourcePosition":attacker.get("position",enemy.position)}
	var fields: Dictionary=_skill_event_fields(source)
	if not str(modified.get("skillId","")).is_empty(): fields["skillId"]=str(modified.skillId)
	if not str(modified.get("effectKind","")).is_empty(): fields["effectKind"]=str(modified.effectKind)
	var flags: Dictionary=fields.get("flags",{}).duplicate(true)
	flags.merge(modified.get("flags",{}),true)
	fields["flags"]=flags
	fields.merge({"damage":actual_damage,"hpBefore":previous_health,"hpAfter":float(enemy.hp),"armor":armor,"position":_normalized_position(enemy.position),"instant":bool(modified.get("instant",false))},true)
	_combat_event("hit",attacker,enemy,fields)
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
	if finished or wave<=completed_wave or wave<=0: return
	var generation: int=battle_generation
	var timed: bool = _is_timed_battle()
	if timed and elapsed<float(_timed_wave().get("endSeconds",battle_plan.targetSeconds))-.0000001: return
	# The last combat step can contain an escape as well as the deadline.
	# A lost objective takes precedence over holding out until that deadline.
	for objective in objectives:
		if int(objective.hp)<=0:
			_finish(false)
			return
	completed_wave=wave
	if not timed:
		ground_combat.cease_combat()
		_remove_consumed_units()
		if generation!=battle_generation or battle_closed: return
	gold += 40 + wave * 3
	var supply: Dictionary = _trait().get("waveGold", {})
	if not supply.is_empty() and wave % maxi(1, int(supply.get("every", 1))) == 0:
		var amount: int = maxi(0, int(supply.get("amount", 0)))
		gold += amount
		_event("trait-supply", "작전 보급 · 금화 +%d" % amount)
	var final_wave: bool = elapsed>=float(battle_plan.targetSeconds)-.0000001 if timed else wave>=total_waves
	_event("waveend","",{"side":"system","final":final_wave,"kills":kills})
	if generation!=battle_generation or battle_closed: return
	if final_wave:
		_finish(true)
		return
	between_waves = true
	if not timed: projectiles.clear()
	_emit_state()
	wave_ended.emit({"wave":wave,"totalWaves":total_waves,"mapId":config.get("id", ""),"kills":kills})

func _finish(won: bool) -> void:
	if finished:
		return
	var generation: int=battle_generation
	finished=true
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

func _stats(unit: Dictionary) -> Dictionary:
	var definition: Dictionary = _unit_definition(unit)
	var growth: Dictionary = UnitGrowth.factors(unit,definition)
	var attack_range: float = float(definition.range)*float(growth.range)
	var damage: float = float(definition.damage)*float(growth.damage)
	var interval: float = float(definition.interval)*float(growth.interval)
	for bonus in _trait().get("unitBonuses", []):
		if str(bonus.get("type", "all")) in [str(unit.type), "all"]:
			damage *= float(bonus.get("damageFactor", 1.0))
			attack_range *= float(bonus.get("rangeFactor", 1.0))
			interval *= float(bonus.get("intervalFactor", 1.0))
	if unit.has("position"):
		for aura in active_auras():
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
	return GroundCombat.placement_contract(type_name)

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

func _eligible_zone(p: Vector2, type_name: String = "") -> Dictionary:
	if p.x < 0.025 or p.x > 0.975 or p.y < 0.04 or p.y > 0.96:
		return {}
	var role: String = str(placement_contract(_placement_type(type_name)).placementRole)
	if role=="ambush" and not ground_combat.land_segment_safe(p,p): return {}
	for obstacle in config.get("obstacles",[]):
		if bool(obstacle.get("blockPlacement",false)) and p.distance_to(_point(obstacle)) <= float(obstacle.get("r",0.0)):
			return {}
	for build_zone in zones:
		if str(build_zone.get("placementRole","ranged")) != role: continue
		if p.distance_to(build_zone.position) <= float(build_zone.get("r", 0.08))+.00001:
			if role=="ambush":
				if ground_combat.ambush_position_legal(build_zone.position,build_zone.entryPosition): return build_zone
				continue
			if role=="ranged" and _on_road(p):
				continue
			var projected: Vector2 = _placement_position(p,build_zone)
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
	if str(build_zone.get("placementRole","ranged"))!=role: return false
	if p.distance_to(build_zone.position) > float(build_zone.get("r", 0.08)) + 0.00001:
		return false
	if _eligible_zone(p,type_name)!=build_zone:
		return false
	var actual: Vector2 = _placement_position(p,build_zone)
	for unit in units:
		if GroundCombat.is_marching(str(unit.type)): continue
		if _reserved_position(unit).distance_to(actual) < 0.0521:
			return false
	for job in recruitment_queue:
		if str(job.kind)!="marching" and job.position.distance_to(actual)<.0521: return false
	return true

func _zone_placement_hint(build_zone: Dictionary, type_name: String = "") -> Vector2:
	var role: String = str(placement_contract(_placement_type(type_name)).placementRole)
	if str(build_zone.get("placementRole","ranged"))!=role: return Vector2(-1,-1)
	var center: Vector2 = build_zone.position
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
	placement_hints.clear()
	for build_zone in zones:
		placement_hints.append(_zone_placement_hint(build_zone))
	queue_redraw()
	if actor_overlay!=null:
		actor_overlay.queue_redraw()

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

func _enemy(id: int) -> Dictionary:
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
	result["hp"] = float(unit.get("hp",ground_combat.max_health(unit)))
	result["maxHp"] = float(unit.get("maxHp",ground_combat.max_health(unit)))
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
		public.merge(enemy_role_contract(str(enemy.kind)),true)
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
	var result: Dictionary = {"mapId":config.get("id", ""),"theme":config.get("theme", ""),"wave":wave,"totalWaves":total_waves,"gold":gold,"recruitCost":config.get("recruitCost", 60),"unitLimit":config.get("unitLimit", 14),"hp":hp,"maxHp":max_hp,"objectives":public_objectives,"units":public_units,"selected":_unit_public(_selected()),"pending":_unit_public(pending),"paused":paused,"betweenWaves":between_waves,"waiting":between_waves,"victory":victory,"defeat":finished and not victory,"finished":finished,"running":running,"kills":kills,"enemyCount":enemies.size(),"enemies":public_enemies,"deathActors":public_deaths,"remainingSpawns":spawn_queue.size(),"speed":speed,"elapsed":elapsed,"bridge":bridge_index,"bridgeCooldown":bridge_cooldown,"storm":storm_active,"animationTime":animation_time,"animationAssets":animated_textures.keys(),"traitName":_trait().get("nameKO", ""),"activeAuras":active_auras(),"learningSupports":learning_supports.duplicate(true),"routeCycle":bool(_trait().get("cycleRoutes", false)),"tacticsName":config.get("tactics",{}).get("nameKo",""),"tacticsDescription":config.get("tactics",{}).get("descriptionKo","")}
	var target_seconds: float = float(battle_plan.get("targetSeconds",0.0))
	result.merge({"battleMinutes":battle_minutes,"battleTargetSeconds":target_seconds,"battleElapsedSeconds":elapsed,"battleRemainingSeconds":maxf(0.0,target_seconds-elapsed),"battleMode":"timed_survival" if _is_timed_battle() else "legacy_waves","waveRemainingSeconds":maxf(0.0,float(_timed_wave().get("endSeconds",elapsed))-elapsed),"battleRefillCount":battle_refill_count})
	result["battleSupports"]=battle_support.snapshot()
	result["emplacementProtectionActive"]=emplacement_protection_active()
	result["protectedUnitTypes"]=["archer","gunner","monk","naginata"] if emplacement_protection_active() else []
	var recruit_costs: Dictionary={}
	for definition in recruit_catalog.values() if roster_configured else UNIT_TYPES:
		recruit_costs[str(definition.id)]=recruit_cost(str(definition.id))
	result["recruitCosts"]=recruit_costs
	var bases: Array=[]
	for base in ground_combat.march_bases:
		bases.append({"baseId":str(base.baseId),"baseNameKo":str(base.baseNameKo),"pathIndex":int(base.pathIndex),"pathId":str(base.pathId),"objectiveId":str(base.objectiveId),"x":base.position.x,"y":base.position.y,"baseDistance":float(base.baseDistance),"routeMin":float(base.routeMin),"routeMax":float(base.routeMax)})
	result["marchBases"]=bases
	result["presentationMirrored"]=presentation_mirrored
	result["fieldMarkers"]=field_markers()
	result["productionWorldIndicators"]=false
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
	result["recruitmentCapacity"]=RECRUITMENT_CAPACITY
	result["attackPattern"]=attack_pattern
	result["attackPatternKo"]={"formation":"대형 진입","mounted_vanguard":"기마 선행 · 보병 후속","rush":"분산 난입","skirmish":"소규모 접근"}.get(attack_pattern,"접근")
	return result

func actor_states() -> Array:
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
		states.back().merge(enemy_role_contract(str(enemy.kind)),true)
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
	state_changed.emit(snapshot())

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
	var side: String = "enemy" if actor.has("kind") else "friendly"
	var unit_type: String = str(actor.get("type",actor.get("kind","")))
	var data: Dictionary = {"side":side,"unitType":unit_type,"enemyKind":str(actor.get("kind","")),"weapon":_weapon(unit_type),"actorId":actor.get("id",-1)}
	if side=="enemy":
		data["sailing"] = bool(actor.sailing) if actor.has("sailing") else _sailing_visual(actor)
		data.merge(enemy_role_contract(unit_type),true)
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
	game_event.emit(data)

func _draw() -> void:
	if field_rect.size.x <= 1.0 or config.is_empty():
		return
	if not three_d_enabled:
		if background != null:
			var image_rect: Rect2=Rect2(Vector2(field_rect.end.x,field_rect.position.y),Vector2(-field_rect.size.x,field_rect.size.y)) if presentation_mirrored else field_rect
			draw_texture_rect(background, image_rect, false)
		else:
			draw_rect(field_rect, Color(str(config.get("color", "#334333"))))
		draw_rect(field_rect, Color(0.03, 0.04, 0.03, 0.11))
	_draw_roads()
	_draw_trait_auras()
	if not three_d_enabled:
		_draw_zones(self)
	if str(config.get("theme", "")) == "night":
		_draw_torches()
	render_sprite_cursor = 0
	if not three_d_enabled:
		var actors: Array = render_actor_list()
		if actor_material != null:
			actor_material.set_shader_parameter("saturation",float(visual_profile().get("actorSaturation",0.70)))
		for actor in actors:
			if bool(actor.get("dead", false)):
				_draw_death_actor(actor.data)
			elif actor.friendly:
				var unit: Dictionary = actor.data
				var pulse: float = 1.0 + sin(float(unit.get("pulseClock",0.0))*PI/0.8)*0.065
				_draw_soldier(_screen(actor.position),Color(str(_stats(unit).color)),str(unit.type),unit.aim,float(actor.sizeFactor)*pulse,0.0,true,unit,float(actor.phaseOffset))
			else:
				_draw_enemy(actor.data)
		for data in battle_support.actor_states():
			var supporter: Dictionary=data.duplicate(true)
			supporter.position=Vector2(float(data.x),float(data.y))

			_draw_soldier(_screen(supporter.position),Color("79a7a8"),"matchlock",Vector2(data.aimX,data.aimY),1.0,float(data.animationClock),true,supporter)
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

func _draw_zones(target: Node2D = null) -> void:
	var canvas: Node2D=target if target!=null else self
	var selected: Dictionary = _selected()
	if not selected.is_empty() and pending.is_empty():
		var stats: Dictionary = _stats(selected)
		if GroundCombat.is_ambush(str(selected.type)):
			_draw_world_circle(selected.homePosition,float(selected.guardRadius),Color(.72,.60,1.0,.012),Color(.72,.60,1.0,.30),canvas)
			_draw_world_circle(selected.homePosition,float(stats.range)*2.0,Color(0,0,0,0),Color(.72,.60,1.0,.12),canvas)
		else:
			_draw_world_circle(selected.position,float(stats.range),Color(0.77,0.83,0.66,0.012),Color(0.78,0.83,0.66,0.15),canvas)
	for index in range(zones.size()):
		var build_zone: Dictionary = zones[index]
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
	var fill: Color = color
	fill.a = .016
	var outline: Color = color
	outline.a = .63 if valid else .42
	_draw_world_circle(actual,float(preview.range),fill,outline,canvas,1.5)
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
	if not (external_placement_ghost and three_d_enabled):
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
		anchor.y-=float(sprite_geometry(_screen(actor.position)).size.y)+8.0
		flags=unit_skills.public_state(actor).get("flags",{}) if friendly else unit_skills.enemy_state(actor).get("flags",{})
	var width: float=58.0 if str(actor.get("type",actor.get("kind",""))) in ["commander","enemy_cavalry"] else 46.0
	# Retain the previous bar centre, edge clamping and name-label reservation.
	# Only the drawn line gets thinner; the real head/foot anchor stays fixed.
	var anchor_rect: Rect2=Rect2(Vector2(anchor.x-width*.5,anchor.y-HEALTHBAR_ANCHOR_HEIGHT),Vector2(width,HEALTHBAR_ANCHOR_HEIGHT))
	var visible: Rect2=visible_field_rect_local()
	if visible.has_point(_screen(actor.position)) and visible.size.x>width+25 and visible.size.y>40:
		anchor_rect.position.x=clampf(anchor_rect.position.x,visible.position.x+13,visible.end.x-width-3)
		anchor_rect.position.y=clampf(anchor_rect.position.y,visible.position.y+3,visible.end.y-anchor_rect.size.y-3)
	var rect: Rect2=Rect2(Vector2(anchor_rect.position.x,anchor_rect.get_center().y-HEALTHBAR_HEIGHT*.5),Vector2(width,HEALTHBAR_HEIGHT))
	var ratio: float=clampf(float(actor.get("hp",0))/maxf(1,float(actor.get("maxHp",0))),0,1)
	return {"anchor":anchor,"anchorRect":anchor_rect,"rect":rect,"fillRect":Rect2(rect.position+Vector2(1,0),Vector2((width-2)*ratio,HEALTHBAR_HEIGHT)),"ratio":ratio,"color":HEALTHBAR_FRIENDLY_COLOR if friendly else HEALTHBAR_HOSTILE_COLOR,"backgroundColor":HEALTHBAR_BACKGROUND_COLOR,"text":"","projected":projected,"flags":flags,"clamped":rect.get_center().distance_to(Vector2(anchor.x,anchor.y-HEALTHBAR_ANCHOR_HEIGHT*.5))>.01}

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

func _selected_name_text_layout(unit: Dictionary) -> Dictionary:
	var font: Font = GameFonts.japanese()
	var jp: String=str(unit.get("jp",""))
	var reading: String=str(unit.get("reading",""))
	var key: String = str(font.get_instance_id())+":"+jp+":"+reading+":"+JSON.stringify(unit.get("parts",[]))
	if selected_name_text_cache.has(key): return selected_name_text_cache[key]
	var label: Control = RubyText.new()
	label.font = font
	label.ink = Color("fff9ec")
	label.reading_ink = Color("fff9ec")
	label.reading_group_palette[0] = Color("ffe6a3")
	label.reading_group_palette[1] = Color("9fe7ff")
	label.size = Vector2(592,100)
	label.set_word({"jp":jp,"reading":reading,"parts":unit.get("parts",[])},20,false)
	var measured: Dictionary = label.get_text_layout()
	var bounds: Rect2 = Rect2()
	var first: bool = true
	for run in measured.runs:
		bounds = run.bounds if first else bounds.merge(run.bounds)
		first = false
	var runs: Array = []
	for source_run in measured.runs:
		var run: Dictionary = source_run.duplicate()
		run["position"] = run.position-bounds.position+Vector2(4,4)
		run["bounds"] = Rect2(run.bounds.position-bounds.position+Vector2(4,4),run.bounds.size)
		run["font"] = label.reading_font if str(run.role)=="reading" else font
		runs.append(run)
	var result: Dictionary = {"runs":runs,"size":bounds.size+Vector2(8,8),"colouredGroups":measured.colouredGroups}
	selected_name_text_cache[key] = result
	label.free()
	return result

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
	for unit in units:
		var p: Vector2 = _screen(unit.position)
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
				for run in names.runs:
					actor_overlay.draw_string_outline(run.font,run.position,run.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size),3,Color("101410"))
					actor_overlay.draw_string(run.font,run.position,run.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size),Color(run.color))
	for enemy in enemies:
		if _enemy_visible(enemy) and float(enemy.hp)>0: _draw_enemy_role_marker(enemy,actor_overlay)
		if running and not between_waves and not finished and _enemy_visible(enemy) and float(enemy.hp)>0: _draw_actor_health(enemy,false,actor_overlay)
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
			var text_layout: Dictionary = _selected_name_text_layout({"jp":"支援 "+seconds+"秒","reading":"しえん"+seconds+"びょう","parts":[{"text":"支","reading":"し"},{"text":"援","reading":"えん"},{"text":" "+seconds,"reading":""},{"text":"秒","reading":"びょう"}]})
			var label_position: Vector2 = p+Vector2(17,-text_layout.size.y)
			label_position.x = clampf(label_position.x,field_rect.position.x+7,field_rect.end.x-text_layout.size.x-7)
			label_position.y = clampf(label_position.y,field_rect.position.y+7,field_rect.end.y-text_layout.size.y-7)
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
	for aura in active_auras():
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
