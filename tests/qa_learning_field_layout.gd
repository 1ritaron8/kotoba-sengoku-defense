extends SceneTree
const Field=preload("res://native/learning_field.gd")
var checks: int=0
var failures: Array=[]
var largest_banner: Vector2=Vector2.ZERO
var answered: Array=[]

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		if failures.size()<20: push_error("LEARNING FIELD LAYOUT "+message)

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/learning-field-layout/").to_lower()):
		push_error("Learning field layout QA refuses a player profile")
		quit(2)
		return
	var plans: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	var field=Field.new()
	field.font=load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	root.add_child(field)
	field.target_chosen.connect(func(id: String): answered.append(id))
	var missions: int=0
	for dimensions in [Vector2(1280,570),Vector2(1440,670)]:
		field.size=dimensions
		for stage_id in plans.stages:
			for mission in plans.stages[stage_id].missions:
				missions+=1
				var prefix: String=str(mission.id)+" "+str(dimensions)
				field.show_report(mission,false)
				check(not field.choosing and field.report_card.visible and not field.action_card.visible,prefix+": passive report has only its banner")
				check(field.target_buttons.is_empty() and field.target_anchors.is_empty(),prefix+": passive report creates no target cards or map connector marks")
				check(field.mouse_filter==Control.MOUSE_FILTER_IGNORE,prefix+": passive report permits battlefield input")
				check(field.report_card.position==Vector2(12,12) and field.report_card.size.x<=620,prefix+": banner stays at the upper left and within its 620px limit")
				check(Rect2(Vector2.ZERO,dimensions).encloses(field.report_card.get_rect()),prefix+": full banner stays inside the battlefield")
				check(field.report_text.meaning_visible and field.report_text.word==mission.report,prefix+": Japanese, furigana parts and Korean translation retain the original report")
				check(field.report_text.base_size>=22 and field.report_text.meaning_size>=18,prefix+": compact report retains readable Japanese and Korean sizes")
				check(field.report_card.get_theme_stylebox("panel") is StyleBoxEmpty and field.report_text.outline_size==2,prefix+": passive subtitle has no background or border and outlines its text")
				check(field.report_text.get_rect().end.y<=field.report_card.size.y and field.report_text.size.y>=field.report_text.custom_minimum_size.y,prefix+": the actual wrapped ruby text fits within the banner")
				largest_banner=largest_banner.max(field.report_card.size)
				var clock: float=field.report_clock
				field.flow_paused=true
				field._process(1)
				check(is_equal_approx(field.report_clock,clock),prefix+": pause keeps the passive report lifetime fixed")
				field.flow_paused=false
				field._process(clock+1)
				check(not field.report_card.visible and field.target_buttons.is_empty(),prefix+": passive expiry hides its banner without leaving marks")
				field.begin_choice(mission,false)
				check(field.choosing and not field.resolved and field.action_card.visible,prefix+": actual between-wave location choice retains its actions")
				check(not field.report_text.meaning_visible and field.report_text.meaning_size==20,prefix+": the question still hides translation and restores its usual sizes")
				check(not field.report_card.get_theme_stylebox("panel") is StyleBoxEmpty and field.report_text.outline_size==0,prefix+": actual choice restores its readable interaction panel without changing other ruby styling")
				check(field.target_buttons.size()==mission.targets.size() and field.target_buttons.size()==3,prefix+": all three original target choices are available")
				check(field.mouse_filter==Control.MOUSE_FILTER_STOP and not field.continue_button.disabled,prefix+": active choice owns input and preserves skip")
				check(field.listen_button.disabled,prefix+": missing Japanese voice stays disabled")
				check(Rect2(Vector2.ZERO,field.action_card.size).encloses(field.feedback.get_rect()),prefix+": the first wrapped instruction fits its action card")
				check(field.feedback.get_rect().end.y<=field.hint_button.position.y,prefix+": wrapped instruction does not cover the footer buttons")
				for index in range(field.target_buttons.size()):
					var button: Button=field.target_buttons[index]
					check(button.visible and not button.disabled and button.mouse_filter==Control.MOUSE_FILTER_STOP,prefix+": active target is interactive")
					check(Rect2(Vector2.ZERO,dimensions).encloses(button.get_rect()),prefix+": active target card fits the field")
					check(field.target_anchors[index].is_equal_approx(Vector2(float(mission.targets[index].position.x),float(mission.targets[index].position.y))),prefix+": real map target coordinate is preserved")
					var previous: int=answered.size()
					button.pressed.emit()
					check(answered.size()==previous+1 and str(answered.back())==str(mission.targets[index].id),prefix+": choice emits the exact original answer identifier")
				field.show_hint()
				check(field.hinted and field.report_text.meaning_visible and field.hint_button.disabled,prefix+": hint remains sticky and exposes translation")
				check(field.feedback.text.contains("+25"),prefix+": existing hinted reward copy is unchanged")
				field.show_result(true,"임무 성공")
				check(field.resolved and field.feedback.text=="임무 성공" and field.continue_button.text=="다음 전투 ›",prefix+": resolved result still offers the next battle")
				for button in field.target_buttons: check(button.disabled,prefix+": resolved target cannot answer again")
				field.suspend_choice()
				check(not field.visible and field.mouse_filter==Control.MOUSE_FILTER_IGNORE,prefix+": catalog navigation suspends choice input")
				field.clear()
				check(field.mission.is_empty() and field.target_buttons.is_empty() and not field.report_card.visible,prefix+": clear removes all learning overlay state")
	check(missions==240,"All 120 actual missions were checked at both minimum and standard field dimensions")
	var output=FileAccess.open("user://qa_learning_field_layout.json",FileAccess.WRITE)
	check(output!=null,"Isolated layout QA report opens")
	if output!=null:
		output.store_string(JSON.stringify({"checks":checks,"failures":failures,"missionLayouts":missions,"largestBanner":{"width":largest_banner.x,"height":largest_banner.y},"scope":"120 real mission reports at two field sizes; passive content/visibility/input/lifetime and active target geometry, exact answer IDs, hint, resolved and navigation behavior."},"  "))
		output.close()
	print("LEARNING_FIELD_LAYOUT_QA ",JSON.stringify({"checks":checks,"failures":failures,"missionLayouts":missions,"largestBanner":largest_banner}))
	field.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
