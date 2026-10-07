extends SceneTree
## Actual Main / native UI input. Combat mode timing matrices are covered by backend QA.
const Store = preload("res://native/progress.gd")
var app: Node
var checks: int = 0
var failures: Array = []
var snapshots: Array = []
var images: Array = []
var capture_enabled: bool = false
var context: String = ""

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(context+" · "+note)
		if failures.size()<=30: push_error("BATTLE_MODE_UI "+context+" · "+note)

func settle() -> void:
	for frame in range(4): await process_frame

func named(parent: Node, id: String) -> Control:
	for control in parent.find_children(id,"Control",true,false):
		if control.is_visible_in_tree() and not control.is_queued_for_deletion(): return control
	return null

func find_button(parent: Node, prefix: String) -> Button:
	for control in parent.find_children("*","Button",true,false):
		if control.is_visible_in_tree() and not control.is_queued_for_deletion() and control.text.begins_with(prefix): return control
	return null

func press(button: Button) -> void:
	check(button!=null and not button.disabled,"Actual UI action is available")
	if button==null or button.disabled: return
	var ancestor: Node = button.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
			await settle()
		ancestor = ancestor.get_parent()
	var point: Vector2 = button.get_global_rect().get_center()
	check(root.get_visible_rect().encloses(button.get_global_rect()),"Native click target fits inside the window")
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
	await settle()

func record(note: String) -> void:
	snapshots.append({"case":context,"note":note,"setting":app.progress.data.settings.get("battleMinutes"),"nextMinutes":app.battle_minutes,"activeMinutes":app.active_battle_minutes,"hud":app.hud_clock.text,"hudRect":app.hud_clock.get_global_rect(),"state":app.game.snapshot(),"modal":app.modal_context,"learningPhase":app.learning_transition.phase,"map":str(app.current_map.id)})

func capture(name: String) -> void:
	if not capture_enabled: return
	app.troops_3d._process(0)
	await create_timer(.6,true,false,true).timeout
	await RenderingServer.frame_post_draw
	var path: String = "user://battle-mode-%s-%dx%d.png" % [name,root.content_scale_size.x,root.content_scale_size.y]
	check(root.get_texture().get_image().save_png(path)==OK,"GPU mode capture saves")
	images.append(ProjectSettings.globalize_path(path))

func clock_geometry() -> void:
	var rect: Rect2 = app.hud_clock.get_global_rect()
	check(app.hud_bar.get_global_rect().encloses(rect) and not rect.intersects(app.map_title.get_global_rect()),"Time label fits within the existing HUD beside the map title")
	check(not rect.intersects(app.hud_wave.get_global_rect()) and not rect.intersects(app.hud_health.get_global_rect()) and not rect.intersects(app.hud_gold.get_global_rect()),"Mode/time display does not overlap the original counters")
	var font: Font = app.hud_clock.get_theme_font("font")
	var size: int = app.hud_clock.get_theme_font_size("font_size")
	check(size>=20 and font.get_string_size(app.hud_clock.text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x<=rect.size.x+1,"Mode and time stay readable without shrinking or horizontal clipping")
	check(app.army_toolbar.get_global_rect()==Rect2(16,root.content_scale_size.y-92,root.content_scale_size.x-32,80) and app.army_grid.get_child_count()==8,"Time selection preserves all eight classes and the existing bottom row")

func selection_checks() -> void:
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		for minutes in [5,10,20]:
			context = "catalog "+str(dimensions)+" / "+str(minutes)
			app._show_catalog()
			await settle()
			var option: Button = named(app.front_end,"BattleMinutes%d" % minutes)
			check(option!=null and option.get_theme_font_size("font_size")>=20,"Catalog offers the requested mode at the approved font size")
			if option!=null:
				var legend: Control = named(app.front_end,"DeploymentRoleLegend")
				check(not option.get_global_rect().intersects(legend.get_global_rect()),"Time choices do not cover deployment-role instructions")
			await press(option)
			check(app.battle_minutes==minutes and app.front_end.battle_minutes==minutes and int(app.progress.data.settings.battleMinutes)==minutes,"Native catalog choice synchronizes the one global mode setting")
			var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(app.progress.save_path))
			check(int(saved.settings.battleMinutes)==minutes,"Native mode choice persists in the isolated save")
			await press(named(app.front_end,"CatalogSortie"))
			check(app.modal_context=="briefing" and app.battle_minutes==minutes,"Catalog sortie carries the choice into the actual briefing")
			var selector: Control = named(app.modal_body,"BattleModeSelector")
			check(selector!=null and app.modal_footer.get_global_rect().end.y<=app.modal_card.get_global_rect().end.y,"Briefing offers the same modes and retains its fixed sortie footer")
			clock_geometry()
			for option_minutes in [5,10,20]:
				check(named(app.modal_body,"BattleMinutes%d" % option_minutes)!=null,"Briefing includes "+str(option_minutes)+" minutes")
			await capture("briefing-%d" % minutes)
			record("briefing-choice")
	# Choice from the briefing itself uses native input, not the selection callback directly.
	await press(named(app.modal_body,"BattleMinutes10"))
	check(app.battle_minutes==10 and int(app.progress.data.settings.battleMinutes)==10,"Native briefing choice updates and persists the mode")
	await press(app.modal_footer.get_child(0))
	app.game.set_process(false)
	check(app.active_battle_minutes==10 and int(app.game.snapshot().get("battleMinutes",0))==10,"Sortie applies the selected mode to the common production battle")

