extends SceneTree
## Real production cards, hover signals, placement previews and inspector labels.
## Geometry/combat eligibility matrices belong to qa_deployment_roles, not this UI test.
const Store = preload("res://native/progress.gd")
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var app: Node
var checks: int = 0
var failures: Array = []
var snapshots: Array = []
var context: String = ""
var hint_theme_changes: int = 0

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(context+" · "+message)
		if failures.size()<=30:
			push_error("DEPLOYMENT_UI "+context+" · "+message)

func settle() -> void:
	for frame in range(4):
		await process_frame

func wait_learning_ready() -> void:
	var deadline: int = Time.get_ticks_msec()+2000
	while app.learning_transition.is_busy() and Time.get_ticks_msec()<deadline:
		await process_frame
	check(not app.learning_transition.is_busy(),"Learning presentation reaches its deliberate input phase")

func named(parent: Node, id: String) -> Node:
	for child in parent.find_children(id,"",true,false):
		if child is Control and child.is_visible_in_tree() and not child.is_queued_for_deletion():
			return child
	return null

func motion(point: Vector2) -> void:
	var event = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	await settle()

func key(code: int) -> void:
	for pressed in [true,false]:
		var event = InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	await settle()

func press(card: Button) -> void:
	check(card!=null and not card.disabled,"Actual card action is available")
	if card!=null and not card.disabled:
		card.pressed.emit()
	await settle()

func fits(control: Control, bounds: Rect2, note: String) -> void:
	check(control.is_visible_in_tree() and bounds.grow(1).encloses(control.get_global_rect()),note+" fits its existing area")

func line_widths(label: Label, note: String) -> void:
	for line in label.text.split("\n"):
		var width: float = label.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x
		check(width<=label.size.x+1,note+" remains readable without horizontal clipping")
	check(label.get_combined_minimum_size().y<=label.size.y+1,note+" fits vertically without shrinking the font")

func on_hint_theme_changed() -> void:
	hint_theme_changes += 1

func record_snapshot(note: String, type_name: String = "") -> void:
	var pending: Dictionary = app.game.snapshot().pending
	var preview: Dictionary = app.game.placement_preview(app.game.placement_cursor)
	snapshots.append({"case":context,"note":note,"unit":type_name,"gold":app.game.gold,"permanentFunds":app.progress.data.army.currency,"chosen":app.chosen_unit_id,"pending":pending,"preview":preview,"guidance":app.hint_line.text,"guidanceVisible":app.hint_line.is_visible_in_tree(),"guidanceColor":app.hint_line.get_theme_color("font_color").to_html(),"toolbarRect":app.army_toolbar.get_global_rect(),"learningPhase":app.learning_transition.phase,"tacticalText":app.army_tactics.text,"tacticalVisible":app.army_panel.is_visible_in_tree()})

func locked_roster_checks() -> void:
	context = "fresh locked roster"
	app._select_map(0)
	app._begin_battle()
	await settle()
	var card: Button = app.army_grid.get_node("DeployCard_gunner")
	var gold: int = app.game.gold
	var selected: String = app.chosen_unit_id
	check(card.disabled and card.tooltip_text.contains("전장 3개 완료 시 해금"),"A fresh campaign keeps the original gunner unlock condition")
	check(card.tooltip_text.contains("청록 적 경로 전선") and card.tooltip_text.contains("짧은 거리 사격"),"Locked card still explains its actual future deployment role")
	await motion(Vector2(10,6))
	await motion(card.get_global_rect().get_center())
	record_snapshot("locked-hover","gunner")
	check(app.hint_line.visible and app.hint_line.text.contains("해금") and app.hint_line.text.contains("짧은 거리 사격"),"Hover explains a locked class without asking a learning question")
	card.pressed.emit()
	await settle()
	check(app.game.pending.is_empty() and app.game.gold==gold and app.chosen_unit_id==selected,"Disabled-class callback cannot reserve money or change the selected class")
	await motion(Vector2(10,6))
	check(not app.hint_bar.visible and app.hovered_unit_id.is_empty(),"Leaving the card clears its temporary deployment explanation")

