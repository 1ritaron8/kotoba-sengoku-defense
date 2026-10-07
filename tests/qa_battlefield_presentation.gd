extends SceneTree
## CPU presentation checks use original stages and never start combat or a save.
const Presentation = preload("res://native/battlefield_presentation.gd")
const Game = preload("res://native/game.gd")
const Troops = preload("res://native/troops_3d.gd")
const BattleCamera = preload("res://native/battle_camera.gd")
const Feedback = preload("res://native/combat_feedback.gd")
const BattleAudio = preload("res://native/battle_audio.gd")
const Battlefield = preload("res://native/battlefield_3d.gd")
const SCREEN_SIZES = [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]
const MODEL_SAMPLES = [Vector2.ZERO,Vector2.ONE,Vector2(.02,.03),Vector2(.98,.03),Vector2(.02,.97),Vector2(.98,.97),Vector2(.31,.42),Vector2(-.1,1.1)]
var checks: int = 0
var failures: Array[String] = []
var rows: Array = []
var exceptions: Dictionary = {"escortRoute":[],"marchBases":[]}
var source_hashes: Dictionary = {}
var clip: Control
var content: Control
var game: Node2D
var troops: Control
var camera: Node
var feedback: Node2D

func _initialize() -> void: call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)
		if failures.size()<=30: push_error("BATTLEFIELD_PRESENTATION "+note)

func same_point(actual: Vector2, expected: Vector2, note: String, tolerance: float = .001) -> void:
	check(actual.is_finite() and actual.distance_to(expected)<=tolerance,note)

func expected_view(point: Vector2, mirrored: bool) -> Vector2:
	return Vector2(1.0-point.x,point.y) if mirrored else point

func expected_pixel(point: Vector2, extent: Vector2, mirrored: bool) -> Vector2:
	return Vector2(extent.x-point.x,point.y) if mirrored else point

func allowed(point: Vector2) -> bool:
	return point.x<=.500001 or point.y>=.599999

func remember_source(path: String) -> void:
	if not source_hashes.has(path) and FileAccess.file_exists(path): source_hashes[path]=FileAccess.get_sha256(path)

func frozen_state() -> Dictionary:
	var health: Array = []
	for objective in game.objectives: health.append([int(objective.hp),int(objective.maxHp)])
	return {"gold":game.gold,"objectiveHealth":health,"wave":game.wave,"elapsed":game.elapsed,"waveTime":game.wave_time,"animationTime":game.animation_time,"escortDistance":game.escort_distance,"recruits":game.recruits,"kills":game.kills,"nextId":game.next_id,"running":game.running,"finished":game.finished,"rngState":game.rng.state,"recruitment":game.recruitment_queue.duplicate(true),"spawns":game.spawn_queue.duplicate(true),"enemies":game.enemies.duplicate(true)}

func navigation_state() -> Dictionary:
	return {"paths":game.paths.duplicate(true),"zones":game.zones.duplicate(true),"lengths":game.ground_combat.cumulative.duplicate(true),"bases":game.ground_combat.march_bases.duplicate(true),"ambushSites":game.ground_combat.ambush_sites.duplicate(true),"objectives":game.objectives.duplicate(true)}

func helper_checks() -> void:
	for mirrored in [false,true]:
		for point in MODEL_SAMPLES:
			var view: Vector2 = Presentation.to_view(point,mirrored)
			same_point(view,expected_view(point,mirrored),"Normalized display mapping has the requested horizontal orientation")
			same_point(Presentation.to_model(view,mirrored),point,"Normalized mapping returns canonical coordinates including boundary/outside points")
			var extent: Vector2 = Vector2(1248,620)
			var pixels: Vector2 = point*extent
			same_point(Presentation.pixel_to_view(pixels,extent,mirrored),expected_pixel(pixels,extent,mirrored),"Pixel mapping reflects against the actual field width")
		var original: Rect2 = Rect2(.13,.27,.21,.18)
		var rect: Rect2 = Presentation.rect_to_view(original,mirrored)
		var expected: Rect2 = Rect2(1.0-original.end.x,original.position.y,original.size.x,original.size.y) if mirrored else original
		check(rect.is_equal_approx(expected) and rect.size.is_equal_approx(original.size),"Normalized rectangle reflection preserves its positive extent")
		check(Presentation.rect_to_view(rect,mirrored).is_equal_approx(original),"Normalized rectangle reflection round-trips")
	for fixture in [{"objectives":[]},{"objectives":[{"x":.8,"y":.25}]},{"objectives":[{"x":.8,"y":.75}]},{"objectives":[{"x":.2,"y":.25},{"x":.8,"y":.25}]}]:
		var before: Dictionary = fixture.duplicate(true)
		var decision: Dictionary = Presentation.decision(fixture)
		check(fixture==before,"Policy inspection never edits a caller's stage")
		if fixture.objectives.size()==2: check(not bool(decision.satisfiable),"Opposing upper objectives explicitly report an unsatisfiable single horizontal reflection")
		elif fixture.objectives.is_empty(): check(not bool(decision.mirrored),"An empty objective list retains its original orientation")
		else: check(bool(decision.mirrored)==not allowed(Presentation.point(fixture.objectives[0])),"A left/lower objective keeps its orientation and a right/upper objective reflects")

