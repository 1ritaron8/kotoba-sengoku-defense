extends SceneTree
## Measure the actual bottom learning strip using every authored text and the
## bundled production font. This does not claim GPU appearance or speech QA.
const Store = preload("res://native/progress.gd")
const EPS: float = .75
var app: Node
var font: Font
var checks: int = 0
var failures: Array = []
var failure_details: Array = []
var samples: int = 0
var context: String = ""
var viewport_results: Array = []
var smallest_japanese: Dictionary = {"word":99,"original":99,"transfer":99,"expression":99}
var widest_korean: Dictionary = {}
var glyph_presence: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String, details: Dictionary = {}) -> void:
	checks += 1
	if condition:
		return
	var failure: String = context+" · "+message
	failures.append(failure)
	if not details.is_empty():
		var item: Dictionary = details.duplicate(true)
		item.context = context
		item.message = message
		failure_details.append(item)
	if failures.size()<=24:
		push_error(failure+" "+JSON.stringify(details))

func enclosed(inner: Rect2, outer: Rect2) -> bool:
	return outer.grow(EPS).encloses(inner)

func rect_of(control: Control) -> Rect2:
	return Rect2(control.position,control.size)

func glyph_rect(value: String, point_size: int, baseline: Vector2) -> Rect2:
	return Rect2(baseline-Vector2(0,font.get_ascent(point_size)),Vector2(font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x,font.get_height(point_size)))

func font_has_text(value: String) -> bool:
	var available: bool = true
	for character in value:
		if character in ["\n","\r","\t"]:
			continue
		var code: int = character.unicode_at(0)
		if not glyph_presence.has(code):
			glyph_presence[code] = font.has_char(code)
		available = available and bool(glyph_presence[code])
	return available

func painted_glyphs_in_field(control: Control, glyphs: Rect2, description: String) -> void:
	var outline: float = float(control.outline_size)
	var painted: Rect2 = Rect2(control.get_global_rect().position+glyphs.position,glyphs.size).grow(outline)
	check(enclosed(painted,app.field_clip.get_global_rect()),description+" including its outline remains within the battlefield",{"painted":str(painted),"field":str(app.field_clip.get_global_rect()),"outline":outline})