func time_and_learning_checks() -> void:
	context = "battle clock / pause / learning"
	app.game.set_speed(1)
	app.game._process(.2)
	app._on_state(app.game.snapshot())
	check(app.hud_clock.text.begins_with("10분") and app.hud_clock.text.ends_with("10:00"),"Battle HUD shows the active target and progress")
	clock_geometry()
	var before: float = app.game.elapsed
	await press(app.pause_button)
	app.game._process(.2)
	app._on_state(app.game.snapshot())
	check(app.game.elapsed==before and bool(app.state.paused),"Native pause excludes waiting time from the displayed battle clock")
	await press(app.pause_button)
	app._show_catalog()
	await settle()
	var locked: Button = named(app.front_end,"BattleMinutes20")
	check(locked.disabled,"Ongoing sortie locks mode choices during navigation")
	app._choose_battle_minutes(20)
	check(app.battle_minutes==10 and app.active_battle_minutes==10,"Guarded mode callback cannot change an active sortie")
	app._resume_from_navigation()
	await settle()
	app.game.set_process(false)
	app.game.between_waves = true
	app.game._emit_state()
	before = app.game.elapsed
	app._show_quiz()
	var deadline: int = Time.get_ticks_msec()+2500
	while app.learning_transition.is_busy() and Time.get_ticks_msec()<deadline:
		app.game._process(.05)
		await process_frame
	check(app.learning_transition.phase=="choice" and app.game.elapsed==before and not app.hud_clock.visible,"Learning entry and choice exclude time and deliberately hide the clock with the HUD")
	await press(app.learning_field.continue_button)
	deadline = Time.get_ticks_msec()+2500
	while app.learning_transition.is_busy() and Time.get_ticks_msec()<deadline:
		app.game._process(.05)
		await process_frame
	check(app.learning_transition.phase=="idle" and app.hud_clock.visible and app.game.elapsed==before,"Learning skip and animated return preserve the clock before simulation resumes")
	app.game.set_process(false)
	for battle_speed in [1,2,3]:
		app.game.set_speed(battle_speed)
		before = app.game.elapsed
		app.game._process(.1)
		app._on_state(app.game.snapshot())
		check(absf(app.game.elapsed-before-.1*battle_speed)<.000001,"HUD uses the common battle clock at "+str(battle_speed)+"x without a separate real-time timer")
	app.game.elapsed = 123.5
	app._on_state(app.game.snapshot())
	check(app.hud_clock.text=="10분 · 02:03 / 10:00","HUD formats elapsed and target as minutes/seconds")
	clock_geometry()
	record("elapsed-and-freezes")
	await capture("battle-10")