func audio_checks() -> void:
	var audio: Node = BattleAudio.new()
	root.add_child(audio)
	var field: Rect2 = Rect2(16,64,1248,620)
	audio.set_field_rect(field)
	for mirrored in [false,true]:
		audio.set_presentation_mirrored(mirrored)
		for point in [Vector2(.12,.35),Vector2(.5,.5),Vector2(.86,.73),Vector2(-.1,1.1)]:
			var event: Dictionary = {"position":{"x":point.x,"y":point.y}}
			var original: Dictionary = event.duplicate(true)
			var expected: Vector2 = field.position+expected_view(point.clamp(Vector2.ZERO,Vector2.ONE),mirrored)*field.size
			same_point(audio._event_position(event,false),expected,"Audio event position matches the displayed left/right field after clamping")
			same_point(audio._event_position({"victimPosition":point},false),expected,"Audio victim coordinates use the same canonical display boundary")
			same_point(audio._event_position(event,true),root.get_visible_rect().size*.5,"Centered UI sounds remain at the viewport center under either orientation")
			check(event==original,"Audio mapping retains the canonical event payload")
	check(audio.players.is_empty() and audio.streams.is_empty() and not bool(audio.is_ready) and int(audio.played)==0,"Audio coordinate inspection creates no players, sample loading or playback")
	audio.free()

func original_stage_checks(stage: Dictionary) -> Dictionary:
	var id: String = str(stage.id)
	var original_fits: bool = true
	var reflected_fits: bool = true
	var objective_rows: Array = []
	for index in range(game.objectives.size()):
		var authored: Dictionary = stage.objectives[index]
		var model: Vector2 = Presentation.point(authored)
		if bool(authored.get("mobile",false)) and not stage.get("escortRoute",[]).is_empty(): model=Presentation.point(stage.escortRoute[0])
		same_point(game.objectives[index].position,model,"Loaded objective remains canonical: "+id)
		original_fits=original_fits and allowed(model)
		reflected_fits=reflected_fits and allowed(expected_view(model,true))
		var displayed: Vector2 = game.view_point(game.objectives[index].position)
		check(allowed(displayed),"Every actual initial friendly objective is displayed left or lower: "+id+" "+str(authored.id))
		objective_rows.append({"id":str(authored.id),"model":{"x":model.x,"y":model.y},"view":{"x":displayed.x,"y":displayed.y},"mobile":bool(authored.get("mobile",false))})
	check(bool(game.presentation_mirrored)==(not original_fits and reflected_fits),"Actual stage orientation matches all original objectives: "+id)
	check(game.config==stage,"Loading presentation never changes the original stage dictionary: "+id)
	for path_index in range(game.paths.size()):
		var cumulative: float = 0.0
		for point_index in range(game.paths[path_index].points.size()):
			var point: Vector2 = Presentation.point(stage.paths[path_index].points[point_index])
			same_point(game.paths[path_index].points[point_index],point,"Authored navigation point remains canonical: "+id)
			if point_index>0: cumulative+=point.distance_to(Presentation.point(stage.paths[path_index].points[point_index-1]))
			check(absf(float(game.ground_combat.cumulative[path_index][point_index])-cumulative)<.00001,"Navigation distance comes from original coordinates: "+id)
	for base in game.ground_combat.march_bases:
		var view: Vector2 = game.view_point(base.position)
		if not allowed(view): exceptions.marchBases.append({"stageId":id,"baseId":str(base.baseId),"pathIndex":int(base.pathIndex),"model":{"x":base.position.x,"y":base.position.y},"view":{"x":view.x,"y":view.y}})
	var escort: Array = stage.get("escortRoute",[])
	for segment in range(maxi(0,escort.size()-1)):
		for sample in range(17):
			var model: Vector2 = Presentation.point(escort[segment]).lerp(Presentation.point(escort[segment+1]),float(sample)/16.0)
			var view: Vector2 = game.view_point(model)
			if not allowed(view):
				exceptions.escortRoute.append({"stageId":id,"segment":segment,"fraction":float(sample)/16.0,"model":{"x":model.x,"y":model.y},"view":{"x":view.x,"y":view.y}})
				break
	return {"stageId":id,"mirrored":bool(game.presentation_mirrored),"objectives":objective_rows,"sizes":[]}