func catalog_checks() -> void:
	app._show_catalog()
	await settle()
	var legend: Control = named(app.front_end,"DeploymentRoleLegend")
	var fixed: Label = named(app.front_end,"FixedEmplacementRole")
	var frontline: Label = named(app.front_end,"FrontlineRole")
	check(legend!=null and fixed!=null and frontline!=null,"Stage selection shows the two deployment areas immediately")
	if legend!=null and fixed!=null and frontline!=null:
		fits(legend,root.get_visible_rect(),"Deployment legend")
		fits(fixed,legend.get_global_rect(),"Fixed emplacement explanation")
		fits(frontline,legend.get_global_rect(),"Frontline explanation")
		check(fixed.get_theme_font_size("font_size")==20 and frontline.get_theme_font_size("font_size")==20,"New role explanations retain the minimum 20px text")
		check(fixed.text.contains("궁병") and fixed.text.contains("고정 진지"),"Archer is visibly associated with a fixed emplacement")
		check(frontline.text.contains("근접·기마") and frontline.text.contains("철포의 짧은 거리 사격"),"Frontline legend distinguishes melee/cavalry and gunner shooting")
		line_widths(fixed,"Fixed emplacement explanation")
		line_widths(frontline,"Frontline explanation")
	var description: Label = named(app.front_end,"StageTacticalDescription")
	check(description!=null and description.text==str(app.current_map.get("tactics",{}).get("descriptionKo","")),"Existing stage-specific strategy stays visible beside the new role legend")
	app.front_end.show_catalog(0,true)
	await settle()
	check(named(app.front_end,"DeploymentRoleLegend")==null,"Learning dictionary keeps its existing goal and content layout")
	app._select_map(0)
	await settle()
	var briefing_text: String = ""
	for label in app.modal_body.find_children("*","Label",true,false):
		briefing_text += str(label.text)+"\n"
	check(briefing_text.contains("궁병: 황금 고정 진지") and briefing_text.contains("근접·기마: 청록 적 경로 전선") and briefing_text.contains("철포: 청록 전선으로 접근한 뒤 짧은 거리 사격"),"Briefing states all three roles without the previous gunner high-ground instruction")
	fits(app.modal_footer,app.modal_card.get_global_rect(),"Original sortie footer")
	app._begin_battle()
	await settle()

func roster_checks() -> void:
	var viewport: Rect2 = root.get_visible_rect()
	check(app.army_grid.columns==8 and app.army_grid.get_child_count()==8,"All original eight classes remain in the fixed bottom row")
	check(app.army_toolbar.get_global_rect()==Rect2(16,viewport.size.y-92,viewport.size.x-32,80),"Toolbar position and dimensions are preserved")
	check(app.active_word.base_size==36 and app.example_label.base_size==24,"Japanese word and sentence sizes remain unchanged")
	var gold: int = app.game.gold
	var wallet: int = int(app.progress.data.army.currency)
	for id in TYPES:
		var card: Button = app.army_grid.get_node("DeployCard_"+id)
		var contract: Dictionary = app.game.placement_contract(id)
		fits(card,app.army_scroll.get_global_rect(),"Card "+id)
		check(not card.disabled,"Unlocked fixture exposes the original "+id+" card")
		check(card.get_meta("placement_mode")==contract.placementMode and card.get_meta("placement_role")==contract.placementRole,"Card "+id+" uses the production placement contract")
		check(card.get_theme_stylebox("hover").border_color==Color("ffda87" if id=="archer" else "73e5d2"),"Card "+id+" hover border matches its deployment area")
		check(card.tooltip_text.split("\n").size()==2,"Card "+id+" keeps a concise two-line tooltip")
		for child in card.get_children():
			if child is Label:
				check(child.get_theme_font_size("font_size")==20,"Card "+id+" preserves its original name/cost font")
		var before: String = app.chosen_unit_id
		await motion(card.get_global_rect().get_center())
		check(app.hovered_unit_id==id and app.hint_bar.visible,"Native pointer hover displays the "+id+" role")
		check(app.hint_line.text.contains("황금 고정 진지" if id=="archer" else "청록 적 경로 전선"),"Hover associates "+id+" with its allowed role area")
		check(app.chosen_unit_id==before and app.game.pending.is_empty() and app.game.gold==gold,"Hover remains free and leaves the current selection unchanged")
		line_widths(app.hint_line,"Card hover "+id)
		await motion(Vector2(10,6))
		await press(card)
		check(app.chosen_unit_id==id and str(app.game.pending.type)==id,"Choosing "+id+" prepares that class immediately")
		var preview: Dictionary = app.game.placement_preview(app.game.placement_cursor)
		check(preview.placementMode==contract.placementMode and preview.placementRole==app.army_grid.get_node("DeployCard_"+id).get_meta("placement_role"),"Chosen "+id+" guidance and actual highlight request use the same role")
		check(app.hint_line.text.contains("황금 고정 진지" if id=="archer" else "청록 적 경로 전선") and app.hint_line.text.contains("취소"),"Selected "+id+" retains concise placement and cancel instructions")
		check(app.hint_line.get_theme_color("font_color")==Color("ffda87" if id=="archer" else "73e5d2"),"Selected "+id+" uses its matching existing zone color")
		check(app.army_grid.get_node("DeployCard_"+id).get_theme_stylebox("normal").border_color==app.hint_line.get_theme_color("font_color"),"Selected "+id+" card and placement guide share the same area color")
		if id=="gunner":
			check(app.hint_line.text.contains("짧은 거리 사격") and not app.hint_line.text.contains("고정 진지"),"Gunner is explained as a short-range frontline shooter")
		check(app.game.gold==gold and int(app.progress.data.army.currency)==wallet,"Selection and preview do not change either money balance")
		line_widths(app.hint_line,"Pending "+id)
		record_snapshot("chosen",id)
		await key(KEY_ESCAPE)
		app._update_placement_feedback()
		check(app.game.pending.is_empty() and not app.hint_bar.visible,"Escape safely clears the role preview and instruction strip")
	check(app.game.units.is_empty(),"Free role preview never creates an actor")

