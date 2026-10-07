extends SceneTree

const Battlefield = preload("res://native/battlefield_3d.gd")
const RenderedArt = preload("res://native/rendered_battlefield_helpers.gd")
const Materials = preload("res://native/battlefield_materials.gd")
const Actor = preload("res://native/sengoku_actor_3d.gd")
const Game = preload("res://native/game.gd")
const WIDTH: float = 18.5
const ELEVATION: float = 50.0
const DEPTH: float = WIDTH/(1280.0/720.0)/sin(deg_to_rad(ELEVATION))
var checks: int = 0
var failures: Array[String] = []
var report: Dictionary = {}
var gpu: bool = false

func _initialize() -> void:
	Engine.max_fps = 60
	gpu = "--gpu" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(condition: bool,note: String) -> void:
	checks += 1
	if not condition:
		failures.append(note)
		push_error("RENDERED_BATTLEFIELD: "+note)

func _write_manifest(path: String,value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	RenderedArt.release_shared_resources()

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/native-battlefield-hybrid-").to_lower()):
		push_error("An isolated native-battlefield-hybrid profile is required")
		quit(2)
		return
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var source: Dictionary = maps[0]
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if gpu else SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var world: Node3D = Node3D.new()
	viewport.add_child(world)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = .32
	world.add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58,-35,0)
	sun.light_color = Color("fff1d5")
	sun.light_energy = 1.12
	sun.shadow_enabled = true
	sun.shadow_bias = .10
	sun.shadow_normal_bias = .80
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45
	sun.directional_shadow_fade_start = 1.0
	world.add_child(sun)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.light_cull_mask = 2
	fill.light_energy = .12
	fill.rotation_degrees = Vector3(-50,145,0)
	world.add_child(fill)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = WIDTH
	camera.near = .1
	camera.far = 45
	camera.current = true
	camera.position = Vector3(0,30,30/tan(deg_to_rad(ELEVATION)))
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var battlefield: Node3D = Battlefield.new()
	world.add_child(battlefield)
	var started: int = Time.get_ticks_msec()
	battlefield.configure(source,WIDTH,DEPTH,ELEVATION)
	var info: Dictionary = battlefield.diagnostics()
	var layer: Dictionary = battlefield.render_layer_contract()
	info["initialBuildMilliseconds"] = Time.get_ticks_msec()-started
	report["battlefield"] = info
	check(layer.mode == "rendered","Manifest selects current generated artwork")
	check(layer.rawArtHashVerified and layer.sourceDataVerified,"Artwork hash and actual map source match manifest")
	check(not layer.staticGeometryVisible,"Generic trees, roads and roofs are absent over artwork")
	check(not layer.flatPhotoPlane and layer.heightPreserved,"Real relief remains the shared actor terrain")
	check(info.meshNodes == 1 and info.renderTrianglesUpperBound == 12288,"Only the physical terrain mesh is rendered")
	check(info.roadSegmentCount > 0 and info.landmarkCount > 0,"Physical road and landmark contracts remain available")
	if int(layer.coverage) < 40:
		check(not layer.distributionReady,"Partial artwork coverage is not distribution ready")
	else:
		check(layer.distributionReady,"Complete distinct artwork coverage is distribution ready")
	if "--casual-v3" in OS.get_cmdline_user_args():
		check("casual-v3" in str(layer.artPath),"The approved casual art direction is the actual selected first-stage resource")
	check(layer.dynamicShadowReceiver and layer.shadowReceiverLayer == 1,"Live unit shadows have the dedicated ground receiver")
	var arrays: Array = battlefield.ground_mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var worst_uv_error: float = 0.0
	for index in range(vertices.size()):
		var expected: Vector3 = battlefield.world_point(uv2[index])
		worst_uv_error = maxf(worst_uv_error,vertices[index].distance_to(expected))
	check(uv2.size() == vertices.size() and worst_uv_error < .0001,"All raised vertices preserve exact normalized artwork UV anchors")
	info["normalizedUVVertexError"] = worst_uv_error
	var rebuilds: int = battlefield.rebuild_count
	battlefield.configure(source,WIDTH,DEPTH,ELEVATION)
	check(battlefield.rebuild_count == rebuilds,"Unchanged configure rebuilds no terrain")
	var physical_hash: String = str(info.physicalGeometryFingerprint)
	check(JSON.stringify(battlefield._physical_contract(source)).sha256_text() == physical_hash,"Manifest and diagnostics use the same geometry fingerprint")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RenderedArt.MANIFEST_PATH))
	var original: Dictionary = manifest.duplicate(true)
	manifest.sourceMapsSha256 = "invalid"
	_write_manifest("user://invalid-manifest.json",manifest)
	var invalid_source: Dictionary = RenderedArt.resolve(source,physical_hash,"user://invalid-manifest.json")
	check(invalid_source.mode == "native" and invalid_source.reason == "source_data_changed","Stale source data cannot select artwork")
	manifest = original.duplicate(true)
	manifest.stages[0].sha256 = "0".repeat(64)
	_write_manifest("user://invalid-hash.json",manifest)
	var invalid_art: Dictionary = RenderedArt.resolve(source,physical_hash,"user://invalid-hash.json")
	check(invalid_art.mode == "native" and invalid_art.reason == "art_hash_mismatch","Modified image is rejected by the manifest hash")
	manifest = original.duplicate(true)
	manifest.stages[0].sourceGeometryFingerprint = "0".repeat(64)
	_write_manifest("user://invalid-geometry.json",manifest)
	var invalid_geometry: Dictionary = RenderedArt.resolve(source,physical_hash,"user://invalid-geometry.json")
	check(invalid_geometry.mode == "native" and invalid_geometry.reason == "source_geometry_changed" and not invalid_geometry.distributionReady,"Mismatched blueprint geometry cannot select artwork or mark a release ready")
	var missing: Dictionary = RenderedArt.resolve(source,physical_hash,"user://missing-manifest.json")
	check(missing.mode == "native" and not missing.distributionReady,"Missing art does not silently select legacy historical imagery")
	var preview: Dictionary = RenderedArt.resolve(source,physical_hash,"user://missing-manifest.json",true)
	check(preview.mode == "legacy_preview" and not preview.distributionReady,"Legacy artwork requires explicit non-release preview opt-in")
	manifest = original.duplicate(true)
	var entry: Dictionary = manifest.stages[0].duplicate(true)
	manifest.stages = []
	for config in maps:
		var copy: Dictionary = entry.duplicate(true)
		copy.stageId = str(config.id)
		manifest.stages.append(copy)
	_write_manifest("user://duplicated-art.json",manifest)
	var duplicated: Dictionary = RenderedArt.resolve(source,physical_hash,"user://duplicated-art.json")
	check(duplicated.coverage == 40 and not duplicated.distributionReady,"Forty copies of one art image cannot be marked ready")
	if gpu:
		await _gpu_checks(viewport,world,sun,environment,camera,battlefield,source)
	if "--all-rendered" in OS.get_cmdline_user_args():
		_all_rendered_checks(maps,battlefield,camera)
	var texture_paths: Array[String] = [str(layer.artPath)]
	for value in original.stages:
		var path: String = str(value.get("path",""))
		if not texture_paths.has(path) and FileAccess.file_exists(path):
			texture_paths.append(path)
	for path in ["res://assets/battlefields-rendered/stage-01-marune-v1.png","res://assets/map-forest.png","res://assets/battlefields/basic-forest.png"]:
		if not texture_paths.has(path) and FileAccess.file_exists(path):
			texture_paths.append(path)
	check(texture_paths.size() >= 4,"At least four available artwork resources exercise cache eviction")
	for texture_path in texture_paths.slice(0,4):
		var cached_art: Texture2D = Materials.rendered_art_texture(texture_path,FileAccess.get_sha256(texture_path))
		check(cached_art != null,"Artwork cache loads an actual available image")
	check(Materials.cache_diagnostics().renderedArtTextureCount <= 3,"Artwork texture cache stays bounded across map changes")
	world.free()
	viewport.free()
	Battlefield.release_shared_resources()
	var caches: Dictionary = Battlefield.shared_cache_diagnostics()
	check(caches.materials.renderedArtTextureCount == 0 and not caches.materials.renderedShaderCached,"Rendered texture and shader caches are released at exit")
	report["checks"] = checks
	report["failures"] = failures
	report["gpu"] = gpu
	var out: FileAccess = FileAccess.open("user://report.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"\t"))
	out.close()
	print("RENDERED_BATTLEFIELD checks=%d failures=%d gpu=%s" % [checks,failures.size(),str(gpu)])
	quit(0 if failures.is_empty() else 1)

func _all_rendered_checks(maps: Array,battlefield: Node3D,camera: Camera3D) -> void:
	var physical_fingerprints: Dictionary = {}
	var image_fingerprints: Dictionary = {}
	var stage_reports: Array = []
	check(maps.size() == 40,"All forty campaign stages are available for rendered coverage validation")
	for config in maps:
		var start: int = Time.get_ticks_msec()
		battlefield.configure(config,WIDTH,DEPTH,ELEVATION)
		var layer: Dictionary = battlefield.render_layer_contract()
		var info: Dictionary = battlefield.diagnostics()
		var id: String = str(config.id)
		check(layer.mode == "rendered" and layer.distributionReady and layer.coverage == 40,"Complete rendered campaign selects actual artwork: "+id)
		check(layer.rawArtHashVerified and layer.sourceDataVerified,"Actual artwork and geometry source hashes verified: "+id)
		check(info.sourceDataContractValid and info.meshNodes == 1 and not layer.staticGeometryVisible,"Shared terrain source remains valid without duplicate static props: "+id)
		check(not physical_fingerprints.has(info.physicalGeometryFingerprint),"Distinct paths, heights, landmarks and water independent of stage identifiers: "+id)
		check(not image_fingerprints.has(layer.get("artSha256","")),"Distinct actual artwork resource: "+id)
		physical_fingerprints[info.physicalGeometryFingerprint] = true
		image_fingerprints[layer.get("artSha256","")] = true
		if "--casual-v3" in OS.get_cmdline_user_args():
			check("casual-v3" in str(layer.artPath),"Approved casual direction is selected: "+id)
		var arrays: Array = battlefield.ground_mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var uv_error: float = 0.0
		for index in range(vertices.size()):
			uv_error = maxf(uv_error,vertices[index].distance_to(battlefield.world_point(uv2[index])))
		check(uv2.size() == 6305 and uv_error < .0001,"Artwork anchors match every actual height vertex: "+id)
		var projection_error: float = 0.0
		var wet_path_samples: int = 0
		var route_samples: int = 0
		for route in config.get("paths",[]):
			var points: Array = route.get("points",[])
			for segment in range(points.size()-1):
				var a: Vector2 = Vector2(float(points[segment].x),float(points[segment].y))
				var b: Vector2 = Vector2(float(points[segment+1].x),float(points[segment+1].y))
				for step in range(25):
					var p: Vector2 = a.lerp(b,float(step)/24.0)
					var actual: Vector3 = battlefield.world_point(p)
					var planar: Vector3 = Vector3((p.x-.5)*WIDTH,0,(p.y-.5)*DEPTH)
					projection_error = maxf(projection_error,camera.unproject_position(actual).distance_to(camera.unproject_position(planar)))
					if battlefield._is_water(p):
						wet_path_samples += 1
					check(absf(actual.y-battlefield.height_at(p)) < .0001,"Walking source uses the actual shared terrain height: "+id)
					route_samples += 1
		check(projection_error < .025,"Moving foot remains on the artwork road through all route samples: "+id)
		check(wet_path_samples == 0,"Authored walking routes avoid blocked deep water: "+id)
		for zone in config.get("buildZones",[]):
			check(not battlefield._is_water(Vector2(float(zone.x),float(zone.y))),"Actual tower deployment area avoids blocked water: "+id)
		var rebuilds: int = battlefield.rebuild_count
		battlefield.configure(config,WIDTH,DEPTH,ELEVATION)
		check(battlefield.rebuild_count == rebuilds,"Unchanged stage does not recreate physical geometry: "+id)
		check(Materials.cache_diagnostics().renderedArtTextureCount <= 3,"Artwork memory remains bounded across campaign traversal: "+id)
		stage_reports.append({"stageId":id,"artPath":layer.artPath,"artSha256":layer.get("artSha256",""),"physicalGeometryFingerprint":info.physicalGeometryFingerprint,"routeSamples":route_samples,"wetRouteSamples":wet_path_samples,"projectionErrorPixels":projection_error,"uvVertexError":uv_error,"heightMinimum":info.heightMinimum,"heightMaximum":info.heightMaximum,"waterRegions":info.waterRegionCount,"shallowCrossings":info.shallowCrossingCount,"buildMilliseconds":Time.get_ticks_msec()-start})
	report["renderedCampaign"] = stage_reports

func _capture(viewport: SubViewport) -> Image:
	for unused in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _gpu_checks(viewport: SubViewport,world: Node3D,sun: DirectionalLight3D,environment: WorldEnvironment,camera: Camera3D,battlefield: Node3D,source: Dictionary) -> void:
	var baseline: Image = await _capture(viewport)
	baseline.save_png(ProjectSettings.globalize_path("user://stage-01-artwork-no-actors.png"))
	var layer: Dictionary = battlefield.render_layer_contract()
	var original: Image = Image.load_from_file(ProjectSettings.globalize_path(str(layer.artPath)))
	var colour_error: float = 0.0
	var samples: int = 0
	for y in range(32,720-32,16):
		for x in range(32,1280-32,16):
			var expected: Color = original.get_pixel(mini(original.get_width()-1,int((x+.5)/1280.0*original.get_width())),mini(original.get_height()-1,int((y+.5)/720.0*original.get_height())))
			var actual: Color = baseline.get_pixel(x,y)
			colour_error += (absf(expected.r-actual.r)+absf(expected.g-actual.g)+absf(expected.b-actual.b))/3.0
			samples += 1
	colour_error /= maxi(samples,1)
	check(colour_error < .035,"Actual GPU keeps artwork colour without double lighting")
	report["meanSourceArtworkColourError"] = colour_error
	# Sun colour, energy and ambient all change here. The already-lit static
	# artwork remains unchanged; those lights still affect dynamic actors.
	sun.light_energy = 2.3
	sun.light_color = Color("789aff")
	environment.environment.ambient_light_energy = 1.1
	var lighting_changed: Image = await _capture(viewport)
	var static_change: float = _image_difference(baseline,lighting_changed)
	check(static_change < .002,"Static artwork stays stable under dynamic actor lighting")
	report["staticArtworkLightingMeanDifference"] = static_change
	sun.light_energy = 1.12
	sun.light_color = Color("fff1d5")
	environment.environment.ambient_light_energy = .32
	var points: Array = source.paths[0].points
	var actors: Array[Node3D] = []
	for index in range(4):
		var actor: Node3D = Actor.new()
		world.add_child(actor)
		actor.configure("spear" if index < 2 else "archer",index < 2,1)
		actor.set_process(false)
		actor.scale = Vector3.ONE*.70
		var value: Dictionary = points[mini(index+1,points.size()-1)]
		var norm: Vector2 = Vector2(float(value.x),float(value.y))
		actor.position = battlefield.world_point(norm)
		var flat: Vector3 = Vector3((norm.x-.5)*WIDTH,0,(norm.y-.5)*DEPTH)
		check(camera.unproject_position(actor.position).distance_to(camera.unproject_position(flat)) < .02,"Actor foot exactly matches artwork path anchor")
		actors.append(actor)
	var shadow_on: Image = await _capture(viewport)
	shadow_on.save_png(ProjectSettings.globalize_path("user://stage-01-artwork-actors-shadow-on.png"))
	report["visibleDrawCalls"] = viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	report["shadowDrawCalls"] = viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	report["renderedPrimitives"] = viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	# Keep actor lighting and meshes identical. Changing only the receiver's
	# shadow strength proves the changed pixels belong to ground shadows,
	# rather than different self-shading on the four character models.
	var material: ShaderMaterial = battlefield.ground_mesh.material_override
	var strength: float = float(material.get_shader_parameter("shadow_strength"))
	material.set_shader_parameter("shadow_strength",0.0)
	var no_receiver_shadow: Image = await _capture(viewport)
	var receiver_pixels: int = 0
	for y in range(0,720,2):
		for x in range(0,1280,2):
			var dark: Color = shadow_on.get_pixel(x,y)
			var light: Color = no_receiver_shadow.get_pixel(x,y)
			if light.r+light.g+light.b-dark.r-dark.g-dark.b > .055:
				receiver_pixels += 1
	check(receiver_pixels > 40 and receiver_pixels < 20000,"Ground receiver alone shows actual character shadows without changing character lighting")
	report["groundReceiverShadowSampledPixels"] = receiver_pixels
	material.set_shader_parameter("shadow_strength",strength)
	sun.shadow_enabled = false
	var shadow_off: Image = await _capture(viewport)
	shadow_off.save_png(ProjectSettings.globalize_path("user://stage-01-artwork-actors-shadow-off.png"))
	var changed: int = 0
	for y in range(0,720,2):
		for x in range(0,1280,2):
			var a: Color = shadow_on.get_pixel(x,y)
			var b: Color = shadow_off.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > .055:
				changed += 1
	check(changed > 300,"Actual moving-unit shadows visibly darken the artwork terrain")
	check(changed < 20000,"Shadow toggle changes local shadows without changing the whole artwork brightness")
	report["shadowChangedSampledPixels"] = changed
	for actor in actors:
		actor.free()
	if "--placements" in OS.get_cmdline_user_args():
		await _placement_capture(viewport,world,camera,battlefield,source)

func _placement_capture(viewport: SubViewport,world: Node3D,camera: Camera3D,battlefield: Node3D,source: Dictionary) -> void:
	var overlay: CanvasLayer = CanvasLayer.new()
	viewport.add_child(overlay)
	for route in source.get("paths",[]):
		var line: Line2D = Line2D.new()
		line.width = 2.0
		line.default_color = Color(.18,.92,.95,.85)
		for value in route.get("points",[]):
			line.add_point(camera.unproject_position(battlefield.world_point(Vector2(float(value.x),float(value.y)))))
		overlay.add_child(line)
	var actors: Array[Node3D] = []
	var positions: Array = []
	for index in range(source.get("buildZones",[]).size()):
		var zone: Dictionary = source.buildZones[index]
		var normalized: Vector2 = Vector2(float(zone.x),float(zone.y))
		var actor: Node3D = Actor.new()
		world.add_child(actor)
		actor.configure("archer",false,index+1)
		actor.set_process(false)
		actor.scale = Vector3.ONE*.70
		actor.position = battlefield.world_point(normalized)
		actors.append(actor)
		var pixel: Vector2 = camera.unproject_position(actor.position)
		_add_pin(overlay,pixel,str(index+1),Color("ffe676"))
		positions.append({"zoneId":str(zone.get("id","")),"normalized":normalized,"actualPixel":pixel,"worldHeight":actor.position.y})
	for objective in source.get("objectives",[]):
		var normalized: Vector2 = Vector2(float(objective.x),float(objective.y))
		_add_pin(overlay,camera.unproject_position(battlefield.world_point(normalized)),"BASE",Color("64dcff"))
	var image: Image = await _capture(viewport)
	image.save_png(ProjectSettings.globalize_path("user://stage-01-placement-centres.png"))
	report["placementCentres"] = positions
	if "--b1-pocket" in OS.get_cmdline_user_args():
		await _b1_pocket_capture(viewport,camera,battlefield,source,actors,overlay)
	for actor in actors:
		actor.free()
	overlay.free()

func _b1_pocket_capture(viewport: SubViewport,camera: Camera3D,battlefield: Node3D,source: Dictionary,actors: Array[Node3D],overlay: CanvasLayer) -> void:
	var game: Node2D = Game.new()
	game.three_d_enabled = true
	root.add_child(game)
	game.hide()
	game.set_process(false)
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	game.configure_roster(catalog,["archer"],{"archer":1})
	game.load_map(source)
	check(game.begin_placement("archer"),"B1 boundary captures use the actual Game archer placement flow")
	var zone: Dictionary = source.buildZones[0]
	var center: Vector2 = Vector2(float(zone.x),float(zone.y))
	var radius: float = float(zone.r)
	var samples: Array = []
	for index in [0,1,5,21,25,29]:
		var point: Vector2 = center
		if index>0: point += Vector2.from_angle(TAU*float(index-1)/32.0)*radius
		var preview: Dictionary = game.placement_preview(point)
		check(bool(preview.valid),"The photographed B1 center or perimeter point is genuinely placeable: "+str(index))
		if not bool(preview.valid): continue
		var actual: Vector2 = Vector2(float(preview.position.x),float(preview.position.y))
		actors[0].position = battlefield.world_point(actual)
		var pixel: Vector2 = camera.unproject_position(actors[0].position)
		check(pixel.distance_to(actual*Vector2(1280,720)) < .025,"A photographed B1 perimeter foot stays at the exact accepted artwork coordinate: "+str(index))
		var point_pin: ColorRect = ColorRect.new()
		point_pin.position = pixel-Vector2(3,3)
		point_pin.size = Vector2(6,6)
		point_pin.color = Color("68f3e7")
		overlay.add_child(point_pin)
		var path: String = "user://stage-01-b1-pocket-%02d.png" % index
		var capture: Image = await _capture(viewport)
		capture.save_png(ProjectSettings.globalize_path(path))
		samples.append({"sampleIndex":index,"position":preview.position,"pixel":pixel,"valid":true,"capture":ProjectSettings.globalize_path(path)})
		point_pin.free()
	report["b1PocketRenderedSamples"] = samples
	game.free()

func _add_pin(overlay: CanvasLayer,pixel: Vector2,value: String,colour: Color) -> void:
	var pin: ColorRect = ColorRect.new()
	pin.position = pixel-Vector2(3,3)
	pin.size = Vector2(6,6)
	pin.color = colour
	overlay.add_child(pin)
	var label: Label = Label.new()
	label.text = value
	label.position = pixel+Vector2(7,-14)
	label.add_theme_font_size_override("font_size",20)
	label.add_theme_color_override("font_color",colour)
	label.add_theme_color_override("font_outline_color",Color.BLACK)
	label.add_theme_constant_override("outline_size",5)
	overlay.add_child(label)

func _image_difference(a: Image,b: Image) -> float:
	var result: float = 0.0
	var count: int = 0
	for y in range(0,720,4):
		for x in range(0,1280,4):
			var left: Color = a.get_pixel(x,y)
			var right: Color = b.get_pixel(x,y)
			result += (absf(left.r-right.r)+absf(left.g-right.g)+absf(left.b-right.b))/3.0
			count += 1
	return result/maxi(count,1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
