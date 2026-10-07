extends SceneTree

const OUTPUT = "res://tests/qa_3d_probe"
const WIDTH = 22.0
const ANGLE = 65.0
var checks: int = 0
var failures: Array = []
var results: Dictionary = {}
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var receiver: MeshInstance3D
var actor: Node3D
var animation_player: AnimationPlayer
var arm: Node3D
var environment: Environment

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures.append(name)
		push_error(name)

func _run() -> void:
	# The launcher uses WindowStyle Hidden; keep the root rendering target active.
	viewport = SubViewport.new()
	viewport.size = Vector2i(768, 512)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	root.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	_build_scene()
	await process_frame
	_probe_mapping()
	await _probe_animation()
	results["version"] = Engine.get_version_info()
	results["displayDriver"] = DisplayServer.get_name()
	results["videoAdapter"] = RenderingServer.get_video_adapter_name()
	results["renderer"] = str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	results["gpuRendered"] = DisplayServer.get_name() != "headless"
	if DisplayServer.get_name() != "headless":
		await _probe_pixels()
		await _probe_photo_ground()
	else:
		results["pixelTests"] = "Skipped: headless display uses the dummy renderer; no GPU proof."
	results["checks"] = checks
	results["failures"] = failures
	var report = FileAccess.open(OUTPUT + ".json", FileAccess.WRITE)
	if report:
		report.store_string(JSON.stringify(results, "  "))
		report.close()
	print("QA_3D_PROBE ", JSON.stringify(results))
	quit(0 if failures.is_empty() else 1)

func _build_scene() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = WIDTH
	camera.near = 0.1
	camera.far = 45.0
	camera.position = Vector3(0, sin(deg_to_rad(ANGLE)) * 16.0, cos(deg_to_rad(ANGLE)) * 16.0)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true
	environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.67, 0.70)
	environment.ambient_light_energy = 0.65
	var environment_node = WorldEnvironment.new()
	environment_node.environment = environment
	world.add_child(environment_node)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color(1.0, 0.92, 0.81)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.1
	world.add_child(sun)
	receiver = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(40, 34)
	receiver.mesh = plane
	receiver.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(receiver)
	actor = Node3D.new()
	actor.name = "Actor"
	world.add_child(actor)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.19, 0.30)
	material.metallic = 0.55
	material.roughness = 0.44
	var body = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.34
	capsule.height = 1.8
	body.mesh = capsule
	body.material_override = material
	body.position.y = 0.9
	actor.add_child(body)
	arm = Node3D.new()
	arm.name = "Arm"
	arm.position = Vector3(0.43, 1.3, 0)
	actor.add_child(arm)
	var arm_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.15, 0.65, 0.15)
	arm_mesh.mesh = box
	arm_mesh.material_override = material
	arm_mesh.position.y = -0.25
	arm.add_child(arm_mesh)
	animation_player = AnimationPlayer.new()
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.add_child(animation_player)
	var animation = Animation.new()
	animation.length = 1.0
	animation.loop_mode = Animation.LOOP_LINEAR
	var track = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("Arm:rotation:x"))
	animation.track_insert_key(track, 0.0, 0.0)
	animation.track_insert_key(track, 0.25, 0.8)
	animation.track_insert_key(track, 0.5, 0.0)
	animation.track_insert_key(track, 0.75, -0.8)
	animation.track_insert_key(track, 1.0, 0.0)
	var library = AnimationLibrary.new()
	library.add_animation("walk", animation)
	animation_player.add_animation_library("", library)
	_check(is_equal_approx(material.metallic,0.55) and is_equal_approx(material.roughness,0.44), "PBR material properties are available")

func _probe_mapping() -> void:
	var samples: Array = []
	var ground = Plane(Vector3.UP, 0)
	for dimensions in [Vector2i(768,512), Vector2i(1100,600), Vector2i(1280,720), Vector2i(640,640)]:
		viewport.size = dimensions
		var depth = WIDTH / (float(dimensions.x) / dimensions.y) / sin(deg_to_rad(ANGLE))
		for uv in [Vector2(0.05,0.05), Vector2(0.95,0.05), Vector2(0.5,0.5), Vector2(0.05,0.95), Vector2(0.95,0.95)]:
			var pixel: Vector2 = uv * Vector2(dimensions)
			var projected: Variant = ground.intersects_ray(camera.project_ray_origin(pixel), camera.project_ray_normal(pixel))
			_check(projected is Vector3, "Ground ray intersects for %s %s" % [dimensions, uv])
			if not projected is Vector3:
				continue
			var expected = Vector3((uv.x-0.5)*WIDTH, 0, (uv.y-0.5)*depth)
			var returned = camera.unproject_position(projected)
			var error: float = projected.distance_to(expected)
			var roundtrip: float = returned.distance_to(pixel)
			_check(error < 0.001 and roundtrip < 0.1, "Orthographic width/depth and normalized roundtrip")
			samples.append({"size":str(dimensions),"uv":str(uv),"worldError":error,"pixelError":roundtrip})
	viewport.size = Vector2i(768,512)
	results["mapping"] = samples