func ruby_metrics(control: Control, expected: Dictionary, kind: String) -> void:
	var bound: Rect2 = Rect2(Vector2.ZERO,control.size)
	var jp: String = str(expected.get("jp",""))
	var ko: String = str(expected.get("ko",""))
	check(control.word==expected,kind+" binds the complete original dictionary")
	check(control.font==font and font.resource_path=="res://assets/fonts/NotoSansCJKjp-Regular.otf",kind+" uses the actual bundled Noto font")
	check(not control.wrap_japanese,kind+" uses the shipped compact single-line strip renderer")
	check(control.base_size==(36 if kind=="word" else 24),kind+" preserves the configured Japanese point size")
	check(control.meaning_visible,kind+" keeps the Korean meaning visible")
	check(control.outline_size==2,kind+" uses the small subtitle outline over scenery")
	check(font_has_text(jp) and font_has_text(str(expected.get("reading",""))) and font_has_text(ko),kind+" has every JP/reading/KO glyph available")
	# The renderer may reduce a line to fit. Measure all emitted parts, rather
	# than treating a matching minimum-size request as proof of readable text.
	var text_size: int = int(control.base_size)
	while text_size>14 and font.get_string_size(jp,HORIZONTAL_ALIGNMENT_LEFT,-1,text_size).x>control.size.x-8:
		text_size -= 1
	smallest_japanese[kind] = mini(int(smallest_japanese[kind]),text_size)
	var parts: Array = control._pieces()
	var total_width: float = 0
	var complete_japanese: String = ""
	for part in parts:
		var body: String = str(part.get("text",""))
		total_width += font.get_string_size(body,HORIZONTAL_ALIGNMENT_LEFT,-1,text_size).x
		complete_japanese += body
	check(complete_japanese==jp,kind+" emits every authored Japanese character")
	check(total_width<=control.size.x-8+EPS,kind+" full Japanese line fits horizontally",{"jp":jp,"size":text_size,"needed":total_width,"available":control.size.x-8})
	var cursor: float = maxf(4,(control.size.x-total_width)/2)
	var baseline: float = int(control.base_size)+19
	for part in parts:
		var body: String = str(part.get("text",""))
		var reading: String = str(part.get("reading",""))
		var width: float = font.get_string_size(body,HORIZONTAL_ALIGNMENT_LEFT,-1,text_size).x
		var body_rect: Rect2 = glyph_rect(body,text_size,Vector2(cursor,baseline))
		check(enclosed(body_rect,bound),kind+" Japanese glyph metrics fit vertically and horizontally",{"jp":body,"glyphRect":str(body_rect),"controlRect":str(bound)})
		painted_glyphs_in_field(control,body_rect,kind+" Japanese glyphs")
		check(enclosed(Rect2(control.position+body_rect.position,body_rect.size),Rect2(Vector2.ZERO,app.learning_panel.size)),kind+" Japanese glyphs remain inside the strip parent")
		if not reading.is_empty() and reading!=body:
			var ruby_size: int = maxi(8,int(text_size*.34))
			while ruby_size>6 and font.get_string_size(reading,HORIZONTAL_ALIGNMENT_LEFT,-1,ruby_size).x>width:
				ruby_size -= 1
			var ruby_width: float = font.get_string_size(reading,HORIZONTAL_ALIGNMENT_LEFT,-1,ruby_size).x
			var ruby_rect: Rect2 = glyph_rect(reading,ruby_size,Vector2(cursor+(width-ruby_width)/2,14))
			check(ruby_width<=width+EPS,kind+" full furigana fits its corresponding Japanese span",{"body":body,"reading":reading,"rubySize":ruby_size,"needed":ruby_width,"available":width})
			check(enclosed(ruby_rect,bound),kind+" furigana glyph metrics fit its text area",{"reading":reading,"glyphRect":str(ruby_rect),"controlRect":str(bound)})
			painted_glyphs_in_field(control,ruby_rect,kind+" furigana")
			check(enclosed(Rect2(control.position+ruby_rect.position,ruby_rect.size),Rect2(Vector2.ZERO,app.learning_panel.size)),kind+" furigana remains inside the strip parent")
		cursor += width
	var ko_size: int = int(control.meaning_size)
	while ko_size>18 and font.get_string_size(ko,HORIZONTAL_ALIGNMENT_LEFT,-1,ko_size).x>control.size.x-8:
		ko_size -= 1
	var ko_width: float = font.get_string_size(ko,HORIZONTAL_ALIGNMENT_LEFT,-1,ko_size).x
	if not widest_korean.has(kind) or ko_width>float(widest_korean[kind].width):
		widest_korean[kind] = {"width":ko_width,"available":control.size.x,"text":ko,"context":context}
	check(ko_width<=control.size.x+EPS,kind+" complete Korean original fits horizontally",{"ko":ko,"size":ko_size,"needed":ko_width,"available":control.size.x})
	var korean_rect: Rect2 = glyph_rect(ko,ko_size,Vector2((control.size.x-ko_width)/2,baseline+28))
	check(enclosed(korean_rect,bound),kind+" Korean glyph metrics fit its text area",{"ko":ko,"glyphRect":str(korean_rect),"controlRect":str(bound)})
	painted_glyphs_in_field(control,korean_rect,kind+" Korean meaning")
	check(enclosed(Rect2(control.position+korean_rect.position,korean_rect.size),Rect2(Vector2.ZERO,app.learning_panel.size)),kind+" Korean original stays inside the strip parent")
	check(not Rect2(control.position+korean_rect.position,korean_rect.size).intersects(rect_of(app.learning_panel.get_node("ListenButton"))) and not Rect2(control.position+korean_rect.position,korean_rect.size).intersects(rect_of(app.learning_panel.get_node("NextWordButton"))),kind+" original Korean does not overlap learning buttons")