func layout(dimensions: Vector2i, stage: Dictionary) -> void:
	root.size=dimensions
	var field: Rect2 = Rect2(16,64,dimensions.x-32,dimensions.y-180)
	clip.position=field.position
	clip.size=field.size
	game.position=-field.position
	game.set_field_rect(field)
	troops.set_field_size(field.size)
	var camera_stage: Dictionary = stage.duplicate(true)
	camera_stage["camera"]={"allowZoom":true}
	camera.configure(clip,content,camera_stage)
	camera.reset()
	troops.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED

func pointer_checks(stage_id: String, dimensions: Vector2i) -> void:
	var tag: String = stage_id+" "+str(dimensions)
	check(game.begin_placement("archer"),"A real uncommitted archer preview opens: "+tag)
	for zoom in [1.0,1.6]:
		camera.reset()
		if zoom>1.0:
			check(camera.set_zoom(zoom),"The actual shared camera accepts max zoom: "+tag)
			camera.pan_by_clip_delta(Vector2(-clip.size.x*.13,clip.size.y*.09))
		for point in MODEL_SAMPLES:
			var global: Vector2 = game.field_point_to_screen(point)
			same_point(game.screen_to_field_point(global),point,"Global/canonical input round-trip includes mirror, resize, zoom and pan: "+tag,.00001)
			same_point(game._screen(point),game.field_rect.position+expected_view(point,bool(game.presentation_mirrored))*game.field_rect.size,"Local overlay coordinates agree with the displayed map: "+tag)
		for fraction in [Vector2(.01,.01),Vector2(.99,.01),Vector2(.01,.99),Vector2(.99,.99),Vector2(.5,.5)]:
			var clip_point: Vector2 = fraction*clip.size
			var global: Vector2 = camera.clip_to_screen(clip_point)
			var view: Vector2 = ((clip_point-camera.pan)/float(camera.zoom))/clip.size
			var expected: Vector2 = expected_view(view,bool(game.presentation_mirrored))
			var motion: InputEventMouseMotion = InputEventMouseMotion.new()
			motion.position=global
			game._input(motion)
			check(bool(game.placement_cursor_visible),"Actual pointer motion remains inside the visible clipped field: "+tag)
			same_point(game.placement_cursor,expected,"Actual pointer event stores canonical placement coordinates: "+tag,.00001)
		var outside: Vector2 = camera.clip_to_screen(Vector2(clip.size.x*.5,clip.size.y+10))
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position=outside
		game._input(motion)
		check(not bool(game.placement_cursor_visible) and not game.screen_point_in_field(outside),"Pointer outside the fixed clip hides the placement ghost after zoom: "+tag)
		# Click selection runs through the real InputEvent event-position path.
		game.pending.clear()
		var unit: Dictionary = game.units[0]
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT
		click.pressed=true
		click.position=game.field_point_to_screen(unit.position)
		check(game.screen_point_in_field(click.position),"Selection fixture remains visible under the actual camera: "+tag)
		game.selected_id=-1
		game._unhandled_input(click)
		check(int(game.selected_id)==int(unit.id),"Actual click selects the canonical unit beneath its mirrored view: "+tag)
		check(game.begin_placement("archer"),"Selection can return to a pending preview without spending: "+tag)
	camera.reset()
	for point in [Vector2(.005,.005),Vector2(.995,.005),Vector2(.005,.995),Vector2(.995,.995)]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT
		click.pressed=true
		click.position=game.field_point_to_screen(point)
		game._unhandled_input(click)
		same_point(game.placement_cursor,point,"Real corner click reaches canonical placement validation: "+tag,.00001)
		check(game.recruitment_queue.is_empty() and not game.pending.is_empty(),"Rejected corner placement never reserves production or removes the preview: "+tag)