func inspector_checks() -> void:
	for id in ["archer","gunner","spear"]:
		await press(app.army_grid.get_node("DeployCard_"+id))
		var point: Vector2 = Vector2(-1,-1)
		for candidate in app.game.placement_hints:
			if bool(app.game.placement_preview(candidate).valid):
				point = candidate
				break
		check(point.x>=0,"Real preview provides a visible location for inspecting "+id)
		if point.x<0:
			app.game.cancel_recruit()
			continue
		check(app.game.place_unit(point.x,point.y),"Production placement opens the actual "+id+" inspector")
		await settle()
		check(app.army_panel.visible,"Deployed "+id+" retains the existing inspector")
		check(app.army_tactics.text.contains(str(app.game.placement_contract(id).roleKo)),"Inspector explains the actual "+id+" role")
		if id=="gunner":
			check(app.army_tactics.text.contains("짧은 거리 사격") and not app.army_tactics.text.contains("저지") and app.army_health.visible,"Gunner shows health and shooting without claiming a melee block slot")
		elif id=="spear":
			check(app.army_tactics.text.contains("저지") and app.army_health.visible,"Frontline infantry keeps actual health and block counters")
		else:
			check(app.army_tactics.text.contains("황금 고정 진지") and not app.army_health.visible,"Archer retains a stationary shooting explanation")
		fits(app.army_panel,app.game.field_rect,"Selected inspector")
		line_widths(app.army_tactics,"Selected "+id+" status")
		record_snapshot("deployed",id)
	app.game.cancel_recruit()
	await motion(Vector2(10,6))
	app._update_placement_feedback()
	hint_theme_changes = 0
	for sample in range(100):
		app._update_placement_feedback()
	check(hint_theme_changes==0,"100 unchanged idle UI updates emit no redundant theme/color recalculations")