func inspect_strip(viewport_size: Vector2i) -> void:
	context = str(viewport_size)+" geometry"
	check(app.learning_panel.size.y==92,"Production subtitle area is 92px high")
	check(app.army_toolbar.size.y==80,"Production army toolbar is enlarged to 80px high")
	check(app.learning_panel.get_theme_stylebox("panel") is StyleBoxEmpty,"Subtitles have no background panel")
	check(app.learning_panel.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Subtitle background preserves battlefield input")
	check(not app.learning_panel.clip_contents,"Subtitle outlines may use the surrounding clear battlefield padding")
	check(enclosed(app.learning_panel.get_global_rect(),Rect2(Vector2.ZERO,Vector2(viewport_size))),"Learning strip is inside the viewport")
	check(not app.learning_panel.get_global_rect().intersects(app.army_toolbar.get_global_rect()),"Learning strip does not overlap the fixed army toolbar")
	check(enclosed(app.learning_panel.get_global_rect(),app.field_clip.get_global_rect()),"Transparent subtitles sit wholly inside the battlefield")
	for control in [app.active_word,app.example_label,app.learning_panel.get_node("ListenButton"),app.learning_panel.get_node("NextWordButton")]:
		check(enclosed(rect_of(control),Rect2(Vector2.ZERO,app.learning_panel.size)),"Learning child is inside its strip parent",{"name":str(control.name),"child":str(rect_of(control)),"parent":str(app.learning_panel.size)})
	check(not rect_of(app.active_word).intersects(rect_of(app.example_label)),"Active word and example have separate text areas")
	var listen: Button = app.learning_panel.get_node("ListenButton")
	var next_word: Button = app.learning_panel.get_node("NextWordButton")
	check(not rect_of(listen).intersects(rect_of(next_word)),"Listen and next-word buttons remain separate")
	for button in [listen,next_word]:
		check(not rect_of(button).intersects(rect_of(app.active_word)) and not rect_of(button).intersects(rect_of(app.example_label)),"Fixed learning button does not cover the text areas")
		var button_font: Font = button.get_theme_font("font")
		var button_size: int = button.get_theme_font_size("font_size")
		var style: StyleBox = button.get_theme_stylebox("normal")
		var inner: Vector2 = button.size-Vector2(style.get_content_margin(SIDE_LEFT)+style.get_content_margin(SIDE_RIGHT),style.get_content_margin(SIDE_TOP)+style.get_content_margin(SIDE_BOTTOM))
		check(button_font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button_size).x<=inner.x+EPS,"Learning button's complete caption fits style margins")
		check(button_font.get_height(button_size)<=inner.y+EPS,"Learning button's glyph height fits style margins")