func renderer_checks(stage: Dictionary, dimensions: Vector2i) -> Dictionary:
	var tag: String = str(stage.id)+" "+str(dimensions)
	check(bool(troops.presentation_mirrored)==bool(game.presentation_mirrored) and bool(troops.output.flip_h)==bool(game.presentation_mirrored),"Actual 3D output and game agree on orientation: "+tag)
	check(troops.stage==stage and troops.battlefield.stage==stage,"3D renderer retains the original stage geometry and art coordinates: "+tag)
	var baseline_heights: PackedFloat32Array = troops.battlefield.heights.duplicate()
	var baseline_geometry: String = str(troops.battlefield.geometry_fingerprint)
	var baseline_rebuilds: int = int(troops.battlefield.rebuild_count)
	var original_physical: String = JSON.stringify(troops.battlefield._physical_contract(stage)).sha256_text()
	check(original_physical==str(troops.battlefield.diagnostics().physicalGeometryFingerprint),"Actual terrain fingerprint matches the original physical map: "+tag)
	var layer: Dictionary = troops.battlefield.render_layer_contract()
	if not str(layer.get("artPath","")).is_empty(): remember_source(str(layer.artPath))
	for point in [Vector2(.15,.25),Vector2(.53,.42),Vector2(.82,.73)]:
		var world: Vector3 = troops.normalized_to_world(point)
		var raw: Vector2 = troops.camera.unproject_position(world)*troops.field_size/Vector2(troops.viewport.size)
		var expected: Vector2 = expected_pixel(raw,troops.field_size,bool(game.presentation_mirrored))
		same_point(troops.project_world_to_field(world),expected,"Real terrain projection reflects once at the display boundary: "+tag)
		same_point(expected,game.view_point(point)*game.field_rect.size,"Actual raised terrain and 2D logical view share a ground anchor: "+tag,.1)
		same_point(feedback._ground(point),expected_view(point,bool(game.presentation_mirrored))*game.field_rect.size,"Combat feedback ground anchor follows the view hook: "+tag)
		for source in [true,false]:
			var meta: Dictionary = {"unitType":"spear","side":"friendly"} if source else {"victimType":"enemy_cavalry","victimSide":"enemy"}
			var data: Dictionary = {"type":"spear","friendly":true,"kind":""} if source else {"type":"enemy_cavalry","friendly":false,"kind":"enemy_cavalry"}
			var height: float = .98 if source else 1.48
			var body: Vector3 = world+Vector3.UP*height*float(troops.render_scale_for(point,data))
			same_point(feedback._body(point,meta,source),troops.project_world_to_field(body),"Combat feedback source/victim body uses the actual mirrored 3D projection: "+tag)
	var states: Array = game.actor_states()
	states.append({"id":701,"type":"spear","friendly":true,"dead":false,"x":.36,"y":.62,"aimX":1.0,"aimY":0.0,"animation":"idle","animationClock":0.0,"motionTime":0.0,"campaignLevel":8,"evolution":0,"hp":120.0,"maxHp":120.0,"skillIds":["spear_poison"],"flags":{"poisonTip":true,"poisoned":true,"formation":true}})
	troops.sync_actor_states(states)
	check(troops.side_markers.size()==2,"Actual actor fixtures each supply a separate side marker: "+tag)
	for marker in troops.side_markers:
		var actor: Node3D = troops.actors[str(marker.id)+":"+str(marker.member)]
		same_point(marker.position,troops.project_world_to_field(actor.position),"Actual foot marker follows the reflected rendered actor: "+tag)
		var head_world: Vector3 = actor.bones.head.global_position+Vector3.UP*.26*actor.scale.y
		same_point(marker.healthAnchor,troops.project_world_to_field(head_world),"Actual HP marker follows the projected 3D head: "+tag)
		var anchor: Dictionary = troops.health_anchor_for(int(marker.id))
		same_point(anchor.headPosition,marker.healthAnchor,"Public HP anchor agrees with the actual side marker: "+tag)
		if int(marker.id)==701:
			check(marker.has("statusPoint") and marker.has("poisonTipPoint"),"Actual spear fixture generates independent status and weapon markers: "+tag)
			if marker.has("statusPoint"): same_point(marker.statusPoint,troops.project_world_to_field(actor.position+Vector3.UP*1.25*actor.scale.y),"Status marker reflects with its actor: "+tag)
			if marker.has("poisonTipPoint"): same_point(marker.poisonTipPoint,troops.project_world_to_field(actor.bones.weapon.global_transform*Vector3(0,1.22+actor.evolution_stage*.025,0)),"Articulated poison tip reflects with its actual weapon: "+tag)
	for zoom in [1.0,1.6]:
		camera.reset()
		if zoom>1.0:
			camera.set_zoom(zoom)
			camera.pan_by_clip_delta(Vector2(-clip.size.x*.08,-clip.size.y*.06))
		var health: Dictionary = game.healthbar_layout(game.units[0],true)
		var unit_anchor: Dictionary = troops.health_anchor_for(int(game.units[0].id))
		var local_head: Vector2 = game.get_global_transform_with_canvas().affine_inverse()*(troops.get_global_transform_with_canvas()*unit_anchor.headPosition)
		check(bool(health.projected),"Game HP layout consumes the actual 3D projection provider: "+tag)
		same_point(health.anchor,local_head,"Game HP layout remains aligned through the shared camera transform: "+tag)
	camera.reset()
	var snap: Vector2 = Vector2(-1,-1)
	for hint in game.placement_hints:
		if hint.x>=0 and bool(game.placement_preview(hint).valid): snap=hint;break
	check(snap.x>=0,"Original role validation supplies a legal preview point: "+tag)
	if snap.x>=0:
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position=game.field_point_to_screen(snap)
		game._input(motion)
		var preview: Dictionary = game.placement_preview(game.placement_cursor)
		troops.sync_placement_preview(preview,0.0)
		check(bool(preview.valid) and troops.placement_actor.visible,"Actual uncommitted placement produces the original 3D ghost: "+tag)
		var position: Vector2 = Presentation.point(preview.position)
		check(troops.placement_actor.position.distance_to(troops.normalized_to_world(position))<.00001,"Ghost stays at the canonical legal snap rather than reflecting model coordinates: "+tag)
		same_point(troops.project_world_to_field(troops.placement_actor.position),game.view_point(position)*game.field_rect.size,"Ghost contact point shares the final displayed snap: "+tag,.1)
	# Display state can change without touching terrain, navigation, or art.
	var mirrored: bool = bool(troops.presentation_mirrored)
	troops.presentation_mirrored=not mirrored
	var probe: Vector3 = troops.normalized_to_world(Vector2(.23,.38))
	var raw: Vector2 = troops.camera.unproject_position(probe)*troops.field_size/Vector2(troops.viewport.size)
	same_point(troops.project_world_to_field(probe),expected_pixel(raw,troops.field_size,not mirrored),"Display state alters only the projected x coordinate: "+tag)
	troops.set_stage(stage)
	check(troops.battlefield.heights==baseline_heights and str(troops.battlefield.geometry_fingerprint)==baseline_geometry and int(troops.battlefield.rebuild_count)==baseline_rebuilds,"Presentation reset preserves every terrain height and skips physical reconstruction: "+tag)
	check(troops.battlefield._physical_contract(stage)==troops.battlefield._physical_contract(),"Presentation never rewrites the terrain's physical source contract: "+tag)
	troops.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	return {"width":dimensions.x,"height":dimensions.y,"physicalFingerprint":original_physical,"terrainFingerprint":baseline_geometry,"heightSamples":baseline_heights.size(),"artPath":str(layer.get("artPath","")),"artSha256":str(layer.get("artSha256",""))}