func feedback_and_intermission_checks() -> void:
	app._select_map(0)
	app._begin_battle()
	await settle()
	await press(app.army_grid.get_node("DeployCard_gunner"))
	app.game.placement_cursor = Vector2(-1,-1)
	app.game.placement_cursor_visible = true
	app._update_placement_feedback()
	check(app.hint_line.text==str(app.game.placement_preview(app.game.placement_cursor).reason) and app.hint_line.get_theme_color("font_color")==Color("dfb5a4"),"Invalid-position feedback shows the backend reason and existing error color")
	hint_theme_changes = 0
	for sample in range(100):
		app._update_placement_feedback()
	check(hint_theme_changes==0,"100 unchanged invalid preview updates do not reapply the same color override")
	app.game.placement_cursor_visible = false
	app._update_placement_feedback()
	check(app.hint_line.text==app.placement_guidance and app.hint_line.get_theme_color("font_color")==Color("73e5d2"),"Returning to the UI clears the rejection while retaining the frontline color")
	var pending: Dictionary = app.game.pending.duplicate(true)
	var gold: int = app.game.gold
	app.game.between_waves = true
	app.game.wave = 1
	app._on_state(app.game.snapshot())
	app._show_quiz()
	await wait_learning_ready()
	app.army_grid.get_node("DeployCard_archer").mouse_entered.emit()
	app._update_placement_feedback()
	check(not app.hint_line.visible and not app.army_toolbar.visible and app.hovered_unit_id.is_empty(),"Learning choice hides role guidance and ignores a hidden-card hover")
	app._continue_battle()
	await wait_learning_ready()
	app.game.set_process(false)
	app._update_placement_feedback()
	check(app.learning_transition.phase=="idle" and app.army_toolbar.visible and app.hint_line.visible,"Smooth battle return restores the existing role guidance and toolbar")
	check(app.game.pending==pending and app.game.gold==gold,"Learning skip preserves the unpaid class preview and both placement semantics and supply amount")
	record_snapshot("after-learning-return","gunner")
	app.game.cancel_recruit()
	app.army_grid.get_node("DeployCard_archer").mouse_entered.emit()
	app._show_catalog()
	app._update_placement_feedback()
	check(app.hovered_unit_id.is_empty() and not app.hint_line.visible,"Navigation clears the transient hovered-class instruction")
	app._resume_from_navigation()
	app._update_placement_feedback()
	check(not app.hint_bar.visible,"Navigation return does not resurrect a stale hover")

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/deployment-ui/"):
		push_error("Deployment UI QA refuses the player's profile")
		quit(2)
		return
	var fixture = Store.new()
	fixture.save_path = "user://deployment-ui-%d.json" % Time.get_ticks_msec()
	fixture.data.settings = {"music":false,"voice":false,"effects":false}
	check(fixture.write_save(),"Isolated fresh fixture saves")
	root.size = Vector2i(1280,800)
	root.content_scale_size = Vector2i(1280,800)
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = fixture.save_path
	root.add_child(app)
	await settle()
	app.set_process(false)
	app.game.set_process(false)
	app.troops_3d.set_process(false)
	app.troops_3d.hide()
	app.player.stop()
	app.battle_audio.set_enabled(false)
	app.hint_line.theme_changed.connect(on_hint_theme_changed)
	await locked_roster_checks()
	for stage in app.maps:
		app.progress.data.maps[str(stage.id)] = {"wins":1}
	check(app.progress.write_save(),"Unlocked UI fixture saves only inside its isolated profile")
	var wallet: int = int(app.progress.data.army.currency)
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		context = str(dimensions)
		root.size = dimensions
		root.content_scale_size = dimensions
		app._layout()
		await settle()
		await catalog_checks()
		app.game.set_process(false)
		await roster_checks()
		await inspector_checks()
	context = "feedback / navigation / learning return"
	await feedback_and_intermission_checks()
	check(int(app.progress.data.army.currency)==wallet,"Role UI changes never alter permanent funding")
	var report: Dictionary = {"checks":checks,"failures":failures,"productionSnapshots":snapshots,"driver":DisplayServer.get_name(),"profile":profile,"scope":"Actual production locked/unlocked eight-card roster, native Godot pointer hover and Escape, placement contract/highlight request, three unchanged viewports, stage legend/briefing/inspector, invalid reason recovery, repeated identical UI color updates and smooth learning/navigation restoration. Actual deployment eligibility and gunner combat are verified by separate backend QA."}
	var report_path: String = "user://qa_deployment_ui_packed.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_deployment_ui_headless.json"
	var output: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
	if output==null:
		push_error("Deployment UI QA could not save its report")
		quit(2)
		return
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("DEPLOYMENT_UI ",checks," checks / ",failures.size()," failures / ",snapshots.size()," production snapshots; report=",ProjectSettings.globalize_path(report_path))
	app._cancel_learning_transition()
	app.player.stop()
	app.player.stream = null
	app.battle_audio.shutdown()
	await create_timer(.5).timeout
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
