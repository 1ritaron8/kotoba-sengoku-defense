extends SceneTree

var app: Node
var checks: int = 0
var failures: Array[String] = []
var events: Array = []

func _initialize() -> void:
	Engine.max_fps=120
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		push_error("DEPLOYMENT_CLICK: "+note)

func settle(count: int = 6) -> void:
	for unused in range(count): await process_frame

func click_card(id: String) -> void:
	var card: Button=app.army_grid.get_node("DeployCard_"+id)
	check(card!=null and not card.disabled,"The actual troop card is available: "+id)
	var center: Vector2=card.get_global_rect().get_center()
	check(root.get_visible_rect().has_point(center),"The actual card is visible and clickable: "+id)
	var move = InputEventMouseMotion.new()
	move.position=center
	move.global_position=center
	Input.parse_input_event(move)
	await process_frame
	var pressed = InputEventMouseButton.new()
	pressed.button_index=MOUSE_BUTTON_LEFT
	pressed.position=center
	pressed.global_position=center
	pressed.pressed=true
	Input.parse_input_event(pressed)
	await process_frame
	var released = InputEventMouseButton.new()
	released.button_index=MOUSE_BUTTON_LEFT
	released.position=center
	released.global_position=center
	released.pressed=false
	Input.parse_input_event(released)
	await settle()

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/deployment-click/").to_lower()):
		quit(2)
		return
	root.content_scale_size=Vector2i(1280,800)
	root.size=Vector2i(1280,800)
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path="user://deployment-click-%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app.game.set_process(false)
	app.atmosphere.set_process(false)
	app.troops_3d.set_process(false)
	await settle()
	app._set_audio_volume("masterVolume",0.0)
	app._select_map(0)
	app._begin_battle()
	await settle()
	var game: Node2D=app.game
	game.set_process(false)
	game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	check(app._can_prepare_placement() and game.gold==280 and game.units.is_empty(),"The fresh first battle is actually ready for card input")
	check(game.snapshot().emplacementProtectionActive,"The new account keeps its initial safe shooting emplacements")
	app.chosen_march_path=1
	await click_card("spear")
	check(game.recruitment_queue.size()==1 and game.pending.is_empty() and game.gold==215 and game.units.is_empty(),"One real spear-card click pays once and starts delayed production at the base")
	if game.recruitment_queue.size()==1:
		check(game.recruitment_queue[0].pathIndex==1 and is_equal_approx(float(game.recruitment_queue[0].totalSeconds),2.275),"Card production uses the selected lane and the actual production duration")
	await click_card("spear")
	check(game.recruitment_queue.size()==2 and game.gold==150 and game.units.is_empty(),"A second real card click starts a separate parallel production job")
	if game.recruitment_queue.size()==2:
		check(is_equal_approx(float(game.recruitment_queue[0].remainingSeconds),float(game.recruitment_queue[1].remainingSeconds)),"Neither queued card order waits behind the other")
	for unused in range(22): game._process(0.1)
	check(game.units.is_empty(),"Cards never create instant soldiers before production completes")
	for unused in range(4): game._process(0.1)
	check(game.units.size()==2 and game.recruitment_queue.is_empty(),"Both real card orders create their soldiers when the timers finish")
	var positions: Dictionary={}
	for unit in game.units:
		check(unit.type=="spear" and int(unit.campaignLevel)==1,"Card births are the actual untrained starter class")
		positions[int(unit.id)]=Vector2(unit.position)
	for unused in range(70): game._process(0.1)
	for unit in game.units:
		if positions.has(int(unit.id)):
			check(Vector2(unit.position).distance_to(positions[int(unit.id)])>.02,"A real card-born soldier gathers and advances along its lane")
	var before_gold: int=game.gold
	var before_jobs: int=game.recruitment_queue.size()
	await click_card("archer")
	check(not game.pending.is_empty() and game.pending.type=="archer" and game.gold==before_gold and game.recruitment_queue.size()==before_jobs,"A placed archer card instead opens its location preview without charging")
	game.cancel_recruit()
	app.progress.data.army.levels.spear=5
	game.configure_roster(app.progress.unit_catalog,app.progress.unlocked_units(),app.progress.data.army.levels)
	app._rebuild_army_cards()
	await settle()
	app._choose_unit("spear")
	check(str(app.army_grid.get_node("DeployCard_spear/RecruitPrice_spear").text)=="90" and app.recruit_button.text.contains("90"),"The actual Lv5 card and repeat-recruit button display the approved 90 gold")
	check(game.recruitment_queue.size()==before_jobs+1 and int(game.recruitment_queue[-1].cost)==90 and int(game.recruitment_queue[-1].quantity)==2 and is_equal_approx(float(game.recruitment_queue[-1].totalSeconds),2.275),"The Lv5 UI really submits the approved two-person 90-gold production order")
	app._save_audio_settings()
	var file=FileAccess.open("user://qa_deployment_click.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"events":events},"\t"))
	file.close()
	print("DEPLOYMENT_CLICK checks=",checks," failures=",failures.size())
	app._stop_narration()
	app.player.stop()
	app.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
