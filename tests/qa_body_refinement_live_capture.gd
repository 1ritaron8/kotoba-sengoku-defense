extends SceneTree
## Real barracks screenshots and untouched idle animation, in an isolated profile.

const Store = preload("res://native/progress.gd")
const FRAME_COUNT: int = 12
const FRAME_INTERVAL: float = 1.0/12.0
var app: Node
var checks: int = 0
var failures: Array = []
var capture_log: Array = []
var frame_clocks: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("BARRACKS LIVE CAPTURE: "+message)

func settle(seconds: float = .35) -> void:
	await create_timer(seconds).timeout
	await process_frame
	await RenderingServer.frame_post_draw

func live_portrait() -> Node:
	return app.barracks.find_child("SelectedArmyPortrait",true,false)

func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	check(frame != null and frame.get_width()==root.size.x and frame.get_height()==root.size.y,"Full-size UI screenshot matches the real window")
	check(frame.save_png(path)==OK,"PNG saved: "+path)
	var portrait: Node = live_portrait()
	check(portrait != null and portrait.active,"Selected portrait is live and visible")
	check(portrait.actor != null and portrait.viewport.get_texture().get_image() != null,"A real hero model viewport is rendered")
	capture_log.append({"path":path,"windowWidth":root.size.x,"windowHeight":root.size.y,"portrait":portrait.diagnostics()})
	print("BARRACKS_LIVE_SCREENSHOT ",path," ",JSON.stringify(portrait.diagnostics()))

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Barracks live capture requires an actual GPU display driver")
		quit(2)
		return
	var workspace: String = ProjectSettings.globalize_path("res://").replace("\\","/").to_lower()
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with(workspace):
		push_error("Refusing player profile; redirect APPDATA to a workspace test profile")
		quit(2)
		return
	root.size = Vector2i(1440,900)
	root.title = "말의 전장 · 실시간 병영 검수"
	app = load("res://native/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	# Fresh defaults are restored in memory on repeated fixture runs. No player
	# save is loaded outside the guarded workspace profile or written by this test.
	var fresh = Store.new()
	app.progress.data = fresh.data.duplicate(true)
	app.progress.save_path = "user://barracks-live-capture-progress.json"
	check(app.progress.unlocked_units()==["archer","spear"],"Fresh roster contains only the two starter classes")
	check(app.progress.army_level("archer")==1,"Fresh selected archer remains permanent Lv1")
	app._show_home()
	app._show_barracks()
	await settle(.5)
	check(app.barracks.selected_unit_id=="archer","Fresh barracks selects the starter archer")
	check(live_portrait().unit_id=="archer" and live_portrait().evolution_stage==0,"Initial live model is the actual basic archer")
	await capture("res://dist/preview-refined-barracks-starter.png")
	# Deliberate rendering fixture for an earned final evolution. It does not
	# claim campaign balance or persist fabricated clears to the player's save.
	for index in range(14):
		app.progress.data.maps[str(app.maps[index].id)] = {"wins":1}
	app.progress.data.army.currency = 1540
	app.progress.data.army.levels.samurai = 8
	app.progress.data.army.selected = "samurai"
	app.barracks._select_unit("samurai")
	await settle(.5)
	check("samurai" in app.progress.unlocked_units(),"Fixture samurai is unlocked after fourteen clears")
	check(app.progress.army_level("samurai")==8,"Fixture uses actual Lv8 evolution mapping")
	check(live_portrait().unit_id=="samurai" and live_portrait().evolution_stage==2,"Selected live samurai is the final evolution")
	await capture("res://dist/preview-refined-barracks-samurai.png")
	root.size = Vector2i(1280,800)
	await settle(.4)
	await capture("res://dist/preview-refined-barracks-samurai-1280.png")
	root.size = Vector2i(1440,900)
	await settle(.4)
	var portrait: Node = live_portrait()
	var initial_clock: float = portrait.elapsed
	var initial_torso: Transform3D = portrait.actor.bones.torso.transform
	var camera_transform: Transform3D = portrait.camera.global_transform
	check(DirAccess.make_dir_recursive_absolute("res://tests/body-refinement-live-frames")==OK,"Frame output directory exists")
	for index in range(FRAME_COUNT):
		# Waiting lets the production _process(delta) advance naturally. The test
		# never applies an actor pose, changes animationClock or moves the camera.
		await create_timer(FRAME_INTERVAL).timeout
		await RenderingServer.frame_post_draw
		var frame: Image = root.get_texture().get_image()
		frame.resize(640,400,Image.INTERPOLATE_LANCZOS)
		check(frame.save_png("res://tests/body-refinement-live-frames/frame%03d.png" % index)==OK,"Actual UI animation frame saved")
		frame_clocks.append(portrait.elapsed)
		check(portrait.camera.global_transform.is_equal_approx(camera_transform),"Production portrait camera remains stationary")
	check(portrait.elapsed>initial_clock+1.0,"Natural real-time idle animation advances")
	check(not portrait.actor.bones.torso.transform.is_equal_approx(initial_torso),"Whole torso idle pose changes without fixture pose injection")
	var report = {"checks":checks,"failures":failures,"profile":profile,"screenshots":capture_log,"frameCount":FRAME_COUNT,"frameSize":[640,400],"frameClocks":frame_clocks,"animation":"production idle, natural real elapsed, stationary production camera"}
	var output: FileAccess = FileAccess.open("res://tests/qa_body_refinement_live_capture.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	# Stop playback before destroying the app and give AudioServer time to drain.
	for player in app.find_children("*","AudioStreamPlayer",true,false):
		player.stop()
		player.stream = null
	AudioServer.set_bus_mute(0,true)
	DisplayServer.tts_stop()
	await create_timer(.5).timeout
	app.queue_free()
	await process_frame
	print("BARRACKS_LIVE_CAPTURE ",JSON.stringify({"checks":checks,"failures":failures,"frames":FRAME_COUNT}))
	quit(0 if failures.is_empty() else 1)