func run() -> void:
	var workspace: String = ProjectSettings.globalize_path("res://").replace("\\","/").simplify_path().to_lower()
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	var packed: bool = "--packed" in OS.get_cmdline_user_args()
	if not profile.begins_with(qa_project_path("").to_lower()+"/") or (not packed and not profile.begins_with(workspace)):
		push_error("Learning strip QA refuses a non-workspace player profile")
		quit(2)
		return
	var save_path: String = "user://learning-strip-%d.json" % Time.get_ticks_msec()
	var store = Store.new()
	store.save_path = save_path
	store.data.settings = {"music":false,"voice":false}
	check(store.write_save(),"Isolated fixture saves without touching player progress")
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = save_path
	root.add_child(app)
	for index in range(3): await process_frame
	app.set_process(false)
	app.game.set_process(false)
	app.troops_3d.set_process(false)
	app.atmosphere.set_process(false)
	app.learning_field.set_process(false)
	app.front_end.hide()
	app._close_modal(false)
	app.ui.show()
	app.battle_started = false
	app.japanese_voice = ""
	app.progress.data.settings.voice = false
	app.player.stop()
	app.player.stream = null
	font = app.font
	var lessons: Array = []
	for tier in app.TIER_IDS: lessons.append_array(app.curriculum[tier])
	var word_count: int = 0
	var sentence_count: int = 0
	var expression_count: int = 0
	for lesson in lessons:
		word_count += lesson.get("newWords",[]).size()
		expression_count += lesson.get("expressions",[]).size()
		for word in lesson.get("newWords",[]):
			for key in ["example","transferExample"]:
				if not word.get(key,{}).is_empty(): sentence_count += 1
	check(lessons.size()==40 and word_count==900,"Actual Main loads forty lessons and all nine hundred words")
	check(sentence_count==1800,"Both authored example sentences exist for every word")
	check(expression_count==80,"All eighty authored lesson expressions exist")
	for viewport_size in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		app._layout()
		for frame in range(2): await process_frame
		var before_samples: int = samples
		var before_failures: int = failures.size()
		inspect_strip(viewport_size)
		for lesson in lessons:
			app.current_lesson = lesson.duplicate(true)
			app.current_lesson.expressions = []
			for word in lesson.get("newWords",[]):
				app.learning_words = [word]
				app.learning_index = -1
				app._advance_word()
				app._layout()
				context = "%dx%d %s word" % [viewport_size.x,viewport_size.y,str(word.id)]
				ruby_metrics(app.active_word,word,"word")
				samples += 1
				context = "%dx%d %s original" % [viewport_size.x,viewport_size.y,str(word.id)]
				ruby_metrics(app.example_label,word.example,"original")
				samples += 1
				# Transfer text is exercised in the same actual Control and size;
				# the current automatic strip cycle only selects original examples.
				app.example_label.set_word(word.transferExample,24)
				app._layout()
				context = "%dx%d %s transfer" % [viewport_size.x,viewport_size.y,str(word.id)]
				ruby_metrics(app.example_label,word.transferExample,"transfer")
				samples += 1
			for expression in lesson.get("expressions",[]):
				app.current_lesson.expressions = [expression]
				var word: Dictionary = lesson.newWords[0]
				app.learning_words = [word,word,word,word]
				app.learning_index = 2
				app._advance_word()
				app._layout()
				context = "%dx%d %s expression %s" % [viewport_size.x,viewport_size.y,str(lesson.id),str(expression.jp)]
				ruby_metrics(app.example_label,expression,"expression")
				samples += 1
			await process_frame
		viewport_results.append({"width":viewport_size.x,"height":viewport_size.y,"samples":samples-before_samples,"failures":failures.size()-before_failures,"wordRect":str(app.active_word.get_global_rect()),"exampleRect":str(app.example_label.get_global_rect())})
		print("BATTLE_STRIP_VIEWPORT ",JSON.stringify(viewport_results[-1]))
	app.queue_free()
	await process_frame
	await create_timer(.5).timeout
	var report: Dictionary = {"checks":checks,"failures":failures,"failureDetails":failure_details,"samples":samples,"words":word_count,"sentences":sentence_count,"expressions":expression_count,"viewports":viewport_results,"smallestRenderedJP":smallest_japanese,"widestKorean":widest_korean,"scope":"Actual Main scene, transparent 92px subtitle area inside the battlefield, enlarged 80px army toolbar and bundled Noto font. 900 words, 900 original examples, 900 transfer examples and 80 expressions at three viewport sizes. Words/originals/expressions use the production _advance_word callback; transfer examples are bound to the same production text Control without claiming the automatic cycle currently chooses them. Complete JP/ruby/KO font metrics, glyph coverage, text-area containment, 2px outline padding inside the field, transparent input behavior and fixed-button separation are measured. GPU appearance, speech, answer scoring and proficiency are outside this headless test."}
	var report_path: String = "user://qa_battle_learning_strip.json" if packed else "res://tests/qa_battle_learning_strip.json"
	var output: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
	if output==null:
		push_error("Cannot save bottom learning strip QA report: "+report_path)
		quit(2)
		return
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("BATTLE_LEARNING_STRIP_QA ",JSON.stringify({"checks":checks,"failures":failures.size(),"samples":samples,"viewports":viewport_results,"smallestRenderedJP":smallest_japanese}))
	print("BATTLE_LEARNING_STRIP_REPORT "+ProjectSettings.globalize_path(report_path))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
