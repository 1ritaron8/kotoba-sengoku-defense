extends SceneTree
## Instantiate the actual learning overlay and measure its controls and glyphs.
## This is a headless layout check, not a replacement for GPU visual review.
const LearningField = preload("res://native/learning_field.gd")
const UIStyle = preload("res://native/sengoku_ui.gd")
const FONT_PATH = "res://assets/fonts/NotoSansCJKjp-Regular.otf"
const EPS = 0.75
var checks: int = 0
var failures: Array = []
var samples: int = 0
var phase_counts: Dictionary = {}
var viewport_results: Array = []
var font: Font
var field: Control
var context: String = ""
var largest_japanese_rows: int = 0
var smallest_report_size: int = 99
var largest_report_height: float = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		var item: String = context+" · "+message
		failures.append(item)
		if failures.size()<=35:
			push_error(item)

func enclosed(inner: Rect2, outer: Rect2) -> bool:
	return outer.grow(EPS).encloses(inner)

func local_rect(control: Control) -> Rect2:
	return Rect2(control.position,control.size)

func in_parent(control: Control, parent: Control, description: String) -> void:
	var fits: bool = enclosed(local_rect(control),Rect2(Vector2.ZERO,parent.size))
	check(fits,description+" stays inside its parent"+(" · actual "+str(local_rect(control))+" parent "+str(parent.size) if not fits else ""))

func glyph_rect(text: String, point_size: int, baseline: Vector2, face: Font) -> Rect2:
	# Font metrics are independent of the layout's minimum-height calculation.
	var advance: float = face.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x
	return Rect2(baseline-Vector2(0,face.get_ascent(point_size)),Vector2(advance,face.get_height(point_size)))

func ruby_content(control: Control, description: String) -> void:
	var bound: Rect2 = Rect2(Vector2.ZERO,control.size)
	var layout: Dictionary = control.get_text_layout()
	var observed_japanese: String = ""
	var observed_korean: String = ""
	var japanese_baselines: Dictionary = {}
	for run in layout.runs:
		var actual: Rect2 = glyph_rect(str(run.text),int(run.size),run.position,font)
		check(enclosed(actual,bound),description+" full glyph metrics fit the allocated text area")
		if run.role=="reading":
			check(int(run.size)>=16,description+" furigana stays at least 16px")
		elif run.role=="body":
			observed_japanese += str(run.text)
			japanese_baselines[run.position.y] = true
		elif run.role=="meaning":
			observed_korean += str(run.text)
	for first in range(layout.runs.size()):
		for second in range(first+1,layout.runs.size()):
			check(not layout.runs[first].bounds.intersects(layout.runs[second].bounds),description+" reading, Japanese and translation remain separate")
	check(observed_japanese.replace(" ","")==str(control.word.get("jp","")).replace(" ","").replace("\n",""),description+" preserves every authored Japanese character")
	if control.meaning_visible:
		check(observed_korean.replace(" ","")==str(control.word.get("ko","")).replace(" ","").replace("\n",""),description+" preserves the complete Korean translation")
	if control==field.report_text:
		largest_japanese_rows = maxi(largest_japanese_rows,japanese_baselines.size())
		smallest_report_size = mini(smallest_report_size,int(layout.body_size))
		check(int(layout.body_size)==36 if field.choosing else int(layout.body_size) in [22,24],"Report preserves the current full-screen or compact font size")

func label_content(label: Label, description: String) -> void:
	var lines: int = label.get_line_count()
	var point_size: int = label.get_theme_font_size("font_size")
	var real_font: Font = label.get_theme_font("font")
	var needed_height: float = lines*real_font.get_height(point_size)+(lines-1)*label.get_theme_constant("line_spacing")
	check(label.get_visible_line_count()>=lines,description+" displays every wrapped line")
	check(needed_height<=label.size.y+EPS,description+" wrapped glyph metrics fit its height")
	if label.autowrap_mode==TextServer.AUTOWRAP_OFF:
		for line in label.text.split("\n"):
			check(real_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x<=label.size.x+EPS,description+" text fits its width")

