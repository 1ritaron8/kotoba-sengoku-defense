extends Control

const Troops = preload("res://native/troops_3d.gd")
const Actor = preload("res://native/sengoku_actor_3d.gd")
const PaintedActors = preload("res://native/painted_actor_renderer.gd")
const PaintedStage = preload("res://native/painted_stage.gd")
const PaintedBattlefield = preload("res://native/painted_battlefield.gd")
var troops: Control
var hero: Node3D
var hero_viewport: SubViewport
var clock: float = 0.0
var samples: Array = []
var painted_renderer: RefCounted
var painted_field: RefCounted
var painted_mode: bool = false
const PAINTED_TYPES: Array[String] = ["archer","spear","samurai","gunner","monk","commander","ninja"]
const PAINTED_FIELD: Rect2 = Rect2(20,54,1100,620)

func _ready() -> void:
	painted_mode=not bool(ProjectSettings.get_setting("application/config/use_3d_units",false))
	if painted_mode:
		_ready_painted()
		return
	DisplayServer.window_set_title("말의 전장 · 3D 병력 검수")
	var maps = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	troops = Troops.new()
	add_child(troops)
	troops.position = Vector2(20,54)
	troops.set_field_size(Vector2(1100,620))
	troops.set_stage(maps[0])
	var types: Array = ["archer","spear","samurai","commander","enemy_light","enemy_heavy"]
	for index in range(types.size()):
		samples.append({"id":index+1,"type":types[index],"friendly":index<4,"x":0.19+index*0.115,"y":0.64,"animation":"idle" if index<4 else "walk","animationClock":0.0,"animationPhase":index*0.19,"aimX":-0.32,"aimY":-1.0})
	var title: Label = Label.new()
	title.text = "전장 65° · 실제 관절 / 표면 재질 / 지면 그림자"
	title.position = Vector2(24,12)
	title.add_theme_font_size_override("font_size",22)
	add_child(title)
	var note: Label = Label.new()
	note.text = "궁병       창병       사무라이       장수       경장병       중장병\n3초마다 대기 → 공격 전환 / 적 보행은 실제 방향 회전"
	note.position = Vector2(80,695)
	note.add_theme_font_size_override("font_size",18)
	add_child(note)
	_create_hero()

func _ready_painted() -> void:
	DisplayServer.window_set_title("말의 전장 · 2D 병력 검수")
	painted_renderer=PaintedActors.new()
	painted_field=PaintedBattlefield.new()
	var maps: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	if maps is Array and not maps.is_empty(): painted_field.configure(PaintedStage.apply(maps[0]))
	for index in range(PAINTED_TYPES.size()):
		samples.append({"id":index+1,"type":PAINTED_TYPES[index],"friendly":true,"x":.16+index*.105,"y":.66,"animation":"idle","animationClock":0.0,"animationPhase":index*.19,"aimX":-1.0,"aimY":1.0})
	var title: Label = Label.new()
	title.text="실제 전장과 같은 2D 병사 · 7개 병종"
	title.position=Vector2(24,12)
	title.add_theme_font_size_override("font_size",22)
	add_child(title)
	var note: Label = Label.new()
	note.text="궁병       창병       사무라이       조총병       승병       기마 무장       닌자\n방향별 2개 보행 포즈 · 공격 시 작은 시각 이동 / 전투 판정 없음"
	note.position=Vector2(80,695)
	note.add_theme_font_size_override("font_size",18)
	add_child(note)
	queue_redraw()

func _create_hero() -> void:
	hero_viewport = SubViewport.new()
	hero_viewport.size = Vector2i(200,240)
	hero_viewport.transparent_bg = true
	hero_viewport.own_world_3d = true
	hero_viewport.msaa_3d = Viewport.MSAA_4X
	hero_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(hero_viewport)
	var world: Node3D = Node3D.new()
	hero_viewport.add_child(world)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	camera.position = Vector3(2.8,1.9,-4)
	camera.current = true
	camera.near = 0.1
	camera.far = 45
	world.add_child(camera)
	camera.look_at(Vector3(0,0.86,0))
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-35,0)
	light.light_energy = 1.2
	world.add_child(light)
	var environment: WorldEnvironment = WorldEnvironment.new()
	var settings: Environment = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0,0,0,0)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c7cec2")
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	world.add_child(environment)
	hero = Actor.new()
	world.add_child(hero)
	hero.configure("samurai",false,27)
	var image: TextureRect = TextureRect.new()
	image.texture = hero_viewport.get_texture()
	image.position = Vector2(1150,100)
	image.size = Vector2(200,240)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(image)
	var text: Label = Label.new()
	text.position = Vector2(1170,360)
	text.text = "근접 150px 검수"
	add_child(text)

func _process(delta: float) -> void:
	clock += delta
	var attack: bool = fmod(clock,3.0)<0.5
	if painted_mode:
		for source in samples:
			source.animation="heal" if attack and str(source.type)=="monk" else "attack" if attack else "walk"
			source.animationClock=fmod(clock,3.0) if attack else clock
			source.aimX=1.0 if fmod(clock,6.0)<3.0 else -1.0
			source.aimY=-source.aimX
		queue_redraw()
		return
	for source in samples:
		source.animation = "attack" if source.friendly and attack else ("idle" if source.friendly else "walk")
		source.animationClock = fmod(clock,3.0) if source.animation == "attack" else clock
		source.aimX = sin(clock*0.25)*0.5
	troops.manual_states = samples
	if hero != null:
		hero.apply_state({"animation":"attack" if attack else "idle","animationClock":fmod(clock,3.0) if attack else clock,"aimX":0.0,"aimY":-1.0})

func _draw() -> void:
	if not painted_mode: return
	if painted_field!=null and painted_field.is_ready(): draw_texture_rect(painted_field.texture,PAINTED_FIELD,false,Color.WHITE)
	if painted_renderer==null or not painted_renderer.is_ready(): return
	for source in samples:
		var foot: Vector2 = PAINTED_FIELD.position+Vector2(float(source.x),float(source.y))*PAINTED_FIELD.size
		painted_renderer.draw_actor(self,source,foot,true,44.0,Vector2(float(source.aimX),float(source.aimY)))
	painted_renderer.draw_actor(self,{"type":"samurai","animation":"idle"},Vector2(1250,340),true,150.0,Vector2(-1,1))

func diagnostics() -> Dictionary:
	return {"renderMode":"painted2d" if painted_mode else "3d","unitTypes":PAINTED_TYPES.duplicate() if painted_mode else [],"realUnitSamples":samples.size(),"world3D":is_instance_valid(troops) or is_instance_valid(hero_viewport),"ready":painted_renderer!=null and painted_renderer.is_ready() if painted_mode else is_instance_valid(troops),"animation":"two authored walk poses plus presentation transforms" if painted_mode else "articulated"}
