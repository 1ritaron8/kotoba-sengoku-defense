extends SceneTree
## Actual main.gd modal layout, authored curriculum, Noto font and production theme.
## Tasks are issued as UI fixtures; this test does not exercise TTS or learning scores.
const EPS: float = 0.8
var app: Node
var font: Font
var checks: int = 0
var failures: Array = []
var samples: int = 0
var context: String = ""
var phase_counts: Dictionary = {}
var kind_counts: Dictionary = {}
var viewport_results: Array = []
var widest_japanese: Dictionary = {}
var longest_feedback: Dictionary = {}
var maximum_rows: int = 0
var overflow_samples: int = 0
var extremes_only: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		var message: String = context+" · "+description
		failures.append(message)
		if failures.size()<=30: push_error(message)

func enclosed(inner: Rect2, outer: Rect2) -> bool:
	return outer.grow(EPS).encloses(inner)

func in_parent(child: Control, parent: Control, description: String) -> void:
	check(enclosed(Rect2(child.position,child.size),Rect2(Vector2.ZERO,parent.size)),description+" inside parent · "+str(child.position)+" "+str(child.size)+" parent "+str(parent.size))

func glyph_rect(text: String, point_size: int, baseline: Vector2) -> Rect2:
	return Rect2(baseline-Vector2(0,font.get_ascent(point_size)),Vector2(font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x,font.get_height(point_size)))

func inspect_ruby(control: Control) -> void:
	var bound: Rect2 = Rect2(Vector2.ZERO,control.size)
	var layout: Dictionary = control.get_text_layout()
	check(int(layout.body_size) in [36,44],"Quiz preserves its current sentence or word font size")
	var observed: String = ""
	var observed_ko: String = ""
	var japanese_baselines: Dictionary = {}
	for run in layout.runs:
		var actual: Rect2 = glyph_rect(str(run.text),int(run.size),run.position)
		check(enclosed(actual,bound),"Complete glyph ascent/descent fits the actual RubyText control")
		var content_rect: Rect2 = Rect2(actual.position+control.position,actual.size)
		check(enclosed(content_rect,Rect2(Vector2.ZERO,app.modal_body.size)),"Complete text stays inside scrollable content")
		for sibling in app.modal_body.get_children():
			if sibling is Control and sibling!=control:
				check(not content_rect.intersects(Rect2(sibling.position,sibling.size)),"Text does not cover a neighbouring control")
		if run.role=="reading":
			check(int(run.size)>=16,"Furigana stays at least 16px")
		elif run.role=="body":
			observed += str(run.text)
			japanese_baselines[run.position.y] = true
		elif run.role=="meaning":
			observed_ko += str(run.text)
	for first in range(layout.runs.size()):
		for second in range(first+1,layout.runs.size()):
			check(not layout.runs[first].bounds.intersects(layout.runs[second].bounds),"Reading, Japanese and translation do not overlap")
	check(observed.replace(" ","")==str(control.word.get("jp","")).replace(" ","").replace("\n",""),"Every authored Japanese character is laid out")
	if control.meaning_visible:
		check(observed_ko.replace(" ","")==str(control.word.get("ko","")).replace(" ","").replace("\n",""),"Complete Korean meaning is preserved")
	maximum_rows = maxi(maximum_rows,japanese_baselines.size())

func inspect_label(label: Label, description: String) -> void:
	var face: Font = label.get_theme_font("font")
	var point_size: int = label.get_theme_font_size("font_size")
	var rows: int = label.get_line_count()
	var height: float = rows*face.get_height(point_size)+(rows-1)*label.get_theme_constant("line_spacing")
	check(label.get_visible_line_count()>=rows,description+" displays all actual wrapped lines")
	check(height<=label.size.y+EPS,description+" glyph height fits")
	if label.autowrap_mode==TextServer.AUTOWRAP_OFF:
		for line in label.text.split("\n"): check(face.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x<=label.size.x+EPS,description+" width fits")

func inspect_button(button: Button) -> void:
	in_parent(button,button.get_parent(),"Button "+button.text)
	var face: Font = button.get_theme_font("font")
	var point_size: int = button.get_theme_font_size("font_size")
	var style: StyleBox = button.get_theme_stylebox("disabled" if button.disabled else "normal")
	var inner: Vector2 = button.size-Vector2(style.get_content_margin(SIDE_LEFT)+style.get_content_margin(SIDE_RIGHT),style.get_content_margin(SIDE_TOP)+style.get_content_margin(SIDE_BOTTOM))
	var actual: Vector2 = face.get_multiline_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,inner.x,point_size,-1,TextServer.BREAK_MANDATORY|TextServer.BREAK_WORD_BOUND|TextServer.BREAK_ADAPTIVE) if button.autowrap_mode!=TextServer.AUTOWRAP_OFF else face.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size)
	check(actual.x<=inner.x+EPS,"Button complete text fits its styled width: "+button.text)
	check(actual.y<=inner.y+EPS,"Button complete wrapped text fits its styled height: "+button.text)
	check(enclosed(button.get_global_rect(),app.modal_scroll.get_global_rect()) or enclosed(button.get_global_rect(),app.modal_footer.get_global_rect()) or button.get_parent()!=app.modal_footer,"Button remains in its own scroll/footer region")