func button_content(button: Button, parent: Control, description: String) -> void:
	in_parent(button,parent,description)
	var point_size: int = button.get_theme_font_size("font_size")
	var real_font: Font = button.get_theme_font("font")
	var box: StyleBox = button.get_theme_stylebox("disabled" if button.disabled else "normal")
	var inner: Vector2 = button.size-Vector2(box.get_content_margin(SIDE_LEFT)+box.get_content_margin(SIDE_RIGHT),box.get_content_margin(SIDE_TOP)+box.get_content_margin(SIDE_BOTTOM))
	check(real_font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x<=inner.x+EPS,description+" complete text fits inside style margins")
	check(real_font.get_height(point_size)<=inner.y+EPS,description+" font fits inside vertical style margins")
	for child in button.get_children():
		if child is Control:
			in_parent(child,button,description+" child text")
			if child is Label:
				label_content(child,description+" target label")
			elif child.get_script()!=null and child.get_script().resource_path=="res://native/ruby_label.gd":
				ruby_content(child,description+" target ruby")

func inspect(phase: String, mission: Dictionary, viewport_size: Vector2i) -> void:
	samples += 1
	phase_counts[phase] = int(phase_counts.get(phase,0))+1
	context = "%dx%d %s %s" % [viewport_size.x,viewport_size.y,str(mission.get("id","")),phase]
	if field.choosing:
		check(field.target_buttons.size()==mission.get("targets",[]).size(),"Every interactive world target has a visible button")
	else:
		check(field.target_buttons.is_empty(),"Passive report leaves the battlefield free of target buttons")
		check(not field.action_card.visible,"Passive report has no quiz action card")
		check(field.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Passive report preserves battlefield mouse input")
		check(field.report_card.size.x<=620+EPS,"Passive report stays in a compact banner")
	in_parent(field.report_card,field,"Report card")
	in_parent(field.report_heading,field.report_card,"Report heading")
	in_parent(field.report_text,field.report_card,"Report text")
	label_content(field.report_heading,"Report heading")
	ruby_content(field.report_text,"Report text")
	largest_report_height = maxf(largest_report_height,field.report_card.size.y)
	var report: Rect2 = local_rect(field.report_card)
	var action: Rect2 = local_rect(field.action_card)
	for index in range(field.target_buttons.size()):
		var button: Button = field.target_buttons[index]
		button_content(button,field,"Target %d" % index)
		var target: Rect2 = local_rect(button)
		check(not target.intersects(report),"Target %d does not overlap the report card" % index)
		for other in range(index):
			check(not target.intersects(local_rect(field.target_buttons[other])),"Target %d does not overlap target %d" % [index,other])
		var anchor: Vector2 = field.target_anchors[index]*field.size
		check(enclosed(Rect2(anchor-Vector2(13,13),Vector2(26,26)),Rect2(Vector2.ZERO,field.size)),"Target %d world marker is inside the battlefield" % index)
		if field.action_card.visible:
			check(not target.intersects(action),"Target %d does not overlap the action card" % index)
	if field.action_card.visible:
		in_parent(field.action_card,field,"Action card")
		check(not report.intersects(action),"Report and action card remain separate")
		in_parent(field.feedback,field.action_card,"Feedback")
		label_content(field.feedback,"Feedback")
		for button in [field.hint_button,field.listen_button,field.continue_button]:
			button_content(button,field.action_card,"Footer "+button.text)
			check(not local_rect(button).intersects(local_rect(field.feedback)),"Footer button does not cover feedback")
		check(not local_rect(field.hint_button).intersects(local_rect(field.listen_button)) and not local_rect(field.listen_button).intersects(local_rect(field.continue_button)),"Footer buttons do not overlap")

func settle() -> void:
	await process_frame
	await process_frame

func run() -> void:
	var workspace: String = ProjectSettings.globalize_path("res://").replace("\\","/").to_lower()
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var packed: bool = "--packed" in OS.get_cmdline_user_args()
	if not profile.begins_with("c:/jp_df/") or (not packed and not profile.begins_with(workspace)):
		push_error("Layout QA requires workspace-isolated APPDATA")
		quit(2)
		return
	font = load(FONT_PATH)
	check(font!=null and font.resource_path==FONT_PATH,"Real bundled Noto Japanese/Korean font is loaded")
	var plans = JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	var missions: Array = []
	for stage in plans.get("stages",{}).values():
		missions.append_array(stage.get("missions",[]))
	check(missions.size()==120,"All 120 authored battlefield missions are inspected")
	field = LearningField.new()
	field.font = font
	# The production overlay inherits main.gd's common button skin. Preserve
	# that inheritance, including the disabled state's content margins.
	var inherited_theme: Theme = Theme.new()
	inherited_theme.default_font = font
	inherited_theme.default_font_size = 22
	for style_name in ["normal","hover","pressed","disabled","focus"]:
		inherited_theme.set_stylebox(style_name,"Button",UIStyle.button(style_name))
	field.theme = inherited_theme
	root.add_child(field)
	field.set_process(false)
	for viewport_size in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		field.position = Vector2(16,64)
		field.size = Vector2(viewport_size.x-32,viewport_size.y-164)
		await settle()
		var before_checks: int = checks
		var before_failures: int = failures.size()
		for mission in missions:
			field.position = Vector2(16,64)
			field.size = Vector2(viewport_size.x-32,viewport_size.y-164)
			field.show_report(mission,false)
			await settle()
			inspect("report",mission,viewport_size)
			field.position = Vector2.ZERO
			field.size = viewport_size
			field.begin_choice(mission,false)
			await settle()
			inspect("choice",mission,viewport_size)
			field.show_hint()
			await settle()
			inspect("hint",mission,viewport_size)
			field.show_result(true,"보급 +70 · 선택한 지점 공격 지원 12초\n"+str(mission.get("successKo","요청한 위치에 지원을 보냈습니다.")))
			await settle()
			inspect("result_correct",mission,viewport_size)
			var answer_name: String = ""
			for target in mission.get("targets",[]):
				if str(target.get("id",""))==str(mission.get("answerId","")):
					answer_name = str(target.get("label",{}).get("ko",""))
			field.show_result(false,"요청한 위치는 ‘%s’입니다.\n이 표현을 맞춤 복습에 반영했습니다." % answer_name)
			await settle()
			inspect("result_wrong",mission,viewport_size)
		viewport_results.append({"width":viewport_size.x,"height":viewport_size.y,"fieldWidth":field.size.x,"fieldHeight":field.size.y,"checks":checks-before_checks,"failures":failures.size()-before_failures})
	field.clear()
	field.queue_free()
	await process_frame
	var report: Dictionary = {"checks":checks,"failures":failures,"missions":missions.size(),"samples":samples,"phaseCounts":phase_counts,"viewports":viewport_results,"smallestReportJP":smallest_report_size,"maxJapaneseRows":largest_japanese_rows,"maxReportHeight":largest_report_height,"scope":"120 authored battlefield reports at three window sizes in five states: passive compact 22/24px banner, plus full-screen choice/hint/correct/wrong reports at 36px. Actual settled Controls and independent Noto glyph extents at the production drawn baselines; minimum 16px furigana, complete translations and non-overlapping text. GPU appearance and platform TTS are outside this headless test."}
	var report_path: String = "user://qa_learning_layout.json" if packed else "res://tests/qa_learning_layout.json"
	var output: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
	if output==null:
		push_error("Cannot save layout QA report: "+report_path)
		quit(2)
		return
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("LEARNING_LAYOUT_QA "+JSON.stringify({"checks":checks,"failures":failures.size(),"missions":missions.size(),"samples":samples,"viewports":viewport_results,"smallestReportJP":smallest_report_size,"maxJapaneseRows":largest_japanese_rows}))
	print("LEARNING_LAYOUT_REPORT "+ProjectSettings.globalize_path(report_path))
	quit(0 if failures.is_empty() else 1)