func _probe_animation() -> void:
	animation_player.play("walk")
	animation_player.seek(0.25, true, true)
	_check(absf(arm.rotation.x-0.8) < 0.001, "Manual seek updates the actual joint immediately")
	var paused_value: float = arm.rotation.x
	await process_frame
	await process_frame
	_check(absf(arm.rotation.x-paused_value) < 0.001, "No automatic animation advancement in manual mode")
	animation_player.seek(0, true, true)
	animation_player.advance(0.125*2.0)
	_check(absf(arm.rotation.x-0.8) < 0.001, "External speed 2x advances only once")
	results["animation"] = {"manual":true,"pauseStable":is_equal_approx(arm.rotation.x,0.8),"externalSpeed2xPosition":animation_player.current_animation_position}

func _shadow_material(color: Color, shader_mode: bool = false) -> Material:
	if shader_mode:
		var shader = Shader.new()
		shader.code = "shader_type spatial; render_mode blend_mix, depth_draw_opaque, cull_back, shadow_to_opacity; void fragment(){ ALBEDO=vec3(0.0); }"
		var shader_material = ShaderMaterial.new()
		shader_material.shader = shader
		return shader_material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shadow_to_opacity = true
	material.roughness = 1.0
	return material

func _capture(label: String) -> Image:
	for unused in range(5):
		await process_frame
	RenderingServer.force_draw(false)
	var image: Image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.save_png(OUTPUT + "_" + label + ".png")
	return image

func _pixel_stats(image: Image) -> Dictionary:
	var nonzero = 0
	var opaque = 0
	var alpha_total: float = 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var alpha = image.get_pixel(x,y).a
			if alpha > 0.01: nonzero += 1
			if alpha > 0.9: opaque += 1
			alpha_total += alpha
	return {"nonzero":nonzero,"opaque":opaque,"alphaTotal":alpha_total,"cornerAlpha":image.get_pixel(8,8).a}

func _probe_pixels() -> void:
	actor.visible = false
	receiver.visible = false
	var empty = await _capture("empty")
	var empty_stats = _pixel_stats(empty)
	_check(int(empty_stats.nonzero) == 0, "Empty transparent 3D viewport has no opaque background")
	results["empty"] = empty_stats
	actor.visible = true
	var actor_only = await _capture("actor")
	var actor_stats = _pixel_stats(actor_only)
	_check(int(actor_stats.opaque)>100 and float(actor_stats.cornerAlpha)==0, "Real PBR geometry renders with transparent margins")
	results["actorOnly"] = actor_stats
	receiver.visible = true
	var opaque_material = StandardMaterial3D.new()
	opaque_material.albedo_color = Color.WHITE
	opaque_material.roughness = 1.0
	receiver.material_override = opaque_material
	sun.shadow_enabled = false
	var opaque_without_shadow = await _capture("opaque_no_shadow")
	sun.shadow_enabled = true
	var opaque_with_shadow = await _capture("opaque_shadow")
	var darkened_pixels = 0
	for y in range(opaque_with_shadow.get_height()):
		for x in range(opaque_with_shadow.get_width()):
			if actor_only.get_pixel(x,y).a < 0.01:
				var before = opaque_without_shadow.get_pixel(x,y)
				var after = opaque_with_shadow.get_pixel(x,y)
				if before.r-after.r > 0.02: darkened_pixels += 1
	results["opaquePlaneShadowPixels"] = darkened_pixels
	_check(darkened_pixels>20, "Opaque plane receives a real dynamic directional shadow")
	var modes: Array = []
	for name in ["black_standard", "white_standard", "black_shader", "black_custom_light"]:
		if name == "black_custom_light":
			var custom_shader = Shader.new()
			custom_shader.code = "shader_type spatial; render_mode blend_mix, depth_draw_never, cull_back, ambient_light_disabled, specular_disabled; void fragment(){ ALBEDO=vec3(0.0); ALPHA=0.0; } void light(){ DIFFUSE_LIGHT=vec3(0.0); SPECULAR_LIGHT=vec3(0.0); ALPHA=clamp(1.0-ATTENUATION,0.0,1.0)*0.65; }"
			var custom_material = ShaderMaterial.new()
			custom_material.shader = custom_shader
			receiver.material_override = custom_material
		else:
			receiver.material_override = _shadow_material(Color.WHITE if name == "white_standard" else Color.BLACK, name == "black_shader")
		sun.shadow_enabled = false
		var no_shadow = await _capture(name + "_unlitshadow")
		var baseline_stats = _pixel_stats(no_shadow)
		sun.shadow_enabled = true
		var with_shadow = await _capture(name + "_shadow")
		var shadow_stats = _pixel_stats(with_shadow)
		var gained_shadow = 0
		for y in range(with_shadow.get_height()):
			for x in range(with_shadow.get_width()):
				if actor_only.get_pixel(x,y).a < 0.01 and with_shadow.get_pixel(x,y).a-no_shadow.get_pixel(x,y).a > 0.03:
					gained_shadow += 1
		modes.append({"mode":name,"off":baseline_stats,"on":shadow_stats,"shadowPixelsOutsideActor":gained_shadow})
		print("SHADOW_MODE ", JSON.stringify(modes[-1]))
	results["shadowModes"] = modes
	var working: bool = false
	for mode in modes:
		if int(mode.shadowPixelsOutsideActor)>20 and float(mode.on.cornerAlpha)==0 and int(mode.off.nonzero)<int(actor_stats.nonzero)+200:
			working = true
	_check(working, "At least one native shadow catcher adds only cast-shadow alpha on a transparent plane")