func inspect(phase: String, variant: String, word: Dictionary, viewport_size: Vector2i) -> void:
	samples += 1
	phase_counts[phase] = int(phase_counts.get(phase,0))+1
	kind_counts[variant] = int(kind_counts.get(variant,0))+1
	context = "%dx%d %s %s %s" % [viewport_size.x,viewport_size.y,str(word.id),variant,phase]
	check(app.modal_context=="quiz" and app.modal!=null,"Production quiz modal is displayed")
	in_parent(app.modal_card,app.modal,"Quiz card")
	in_parent(app.modal_scroll,app.modal_card,"Scrollable content")
	in_parent(app.modal_footer,app.modal_card,"Fixed footer")
	check(not app.modal_scroll.get_global_rect().intersects(app.modal_footer.get_global_rect()),"Scrollable content and fixed footer do not overlap")
	check(app.modal_scroll.horizontal_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"Content never requires horizontal scrolling")
	in_parent(app.quiz_ruby,app.modal_body,"Japanese text area")
	inspect_ruby(app.quiz_ruby)
	for child in app.modal_body.get_children():
		if child is Label:
			in_parent(child,app.modal_body,"Quiz instruction")
			inspect_label(child,"Quiz instruction")
	for index in range(app.quiz_choices.size()):
		var button: Button = app.quiz_choices[index]
		inspect_button(button)
		for previous in range(index): check(not button.get_global_rect().intersects(app.quiz_choices[previous].get_global_rect()),"Choice buttons do not overlap")
		check(not button.get_global_rect().intersects(app.quiz_ruby.get_global_rect()),"Choice does not cover Japanese text")
	in_parent(app.quiz_feedback,app.modal_footer,"Feedback label")
	inspect_label(app.quiz_feedback,"Hint/result feedback")
	var footer_row: Control = app.quiz_continue_button.get_parent()
	in_parent(footer_row,app.modal_footer,"Fixed action row")
	check(not footer_row.get_global_rect().intersects(app.quiz_feedback.get_global_rect()),"Fixed buttons do not cover hint or result feedback")
	for child in footer_row.get_children():
		if child is Button:
			inspect_button(child)
			check(enclosed(child.get_global_rect(),app.modal_footer.get_global_rect()),"Footer button stays on screen inside its fixed footer")
	check(footer_row.get_child_count()==3,"Hint, listening and skip/continue all retain their footer slots")
	for index in range(footer_row.get_child_count()):
		for previous in range(index): check(not footer_row.get_child(index).get_global_rect().intersects(footer_row.get_child(previous).get_global_rect()),"Footer buttons do not overlap each other")
	var bar: VScrollBar = app.modal_scroll.get_v_scroll_bar()
	if app.modal_body.size.y>app.modal_scroll.size.y+EPS:
		overflow_samples += 1
		check(bar.max_value-bar.page>0,"Overflowing content has a working vertical scroll range")
		var bottom: float = app.modal_body.get_global_rect().end.y
		check(bottom-(bar.max_value-bar.page)<=app.modal_scroll.get_global_rect().end.y+EPS,"Scroll range can reach the complete final content row")
	var jp_width: float = font.get_string_size(str(app.quiz_word.get("jp","")),HORIZONTAL_ALIGNMENT_LEFT,-1,32).x
	if jp_width>float(widest_japanese.get("width",0)): widest_japanese={"id":word.id,"variant":variant,"jp":app.quiz_word.jp,"width":jp_width}
	var feedback_width: float = font.get_string_size(app.quiz_feedback.text,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x
	if feedback_width>float(longest_feedback.get("width",0)): longest_feedback={"id":word.id,"variant":variant,"text":app.quiz_feedback.text,"width":feedback_width}

func task_for(word: Dictionary, variant: String) -> Dictionary:
	var item: Dictionary = word.get("example",{}) if variant=="original" else word.get("transferExample",{}) if variant=="transfer" else word
	var kind: String = "sentence" if variant in ["original","transfer"] else "listening" if variant=="listening" else "meaning"
	var choices: Array = app.lesson_session._choices(word,item,kind)
	return {"id":"modal-fixture:"+str(word.id)+":"+variant,"item":item,"itemId":word.id,"kind":kind,"skill":"context" if kind=="sentence" else kind,"contextId":"fixture","choices":choices,"answerId":word.id}

func show_task(task: Dictionary, phase: String) -> void:
	app.quiz_task = task.duplicate(true)
	app.quiz_hinted = phase=="hint"
	app.quiz_resolved = phase in ["wrong","correct"]
	app.quiz_feedback_text = "정답입니다. 보급금 +70를 받았습니다." if phase=="correct" else "뜻은 ‘%s’입니다. 맞춤 복습에 반영했습니다." % str(task.item.get("ko",""))
	app._show_quiz()
	if phase=="hint": app.quiz_feedback.text="힌트: %s  ·  정답 보급금 +25" % str(task.item.get("ko",""))
	app._layout()
	for step in range(3): await process_frame

func extremes(lesson: Dictionary) -> Array:
	var chosen: Dictionary = {}
	for variant in ["meaning","original","transfer"]:
		for language in ["jp","ko"]:
			var largest: Dictionary = {}
			var width: float = -1
			for word in lesson.newWords:
				var item: Dictionary = word if variant=="meaning" else word.example if variant=="original" else word.transferExample
				var candidate_width: float = font.get_string_size(str(item.get(language,"")),HORIZONTAL_ALIGNMENT_LEFT,-1,36 if language=="jp" else 20).x
				if candidate_width>width: width=candidate_width; largest=word
			chosen[str(largest.id)+":"+variant]={"word":largest,"variant":variant}
	return chosen.values()

func run() -> void:
	extremes_only = OS.get_cmdline_user_args().has("--extremes-only")
	var workspace: String = ProjectSettings.globalize_path("res://").replace("\\","/").to_lower()
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with(workspace):
		push_error("Modal QA requires workspace-isolated APPDATA")
		quit(2)
		return
	var scene: PackedScene = load("res://native/main.tscn")
	app = scene.instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.game.set_process(false)
	app.troops_3d.set_process(false)
	app.atmosphere.set_process(false)
	app.learning_field.set_process(false)
	app.front_end.hide()
	app.ui.show()
	app.japanese_voice = ""
	app.progress.data.settings.voice = false
	app.player.stop()
	app.player.stream = null
	font = app.font
	check(font!=null and font.resource_path=="res://assets/fonts/NotoSansCJKjp-Regular.otf","Actual production Noto font is bound")
	check(app.words_by_id.size()==900,"All nine hundred authored words are loaded")
	var lessons: Array = []
	for tier in app.TIER_IDS: lessons.append_array(app.curriculum[tier])
	check(lessons.size()==40,"All forty real lessons are loaded")
	for viewport_size in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		app._layout()
		await process_frame
		var before_samples: int = samples
		var before_failures: int = failures.size()
		for lesson_index in range(lessons.size()):
			var lesson: Dictionary = lessons[lesson_index]
			app.lesson_session.begin_lesson(lesson,app.maps[lesson_index])
			app.lesson_session.rng.seed = 41371+lesson_index
			for word in lesson.newWords:
				if extremes_only:
					continue
				for variant in ["meaning","original","transfer"]:
					var task: Dictionary = task_for(word,variant)
					await show_task(task,"choice")
					inspect("choice",variant,word,viewport_size)
			var selected: Array = extremes(lesson)
			for item in selected:
				for phase in (["choice","hint","wrong","correct"] if extremes_only else ["hint","wrong","correct"]):
					var task: Dictionary = task_for(item.word,item.variant)
					await show_task(task,phase)
					inspect(phase,item.variant,item.word,viewport_size)
			# Listening uses the actual longest instruction/display word in this
			# lesson; forced issuance is explicitly UI-only, with platform TTS off.
			var longest_word: Dictionary = lesson.newWords[0]
			for word in lesson.newWords:
				if font.get_string_size(str(word.jp),HORIZONTAL_ALIGNMENT_LEFT,-1,44).x>font.get_string_size(str(longest_word.jp),HORIZONTAL_ALIGNMENT_LEFT,-1,44).x: longest_word=word
			for phase in ["choice","hint","wrong","correct"]:
				var task: Dictionary = task_for(longest_word,"listening")
				await show_task(task,phase)
				inspect(phase,"listening",longest_word,viewport_size)
		viewport_results.append({"width":viewport_size.x,"height":viewport_size.y,"samples":samples-before_samples,"failures":failures.size()-before_failures})
		print("MODAL_VIEWPORT "+JSON.stringify(viewport_results[-1]))
	app._close_modal(false)
	app.queue_free()
	await process_frame
	await create_timer(.5).timeout
	var coverage: String = "Noto width extrema from all 40 lessons in choice/hint/wrong/correct states at three window sizes." if extremes_only else "Every authored meaning/original/transfer choice at three window sizes, and Noto width extrema in hint/wrong/correct states."
	var report: Dictionary={"checks":checks,"failures":failures,"samples":samples,"wordsLoaded":900,"lessons":40,"extremesOnly":extremes_only,"phaseCounts":phase_counts,"kindCounts":kind_counts,"viewports":viewport_results,"maxJapaneseRows":maximum_rows,"overflowSamples":overflow_samples,"widestJapanese":widest_japanese,"longestFeedback":longest_feedback,"scope":"Actual production main.tscn, main.gd, RubyText and inherited theme. "+coverage+" Forced listening UI states; complete JP/ruby/KO glyph metrics, scroll reach and fixed footer separation. GPU appearance, answer scoring, reading proficiency and real TTS playback are outside this test."}
	var output: FileAccess=FileAccess.open("res://tests/qa_learning_modal.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("LEARNING_MODAL_QA "+JSON.stringify({"checks":checks,"failures":failures.size(),"samples":samples,"viewports":viewport_results,"maxJapaneseRows":maximum_rows}))
	quit(0 if failures.is_empty() else 1)
