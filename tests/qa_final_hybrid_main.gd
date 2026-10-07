extends SceneTree
## Actual Main integration for later approved hybrid battlefields. This fixture
## grants campaign reach in its own save, then buys the initial Lv1 roster at
## real stage prices. It does not inject soldier positions, HP, income or kills.
const Store = preload("res://native/progress.gd")
const Gate = preload("res://native/learning_gate.gd")
const Battlefield = preload("res://native/battlefield_3d.gd")
var PROFILE_PREFIX: String = qa_project_path("tests/profiles/final-hybrid-main/").to_lower()
var checks: int = 0
var failures: Array[String] = []
var app: Node
var observations: Array = []
var captures: Array[String] = []
var packed: bool = false
var cpu_only: bool = false
var main_pack: String = ""
var guard_metadata: Dictionary = {}

func _initialize() -> void:
	packed = "--packed" in OS.get_cmdline_user_args()
	cpu_only = "--cpu-only" in OS.get_cmdline_user_args()
	Engine.max_fps = 60
	call_deferred("run")

func check(value: bool,note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		push_error("FINAL_HYBRID_MAIN: "+note)

func normalized_path(path: String) -> String:
	return path.replace("\\","/").simplify_path().to_lower().trim_suffix("/")

func option(name: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(name+"="): return argument.trim_prefix(name+"=")
	return ""

func safe_environment() -> bool:
	var appdata: String = normalized_path(OS.get_environment("APPDATA"))
	var localdata: String = normalized_path(OS.get_environment("LOCALAPPDATA"))
	var actual: String = normalized_path(ProjectSettings.globalize_path("user://"))
	check(appdata.begins_with(PROFILE_PREFIX.to_lower()) and localdata == appdata,"Both Windows data roots use the same private workspace test profile")
	check(actual.begins_with(appdata+"/"),"Actual Godot user:// is contained by the private profile before scene creation")
	# Godot 4.7 consumes platform/pack startup switches. The invocation log
	# records --audio-driver Dummy/--main-pack; duplicate launcher declarations
	# and mounted resource hashes bind the QA to that concrete artifact.
	var declared_audio: String = OS.get_environment("QA_AUDIO_DRIVER")
	check(declared_audio == "Dummy" and option("--declared-audio-driver") == declared_audio,"Visual launcher explicitly records matching Dummy audio declarations")
	check((DisplayServer.get_name() == "headless") == cpu_only,"CPU and actual GPU modes are explicitly distinguished")
	var resource_hashes: Dictionary = {}
	if packed:
		main_pack = option("--pack-file")
		check(not main_pack.is_empty() and normalized_path(main_pack) == normalized_path(OS.get_environment("QA_MAIN_PACK")),"QA target and actual launcher main-pack declaration identify the same artifact")
		check(normalized_path(main_pack).begins_with(qa_project_path("tests/").to_lower()) and main_pack.get_extension().to_lower() == "exe","Main integration reads only an isolated newly extracted game executable")
		check(not main_pack.is_empty() and FileAccess.file_exists(main_pack),"Packed integration explicitly mounts the newly built artifact")
		var expected: String = option("--expected-pack-sha").to_lower()
		check(expected.length() == 64 and FileAccess.get_sha256(main_pack).to_lower() == expected,"Actual target executable bytes match the final build SHA256")
		var cwd: String = DirAccess.open(".").get_current_dir()
		check(normalized_path(cwd) == qa_project_path("tools/pack-learning-verifier-empty").to_lower() and normalized_path(OS.get_environment("QA_VERIFIER_CWD")) == normalized_path(cwd),"Actual pack-only working directory matches the launcher's empty verifier directory")
		check(not FileAccess.file_exists(cwd.path_join("project.godot")) and not DirAccess.dir_exists_absolute(cwd.path_join("native")),"Packed integration has no loose project or runtime in its working directory")
		check(not FileAccess.file_exists("res://tests/qa_final_hybrid_main.gd"),"External QA is not shipped as a production resource")
		for key in ["maps","plans","voice","art"]:
			var path: String = {"maps":"res://native/maps.json","plans":"res://native/learning_plans.json","voice":"res://assets/learning-voice/manifest.json","art":"res://assets/battlefields-rendered/manifest.json"}[key]
			var required_hash: String = option("--expected-"+key+"-sha").to_lower()
			var actual_hash: String = FileAccess.get_sha256(path).to_lower()
			check(required_hash.length() == 64 and actual_hash == required_hash,"Actual mounted "+key+" resource matches the final build fingerprint")
			resource_hashes[key] = {"path":path,"expected":required_hash,"actual":actual_hash}
	check(not FileAccess.file_exists("user://progress.json"),"Fresh integration profile contains no default player save")
	guard_metadata = {"appData":appdata,"localAppData":localdata,"actualUserDataDir":actual,"displayDriver":DisplayServer.get_name(),"declaredAudioDriver":declared_audio,"declaredMainPack":main_pack,"executableSha256":FileAccess.get_sha256(main_pack) if packed else "","mountedResourceHashes":resource_hashes,"emptyWorkingDirectoryRequired":packed}
	return failures.is_empty()

func settle(count: int = 6) -> void:
	for frame in range(count): await process_frame

func click(button: Button) -> void:
	check(button != null and button.is_visible_in_tree() and not button.disabled,"Actual requested button is visible and enabled")
	if button == null or not button.is_visible_in_tree() or button.disabled:
		return
	var point: Vector2 = button.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await settle(2)
	var hovered: Control = root.gui_get_hovered_control()
	check(hovered == button or (hovered != null and button.is_ancestor_of(hovered)),"Real pointer reaches the intended production button")
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	root.push_input(release)
	await settle(4)

func grant_campaign_reach() -> void:
	if not app.progress.data.learning.has("assessments"):
		app.progress.data.learning["assessments"] = {}
	for id in app.progress.stage_numbers:
		app.progress.data.maps[id] = {"wins":1}
		var lesson: Dictionary = app.progress.stage_lessons[id]
		var count: int = lesson.newWords.size()+lesson.get("grammarSteps",[]).size()
		app.progress.data.learning.assessments[id] = {"passed":true,"count":count,"correctCount":count,"scopeHash":Gate.scope_hash(lesson)}

func silence() -> void:
	app.japanese_voice = ""
	app._stop_narration()
	app.player.stop()
	app.player.stream = null
	app.battle_audio.set_enabled(false)
	app._apply_audio_settings()

func capture(label: String) -> void:
	if cpu_only or not "--capture" in OS.get_cmdline_user_args():
		return
	var pointer: InputEventMouseMotion = InputEventMouseMotion.new()
	pointer.position = Vector2(8,8)
	pointer.global_position = pointer.position
	root.push_input(pointer)
	await settle(8)
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	check(pixels != null and not pixels.is_empty() and pixels.get_size() == root.size,"Actual Main GPU capture has the requested viewport pixels")
	if pixels == null or pixels.is_empty(): return
	var path: String = "user://"+label+".png"
	check(pixels.save_png(path) == OK,"Actual Main GPU capture saves inside the private profile")
	captures.append(ProjectSettings.globalize_path(path))

func inspect_stage(index: int,minutes: int) -> void:
	var stage: Dictionary = app.maps[index]
	var note: String = "%02d %s: " % [index+1,str(stage.id)]
	app._choose_stage(index/10,index%10,false)
	await settle(6)
	check(str(app.current_map.id) == str(stage.id) and app.modal_context == "briefing",note+"actual Main selection reaches this stage's briefing")
	var basis: Label = app.modal_body.find_child("StoryMapBasis",true,false)
	var geography: Dictionary = app.front_end._geography(str(stage.id))
	check(basis != null and basis.text == "맵 제작 근거 · "+str(geography.get("renderingBasisKo","")),note+"actual briefing basis matches the selected stage")
	check(app.modal_body.find_child("BattleMinutes5",true,false) == null and app.battle_mode_buttons.size() == 2,note+"actual briefing offers only the existing ten and twenty minute modes")
	var mode: Button = app.modal_body.find_child("BattleMinutes%d" % minutes,true,false)
	app.modal_scroll.ensure_control_visible(mode)
	await settle(3)
	await click(mode)
	check(app.battle_minutes == minutes,note+"actual pointer click changes the production battle duration")
	var sortie: Button
	for child in app.modal_footer.get_children():
		if child is Button and child.text == "출진": sortie = child
	await click(sortie)
	silence()
	check(app.battle_started and app.modal == null and int(app.game.snapshot().battleMinutes) == minutes,note+"actual sortie button runs _begin_battle with the selected duration")
	check(app.game.render_projection_provider == app.troops_3d,note+"actual Main binds the shared elevated actor and HP provider")
	check(app.game.three_d_enabled and app.game.presentation_mirrored == app.troops_3d.presentation_mirrored and app.troops_3d.output.flip_h == app.game.presentation_mirrored,note+"actual Main displays the canonical terrain with the shared presentation orientation")
	var field: Node3D = app.troops_3d.battlefield
	var layer: Dictionary = field.render_layer_contract()
	check(str(layer.get("mode","")) == "rendered" and bool(layer.get("distributionReady",false)) and int(layer.get("coverage",0)) == 40,note+"actual Main selects complete approved hybrid art without fallback")
	check(bool(layer.get("sourceDataVerified",false)) and bool(layer.get("heightPreserved",false)) and not bool(layer.get("flatPhotoPlane",true)),note+"actual Main retains source-verified terrain relief")
	check(is_equal_approx(field.elevation,50.0) and is_equal_approx(field.width,18.5),note+"actual Main camera agrees with the generated artwork")
	var ground: ShaderMaterial = field.ground_mesh.material_override as ShaderMaterial
	check(ground != null and ground.get_shader_parameter("artwork") is Texture2D,note+"actual Main ground binds a loaded artwork texture")
	var projection_error: float = 0.0
	var display_projection_error: float = 0.0
	for path in app.game.paths:
		for point in path.points:
			var physical: Vector3 = field.world_point(point)
			check(physical.is_finite() and app.troops_3d.normalized_to_world(point).distance_to(physical) < .0001,note+"combat route uses the same actual physical height provider")
			projection_error = maxf(projection_error,app.troops_3d.camera.unproject_position(physical).distance_to(point*app.troops_3d.field_size))
			display_projection_error = maxf(display_projection_error,app.troops_3d.project_world_to_field(physical).distance_to(app.game.view_point(point)*app.troops_3d.field_size))
	check(projection_error < .5,note+"actual camera maps the relief route onto the gameplay anchors")
	check(display_projection_error < .5,note+"actual displayed route projection matches Game view coordinates without changing canonical paths")
	var initial_gold: int = app.game.gold
	var paid: Array = []
	for type_name in ["archer","archer","spear","spear"]:
		var before: int = app.game.recruitment_queue.size()
		var cost: int = app.game.recruit_cost(type_name)
		app._choose_unit(type_name)
		if type_name == "archer":
			var candidate: Vector2 = Vector2(-1,-1)
			for hint in app.game.placement_hints:
				if hint.x >= 0 and bool(app.game.placement_preview(hint).get("valid",false)):
					candidate = hint
					break
			check(candidate.x >= 0 and app.game.place_unit(candidate.x,candidate.y),note+"actual Lv1 archer order uses a legal authored emplacement")
		check(app.game.recruitment_queue.size() == before+1,note+"actual Main roster action creates exactly one paid parallel production order")
		paid.append({"type":type_name,"cost":cost})
	var total_cost: int = 0
	for order in paid: total_cost += int(order.cost)
	check(app.game.gold == initial_gold-total_cost,note+"actual initial supplies pay the original roster prices exactly once")
	for tick in range(600):
		if app.game.finished: break
		app.game.advance_simulation(1.0/60.0)
		app._process(1.0/60.0)
		app.combat_feedback._process(1.0/60.0)
		if tick%6 == 0:
			app.troops_3d._process(1.0/10.0)
			await process_frame
	app.troops_3d._process(0)
	await settle(6)
	check(not app.game.finished and app.game.units.size() > 0,note+"real production creates live soldiers on the selected rendered battlefield")
	var bars: Array = []
	for side in [{"friendly":true,"actors":app.game.units},{"friendly":false,"actors":app.game.enemies}]:
		for actor in side.actors:
			var layout: Dictionary = app.game.healthbar_layout(actor,bool(side.friendly))
			check(str(layout.get("text","missing")) == "" and bool(layout.get("projected",false)),note+"actual friendly/hostile HP bar has no digits and follows its 3D actor")
			check(layout.rect.has_area() and layout.anchor.is_finite() and float(layout.ratio) >= 0 and float(layout.ratio) <= 1,note+"actual HP bar preserves valid health geometry")
			var fill: Color = Color(str(layout.color))
			var background: Color = Color(str(layout.backgroundColor))
			check(is_equal_approx(layout.rect.size.y,2.0) and is_equal_approx(layout.fillRect.size.y,2.0) and fill.a==1.0 and background.a==1.0,note+"actual soldier bars are fully opaque two-pixel solid lines")
			check((fill.g>fill.r*1.5 and fill.g>fill.b*1.5) if side.friendly else (fill.r>fill.g*1.5 and fill.r>fill.b*1.5),note+"actual friendlies use green health and hostiles use red health")
			bars.append({"id":actor.id,"friendly":side.friendly,"type":actor.get("type",actor.get("kind","")),"hp":actor.hp,"text":layout.text,"rect":layout.rect,"projected":layout.projected})
	check(not bars.is_empty(),note+"real game soldiers provide observable health bars")
	var selected_fill: StyleBoxFlat = app.army_health.get_theme_stylebox("fill")
	var selected_background: StyleBoxFlat = app.army_health.get_theme_stylebox("background")
	check(app.army_health.size.y==2.0 and not app.army_health.show_percentage and selected_fill.bg_color.a==1.0 and selected_background.bg_color.a==1.0 and selected_fill.bg_color.g>selected_fill.bg_color.r*1.5,note+"actual selected-friendly health is a two-pixel opaque green line with no number")
	app.game._emit_state()
	await capture("main-casual-stage-%02d-%dmin" % [index+1,minutes])
	observations.append({"stageNumber":index+1,"stageId":stage.id,"minutes":minutes,"startingSupply":initial_gold,"paid":paid,"actualState":app.game.snapshot(),"layerContract":layer,"renderer":app.troops_3d.diagnostics(),"mirroredForDisplay":app.game.presentation_mirrored,"routeProjectionMaximumErrorPx":projection_error,"displayRouteProjectionMaximumErrorPx":display_projection_error,"actualHealthBars":bars})
	app._show_catalog()
	await settle(5)

func run() -> void:
	if not safe_environment(): quit(2);return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/battlefields-rendered/manifest.json"))
	check(manifest is Dictionary and bool(manifest.get("complete",false)) and manifest.get("stages",[]).size() == 40,"Final Main integration waits for the complete forty-map release manifest")
	if not failures.is_empty(): quit(2);return
	root.size = Vector2i(1440,900)
	root.content_scale_size = root.size
	var fixture: RefCounted = Store.new()
	fixture.save_path = "user://late-main-integration-%d.json" % Time.get_ticks_usec()
	for key in ["music","voice","effects"]: fixture.data.settings[key] = false
	check(fixture.write_save(),"Initial muted Lv1 fixture writes only inside the guarded profile")
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = fixture.save_path
	root.add_child(app)
	for node in [app,app.game,app.atmosphere,app.combat_feedback,app.troops_3d]: node.set_process(false)
	silence()
	await settle(8)
	check(app.progress.map_unlocked(str(app.maps[0].id)) and not app.progress.map_unlocked(str(app.maps[1].id)),"Fresh actual Main retains its first-map-only learning unlock rule")
	var original: String = str(app.current_map.id)
	app._choose_stage(3,9,false)
	check(str(app.current_map.id) == original,"Actual Main rejects final-map selection before its learning exam unlock")
	grant_campaign_reach()
	var indices: Array = [25,39]
	if "--include-first" in OS.get_cmdline_user_args(): indices.push_front(0)
	for index in indices:
		await inspect_stage(int(index),20 if int(index) == 39 else 10)
	check(not FileAccess.file_exists("user://progress.json"),"Actual Main writes stay in the fixture and never create a default player save")
	var actual_save: String = ProjectSettings.globalize_path(app.progress.save_path)
	silence()
	for service in [app.battle_audio,app.battle_narrator,app.battle_announcer,app.voice_director]:
		if service != null: service.shutdown()
	await create_timer(.5).timeout
	app.free()
	await settle(12)
	Battlefield.release_shared_resources()
	await settle(24)
	var cache: Dictionary = Battlefield.shared_cache_diagnostics()
	check(int(cache.materials.get("renderedArtTextureCount",-1)) == 0 and not bool(cache.materials.get("renderedShaderCached",true)) and int(cache.modelVariantGroups) == 0,"Actual Main worlds are freed before all shared terrain/art resources release")
	var result: Dictionary = {"checks":checks,"failures":failures,"pass":failures.is_empty(),"packed":packed,"mainPack":main_pack,"mainPackSha256":FileAccess.get_sha256(main_pack) if packed else "","launcherAndResourceGuards":guard_metadata,"gpu":RenderingServer.get_video_adapter_name() if not cpu_only else "not used","actualGpu":not cpu_only,"godot":Engine.get_version_info().string,"userPath":ProjectSettings.globalize_path("user://"),"fixtureSavePath":actual_save,"stages":observations,"captures":captures,"sharedCachesAfterShutdown":cache,"scope":"Actual Main stage1 (optional)/26/40 selection, real time-mode/sortie mouse clicks, complete approved hybrid art and shared relief/projection, real initial Lv1 paid archer/spear production and digit-free actor HP bars. Campaign reach is granted only in a private test save; actor positions/HP/supplies/kills are not injected. Ten seconds of deterministic simulation between real rendered frames observes integration; it is not battle completion, balance, audio playback or a full-game FPS benchmark. Source mode does not verify a packaged artifact."}
	var file: FileAccess = FileAccess.open("user://qa_final_hybrid_main.json",FileAccess.WRITE)
	check(file != null,"Main integration report writes inside the guarded private profile")
	result.checks = checks
	result.pass = failures.is_empty()
	if file != null: file.store_string(JSON.stringify(result,"  "));file.close()
	print("FINAL_HYBRID_MAIN ",JSON.stringify({"checks":checks,"failures":failures,"packed":packed,"actualGpu":not cpu_only,"stages":observations.size(),"captures":captures,"report":ProjectSettings.globalize_path("user://qa_final_hybrid_main.json")}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
