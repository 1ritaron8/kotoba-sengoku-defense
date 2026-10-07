extends Control

const Troops = preload("res://native/troops_3d.gd")
const Actor = preload("res://native/sengoku_actor_3d.gd")
var troops: Control
var hero: Node3D
var hero_viewport: SubViewport
var clock: float = 0.0
var samples: Array = []

func _ready() -> void:
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
	for source in samples:
		source.animation = "attack" if source.friendly and attack else ("idle" if source.friendly else "walk")
		source.animationClock = fmod(clock,3.0) if source.animation == "attack" else clock
		source.aimX = sin(clock*0.25)*0.5
	troops.manual_states = samples
	if hero != null:
		hero.apply_state({"animation":"attack" if attack else "idle","animationClock":fmod(clock,3.0) if attack else clock,"aimX":0.0,"aimY":-1.0})