func run() -> void:
	var profile: String = OS.get_environment("APPDATA").replace("\\","/").to_lower()
	var user_path: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/battlefield-presentation/") or not user_path.begins_with("c:/jp_df/tests/profiles/battlefield-presentation/") or DisplayServer.get_name()!="headless":
		push_error("An isolated battlefield-presentation APPDATA profile and headless CPU mode are required")
		quit(2);return
	var started: int = Time.get_ticks_msec()
	remember_source("res://native/maps.json")
	remember_source("res://native/units.json")
	remember_source("res://assets/battlefields-rendered/manifest.json")
	var raw_maps: String = FileAccess.get_file_as_string("res://native/maps.json")
	var maps: Array = JSON.parse_string(raw_maps)
	check(maps.size()==40,"All forty original authored stages are tested")
	helper_checks()
	audio_checks()
	clip=Control.new()
	clip.mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip.clip_contents=true
	root.add_child(clip)
	content=Control.new()
	content.mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip.add_child(content)
	game=Game.new()
	game.three_d_enabled=true
	game.external_placement_ghost=true
	content.add_child(game)
	game.set_process(false)
	game.set_input_clip(clip)
	troops=Troops.new()
	content.add_child(troops)
	troops.set_process(false)
	troops.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	troops.bind_battle(game)
	feedback=Feedback.new()
	feedback.battle=game
	feedback.troop_renderer=troops
	content.add_child(feedback)
	feedback.set_process(false)
	camera=BattleCamera.new()
	root.add_child(camera)
	for stage in maps:
		game.set_seed(20261007)
		game.load_map(stage)
		troops.set_stage(stage)
		troops.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		var frozen: Dictionary = frozen_state()
		var navigation: Dictionary = navigation_state()
		var row: Dictionary = original_stage_checks(stage)
		# A preview-derived fixture supplies a selectable actor without spawning,
		# paying, consuming an id, advancing production or entering combat.
		check(game.begin_placement("archer"),"An original archer definition supplies the frozen selection fixture")
		var unit: Dictionary = game.pending.duplicate(true)
		unit.merge({"id":700,"position":Vector2(.51,.54),"homePosition":Vector2(.51,.54),"aim":Vector2.RIGHT,"hp":120.0,"maxHp":120.0,"animation":"idle","animationClock":0.0,"animationPhase":0.0,"combatState":"guard","preview":false,"elevation":0},true)
		game.units.append(unit)
		for dimensions in SCREEN_SIZES:
			layout(dimensions,stage)
			pointer_checks(str(stage.id),dimensions)
			row.sizes.append(renderer_checks(stage,dimensions))
		check(navigation_state()==navigation,"All view/input/renderer operations preserve canonical navigation and objective state: "+str(stage.id))
		check(frozen_state()==frozen,"Frozen inspection never advances battle, production, economy, ids or randomness: "+str(stage.id))
		check(game.config==stage and troops.stage==stage,"Original stage dictionaries survive all resizes and mouse events: "+str(stage.id))
		rows.append(row)
		game.units.clear()
		game.pending.clear()
		troops.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		await process_frame
	check(FileAccess.get_file_as_string("res://native/maps.json")==raw_maps,"The original campaign map file is unchanged")
	for path in source_hashes: check(FileAccess.get_sha256(path)==str(source_hashes[path]),"Canonical source/art bytes remain unchanged: "+str(path))
	var report: Dictionary = {"checks":checks,"failures":failures,"stages":rows,"constraintExceptions":exceptions,"sourceSHA256":source_hashes,"cpuOnly":true,"milliseconds":Time.get_ticks_msec()-started,"scope":"Forty original stages; three actual viewport sizes; original objectives and navigation; real shared pan/zoom and canonical InputEvent positions; rejected placement corners and selection; actual 3D terrain/actor/head/skill/ghost projections plus feedback source/victim anchors. No main/progress store, save, combat start, simulation advance, GPU or visual-quality claim. Escort-path crossings and march-base layout constraints are recorded separately from initial objective requirements."}
	var file: FileAccess = FileAccess.open("user://qa_battlefield_presentation.json",FileAccess.WRITE)
	check(file!=null,"The isolated CPU report opens")
	if file!=null:
		report.checks=checks
		report.failures=failures
		file.store_string(JSON.stringify(report,"  "));file.close()
	print("BATTLEFIELD_PRESENTATION ",JSON.stringify({"checks":checks,"failures":failures,"stages":rows.size(),"sizesPerStage":SCREEN_SIZES.size(),"escortConstraints":exceptions.escortRoute.size(),"marchBaseConstraints":exceptions.marchBases.size(),"milliseconds":Time.get_ticks_msec()-started,"cpuOnly":true}))
	clip.free()
	camera.free()
	Battlefield.release_shared_resources()
	quit(0 if failures.is_empty() else 1)
