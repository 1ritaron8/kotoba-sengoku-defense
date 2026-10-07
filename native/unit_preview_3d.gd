extends Control
## One existing detailed soldier on a fixed, transparent demonstration stage.

const Actor = preload("res://native/sengoku_actor_3d.gd")
const UPDATE_SECONDS: float = 1.0/30.0
const LOOP_SECONDS: float = 4.0
const ACTION_START: float = 1.6
const MAX_RENDER_SIZE: Vector2 = Vector2(640,768)
const RENDER_SCALE: float = 1.5
const UNIT_TYPES: Array[String] = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]

var unit_id: String = "archer"
var evolution_stage: int = 0
var available: bool = true
var actor: Node3D
var viewport: SubViewport
var camera: Camera3D
var stage: Node3D
var image: TextureRect
var demo_clock: float = 0.0
var pose_updates: int = 0
var _accumulated: float = 0.0
var _active: bool = false
var _framing: Rect2 = Rect2()

func configure(id: String, evolution: int = 0, unlocked: bool = true) -> void:
	var next_id: String = id if id in UNIT_TYPES else "archer"
	var next_evolution: int = clampi(evolution,0,2)
	var changed: bool = next_id!=unit_id or next_evolution!=evolution_stage
	unit_id = next_id
	evolution_stage = next_evolution
	available = unlocked
	if is_node_ready():
		if changed: _build_actor()
		_update_tint()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	viewport = SubViewport.new()
	viewport.name = "UnitDemonstrationViewport"
	viewport.size = Vector2i(256,256)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	stage = Node3D.new()
	stage.name = "UnitDemonstrationStage"
	viewport.add_child(stage)
	camera = Camera3D.new()
	camera.name = "UnitDemonstrationCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = .1
	camera.far = 20.0
	camera.position = Vector3(3.2,2.4,-5.4)
	stage.add_child(camera)
	camera.look_at(Vector3(0,1,0))
	camera.current = true
	var environment = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0,0,0,0)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("eadbc4")
	settings.ambient_light_energy = .75
	environment.environment = settings
	stage.add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38,-28,0)
	light.light_color = Color("fff0d8")
	light.light_energy = 1.05
	light.shadow_enabled = false
	stage.add_child(light)
	image = TextureRect.new()
	image.name = "UnitDemonstrationImage"
	image.texture = viewport.get_texture()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_actor()
	_update_tint()
	resized.connect(_resize_stage)
	visibility_changed.connect(_sync_activity)
	_resize_stage()
	_sync_activity()

func _build_actor() -> void:
	if is_instance_valid(actor):
		stage.remove_child(actor)
		actor.queue_free()
	actor = Actor.new()
	actor.name = "BattlefieldUnit"
	stage.add_child(actor)
	# Reuse the original high-detail soldier face, body, armour and equipment.
	# The detail flag does not create or select a historical commander model.
	actor.configure(unit_id,false,27,true,evolution_stage)
	if unit_id=="samurai": actor.scale = Vector3.ONE*1.07
	demo_clock = 0.0
	_accumulated = 0.0
	_cache_framing()
	_fit_camera()
	_apply_pose()

func _update_tint() -> void:
	if image!=null: image.modulate = Color.WHITE if available else Color(.66,.62,.56,1)

func _pose_at(value: float) -> Dictionary:
	var cycle: float = fposmod(value,LOOP_SECONDS)
	var duration: float = .6 if unit_id=="monk" else .5
	var performing: bool = cycle>=ACTION_START and cycle<ACTION_START+duration
	var animation: String = ("heal" if unit_id=="monk" else "attack") if performing else "idle"
	return {"type":unit_id,"animation":animation,"animationClock":cycle-ACTION_START if performing else value,"animationPhase":0.0,"attackDuration":.5,"healDuration":.6,"healing":performing and unit_id=="monk","supportState":"heal" if performing and unit_id=="monk" else "guard" if unit_id=="naginata" else "idle","aimX":0.0,"aimY":-1.0,"sailing":false,"dead":false}