func retry_and_reload_checks() -> void:
	context = "result / retry / next / reload"
	var map_id: String = str(app.current_map.id)
	app.game._finish(false)
	await settle()
	var result: Label = named(app.modal_body,"BattleModeResult")
	check(result!=null and result.text=="10분 모드 · 전투 시간 02:03 / 10:00","Actual result shows the same active mode and elapsed battle clock")
	await capture("result-10")
	await press(find_button(app.modal_body,"같은 지도 다시 출진"))
	check(app.modal_context=="briefing" and str(app.current_map.id)==map_id and app.battle_minutes==10,"Native retry preserves the map and selected mode")
	await press(app.modal_footer.get_child(0))
	app.game.set_process(false)
	check(app.active_battle_minutes==10 and int(app.game.snapshot().get("battleMinutes",0))==10 and app.game.elapsed==0,"Retried sortie restarts the same mode with a fresh battle clock")
	app.game._finish(false)
	await settle()
	await press(find_button(app.modal_body,"다음 지도"))
	check(app.current_index==1 and app.battle_minutes==10,"Next map inherits the saved runtime mode without modifying map data")
	await press(named(app.modal_body,"BattleMinutes20"))
	await press(app.modal_footer.get_child(0))
	app.game.set_process(false)
	check(app.active_battle_minutes==20 and int(app.game.snapshot().get("battleMinutes",0))==20,"A later sortie applies its newly selected mode")
	var reloaded = Store.new()
	reloaded.save_path = app.progress.save_path
	reloaded.read_save()
	check(int(reloaded.data.settings.battleMinutes)==20,"Mode survives an actual progress-store reload")
	record("retry-next-reload")

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/battle-mode-ui/").to_lower()):
		push_error("Battle-mode UI QA refuses the player's profile")
		quit(2)
		return
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if capture_enabled and DisplayServer.get_name()=="headless": quit(2);return
	var fixture = Store.new()
	fixture.save_path = "user://battle-mode-ui-%d.json" % Time.get_ticks_usec()
	fixture.data.settings = {"music":false,"voice":false,"effects":false}
	check(fixture.write_save(),"Isolated old-format settings fixture saves")
	root.size = Vector2i(1280,800)
	root.content_scale_size = Vector2i(1280,800)
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = fixture.save_path
	root.add_child(app)
	await settle()
	app.set_process(false)
	app.game.set_process(false)
	if not capture_enabled:
		app.troops_3d.hide()
		app.troops_3d._process(0)
	app.troops_3d.set_process(false)
	check(app.battle_minutes==5 and int(app.progress.data.settings.battleMinutes)==5,"An existing save without a mode defaults to a five-minute sortie")
	var wallet: int = int(app.progress.data.army.currency)
	await selection_checks()
	await time_and_learning_checks()
	await retry_and_reload_checks()
	check(int(app.progress.data.army.currency)==wallet,"Selection/pause/skip/retry does not change permanent funding")
	app._quit_game()
	var report: Dictionary = {"checks":checks,"failures":failures,"productionSnapshots":snapshots,"images":images,"profile":profile,"driver":DisplayServer.get_name(),"scope":"Actual Main/native UI mode selection and persistence in catalog/briefing, production mode dispatch, HUD target/elapsed geometry, frozen pause/navigation/learning entry/skip/exit, 1x/2x/3x common battle clock, result/retry/next map/reload; combat duration matrices belong to backend QA."}
	var path: String = "user://qa_battle_mode_ui_packed.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_battle_mode_ui_headless.json"
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if output==null: quit(2);return
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("BATTLE_MODE_UI ",checks," checks / ",failures.size()," failures / ",snapshots.size()," snapshots; report=",ProjectSettings.globalize_path(path))
	if not failures.is_empty(): quit(1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