func _probe_photo_ground() -> void:
	var photo = Image.load_from_file("res://assets/map-temple.png")
	var photo_texture = ImageTexture.create_from_image(photo)
	var photo_shader = Shader.new()
	photo_shader.code = "shader_type spatial; render_mode ambient_light_disabled, specular_disabled, cull_back; uniform sampler2D photo : source_color, filter_linear; void fragment(){ ALBEDO=texture(photo,UV).rgb; ROUGHNESS=1.0; } void light(){ DIFFUSE_LIGHT += vec3(0.82+0.18*ATTENUATION); }"
	var photo_material = ShaderMaterial.new()
	photo_material.shader = photo_shader
	photo_material.set_shader_parameter("photo", photo_texture)
	var ground_mesh = PlaneMesh.new()
	ground_mesh.size = Vector2(WIDTH, WIDTH / (float(viewport.size.x)/viewport.size.y) / sin(deg_to_rad(ANGLE)))
	receiver.mesh = ground_mesh
	receiver.material_override = photo_material
	receiver.visible = true
	actor.visible = false
	sun.shadow_enabled = false
	var photo_without_actor = await _capture("photo_empty")
	var color_samples: Array = []
	var max_error: float = 0.0
	for uv in [Vector2(0.1,0.1),Vector2(0.9,0.1),Vector2(0.1,0.9),Vector2(0.9,0.9),Vector2(0.5,0.5)]:
		var x = int(uv.x*viewport.size.x)
		var y = int(uv.y*viewport.size.y)
		var expected = photo.get_pixel(int((x+0.5)/viewport.size.x*photo.get_width()),int((y+0.5)/viewport.size.y*photo.get_height()))
		var actual = photo_without_actor.get_pixel(x,y)
		var error = maxf(absf(expected.r-actual.r),maxf(absf(expected.g-actual.g),absf(expected.b-actual.b)))
		max_error=maxf(max_error,error)
		color_samples.append({"uv":str(uv),"expected":str(expected),"actual":str(actual),"colorError":error})
	_check(max_error<0.09, "Photo texture ground maps to the same bitmap field orientation and colors")
	actor.visible = true
	var without_shadow = await _capture("photo_no_shadow")
	sun.shadow_enabled = true
	var with_shadow = await _capture("photo_shadow")
	var shadow_pixels = 0
	for y in range(with_shadow.get_height()):
		for x in range(with_shadow.get_width()):
			if absf(photo_without_actor.get_pixel(x,y).r-without_shadow.get_pixel(x,y).r)<0.01:
				if without_shadow.get_pixel(x,y).r-with_shadow.get_pixel(x,y).r>0.02:
					shadow_pixels+=1
	results["photoGround"]={"colorSamples":color_samples,"maxColorError":max_error,"shadowPixels":shadow_pixels,"material":"opaque, ambient_light_disabled, specular_disabled; DIFFUSE_LIGHT += vec3(0.82+0.18*ATTENUATION)"}
	_check(shadow_pixels>20, "Opaque photo ground receives dynamic shadows while preserving its bitmap UV mapping")
	var tuning: Array = []
	for settings in [{"name":"near_far_tuned_bias_default","far":45.0,"bias":0.1,"normalBias":2.0},{"name":"far_default_bias_tuned","far":4000.0,"bias":0.02,"normalBias":0.1}]:
		camera.far = settings.far
		sun.shadow_bias = settings.bias
		sun.shadow_normal_bias = settings.normalBias
		sun.shadow_enabled = false
		var before = await _capture(settings.name + "_no_shadow")
		sun.shadow_enabled = true
		var after = await _capture(settings.name + "_shadow")
		var gained = 0
		for y in range(after.get_height()):
			for x in range(after.get_width()):
				if absf(photo_without_actor.get_pixel(x,y).r-before.get_pixel(x,y).r)<0.01 and before.get_pixel(x,y).r-after.get_pixel(x,y).r>0.02:
					gained+=1
		settings["shadowPixels"] = gained
		tuning.append(settings)
	results["shadowTuning"] = tuning
	camera.far = 45.0
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.1