func _apply_pose() -> void:
	if is_instance_valid(actor):
		actor.apply_state(_pose_at(demo_clock))
		pose_updates += 1
	if _active and viewport!=null: viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_demo_time(value: float) -> void:
	# Deterministic capture/inspection does not touch any Game or saved state.
	demo_clock = maxf(0.0,value) if is_finite(value) else 0.0
	_accumulated = 0.0
	_apply_pose()

func _process(delta: float) -> void:
	if not _active: return
	var elapsed: float = maxf(0.0,delta)
	demo_clock += elapsed
	_accumulated += elapsed
	if _accumulated>=UPDATE_SECONDS:
		_accumulated = fposmod(_accumulated,UPDATE_SECONDS)
		_apply_pose()

func _sync_activity() -> void:
	_active = is_inside_tree() and is_visible_in_tree() and size.x>1 and size.y>1
	set_process(_active)
	if viewport==null: return
	viewport.disable_3d = not _active
	viewport.process_mode = Node.PROCESS_MODE_ALWAYS if _active else Node.PROCESS_MODE_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if _active else SubViewport.UPDATE_DISABLED

func _exit_tree() -> void:
	_active = false
	set_process(false)
	if is_instance_valid(viewport):
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _resize_stage() -> void:
	if viewport==null: return
	var requested: Vector2 = size*RENDER_SCALE
	var factor: float = minf(1.0,minf(MAX_RENDER_SIZE.x/maxf(1,requested.x),MAX_RENDER_SIZE.y/maxf(1,requested.y)))
	viewport.size = Vector2i(mini(int(MAX_RENDER_SIZE.x),maxi(2,ceili(requested.x*factor))),mini(int(MAX_RENDER_SIZE.y),maxi(2,ceili(requested.y*factor))))
	_fit_camera()
	_sync_activity()

func _mesh_points() -> PackedVector3Array:
	var points = PackedVector3Array()
	for mesh in actor.meshes:
		# The parent joint distinguishes the hidden boat from the soldier.
		if not mesh.get_parent().is_visible_in_tree(): continue
		var bounds: AABB = mesh.get_aabb()
		for corner in range(8):
			points.append(mesh.global_transform*bounds.get_endpoint(corner))
	return points

func _cache_framing() -> void:
	var bounds: Rect2 = Rect2()
	var first: bool = true
	for time in [0.0,.8,1.6,1.725,1.85,1.933333,2.0,2.1,2.2]:
		actor.apply_state(_pose_at(time))
		for point in _mesh_points():
			var projected: Vector2 = Vector2(camera.global_basis.x.dot(point),camera.global_basis.y.dot(point))
			if first:
				bounds = Rect2(projected,Vector2.ZERO)
				first = false
			else: bounds = bounds.expand(projected)
	_framing = bounds
	var center: Vector3 = camera.global_basis.x*bounds.get_center().x+camera.global_basis.y*bounds.get_center().y
	var direction: Vector3 = camera.global_basis.z
	camera.position = center+direction*6.0
	camera.look_at(center)

func _fit_camera() -> void:
	if camera==null or viewport==null or not _framing.has_area(): return
	var aspect: float = float(viewport.size.x)/maxf(1.0,float(viewport.size.y))
	camera.size = maxf(_framing.size.y,_framing.size.x/aspect)*1.16

func projected_bounds() -> Rect2:
	var bounds: Rect2 = Rect2()
	var first: bool = true
	for point in _mesh_points():
		var projected: Vector2 = camera.unproject_position(point)
		if first:
			bounds = Rect2(projected,Vector2.ZERO)
			first = false
		else: bounds = bounds.expand(projected)
	return bounds

func diagnostics() -> Dictionary:
	return {"type":unit_id,"evolution":evolution_stage,"active":_active,"clock":demo_clock,"poseUpdates":pose_updates,"animation":str(actor.current_state.get("animation","")) if is_instance_valid(actor) else "","renderSize":viewport.size if viewport!=null else Vector2i.ZERO,"renderMode":viewport.render_target_update_mode if viewport!=null else 0,"skinned":is_instance_valid(actor) and actor.skinned_renderer!=null,"heroDetail":actor.hero_detail if is_instance_valid(actor) else false,"maxRenderFps":30}
