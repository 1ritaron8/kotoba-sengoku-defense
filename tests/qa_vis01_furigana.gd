extends SceneTree

const Ruby = preload("res://native/ruby_label.gd")
const Readings = preload("res://native/ruby_readings.gd")
const Style = preload("res://native/sengoku_ui.gd")
const Fonts = preload("res://native/game_fonts.gd")
const Feedback = preload("res://native/combat_feedback.gd")
const FrontEnd = preload("res://native/front_end.gd")
class FeedbackField extends Node2D:
	var field_rect: Rect2=Rect2(0,0,1280,560)
	var projectiles: Array=[]
	var paused: bool=false
	var speed: float=1.0
var checks: int=0
var failures: Array=[]
var cases: Array=[]
var callbacks: int=0
var source_before: Dictionary={}
const SOURCES: Array[String]=["native/ruby_label.gd","native/ruby_readings.gd","native/ruby_readings.json","native/sengoku_ui.gd","native/combat_feedback.gd","native/front_end.gd","native/battlefield_hud.gd","tests/qa_vis01_furigana.gd"]

func _initialize() -> void:
	source_before=source_hashes()
	call_deferred("run")

func source_hashes() -> Dictionary:
	var result: Dictionary={}
	for name_value in DirAccess.get_files_at("res://native"):
		if name_value.get_extension() in ["gd","json","tscn","gdshader"]:
			result["native/"+name_value]=FileAccess.get_sha256("res://native/"+name_value)
	for path in SOURCES:
		result[path]=FileAccess.get_sha256("res://"+path)
	for path in [Fonts.HEADING_PATH,Fonts.BODY_PATH,Fonts.JAPANESE_PATH,Fonts.READING_PATH,Fonts.FALLBACK_PATH]: result[path]=FileAccess.get_sha256(path)
	for path in Style.MATERIAL_PATHS.values(): result[path]=FileAccess.get_sha256(path)
	return result

func check(condition: bool, detail: String) -> void:
	checks+=1
	if not condition: failures.append(detail)

func frames() -> void:
	for index in range(3): await process_frame

func inspect(ruby: Control, expected: String, name_value: String) -> void:
	check(is_instance_valid(ruby),name_value+": actual Ruby child exists")
	if not is_instance_valid(ruby): return
	var layout: Dictionary=ruby.get_text_layout()
	check(ruby.text==expected,name_value+": original text retained")
	check(Readings.uncovered_kanji(Readings.for_word(ruby.word)).is_empty(),name_value+": every Han span annotated")
	var readings: int=0
	var body: String=""
	for item in layout.runs:
		if item.role=="reading":
			readings+=1
			check(int(item.size)>=16,name_value+": visible reading >=16px")
		elif item.role=="body": body+=str(item.text)
		check(Rect2(Vector2.ZERO,ruby.size).grow(.5).encloses(item.bounds),name_value+": complete run within Ruby bounds: "+str(item.text))
	check(readings>0,name_value+": actual reading draw runs")
	check(body.replace(" ","").replace("\n","")==expected.replace(" ","").replace("\n",""),name_value+": complete original body drawn")
	check(ruby.visible and ruby.modulate.a>0 and ruby.self_modulate.a>0,name_value+": annotated child visible")
	check(not ruby.is_processing() and not ruby.is_physics_processing(),name_value+": no per-frame polling")
	cases.append({"name":name_value,"text":expected,"bodyRuns":layout.runs.size(),"readingRuns":readings,"size":str(ruby.size),"height":layout.height})

func run() -> void:
	root.theme=Fonts.theme()
	for phrase in ["補給任務","聞き取り","音楽","音声","効果音","選択","出陣","勝利","撤退","続行","作戦会議","本陣へ","兵営","解禁試験","軍資金","の記録","名詞","五段","一段","来る","来て","静かな","大きいです","小さい","先に","場合","一方で","限り","次に","た後"]:
		check(Readings.uncovered_kanji(Readings.for_text(phrase)).is_empty(),"observed actual UI gap covered: "+phrase)
	for resolution in [Vector2(1440,900),Vector2(1280,800)]:
		var host: Control=Control.new()
		host.size=resolution
		root.add_child(host)
		var menu: Control=FrontEnd.new()
		var map_button: Button=menu._ruby_button({"jp":"全国地図","reading":"ぜんこくちず","ko":"전국 지도","parts":[{"text":"全国","reading":"ぜんこく"},{"text":"地図","reading":"ちず"}]},Rect2(78,477,430,132),func(): callbacks+=1)
		map_button.reparent(host)
		menu.free()
		await frames()
		var map_ruby: Control=map_button.get_node("MenuRuby")
		inspect(map_ruby,"全国地図","actual FrontEnd campaign-map button")
		check(map_button.get_global_rect().encloses(map_ruby.get_global_rect()),"actual campaign-map Ruby fits allocated button")
		var label: Label=Style.TooltipLabel.new()
		label.size=Vector2(260,86)
		label.vertical_alignment=VERTICAL_ALIGNMENT_BOTTOM
		label.add_theme_font_override("font",Fonts.body())
		label.add_theme_font_size_override("font_size",22)
		label.text="全国地図 · 전국 지도"
		host.add_child(label)
		await frames()
		inspect(label.ruby_text,label.text,str(resolution)+": label")
		var old_y: float=label.ruby_text.position.y
		label.size.y+=40
		await frames()
		check(is_equal_approx(label.ruby_text.position.y,old_y+40),"height-only bottom alignment updates")
		label.text="伝令 · 전령 보고"
		await frames()
		inspect(label.ruby_text,label.text,"dynamic native Label.text")
		label.text="春信"
		label.ruby_context_words=[{"jp":"春信","reading":"はるのぶ"}]
		await frames()
		inspect(label.ruby_text,label.text,"contextual proper name")
		label.ruby_context_words=[{"jp":"春信","reading":"はるのぶ"}]
		check(label.ruby_text.word.jp=="春信","same-text context setter refresh")
		var button: Button=Style.TooltipButton.new()
		button.size=Vector2(252,92)
		button.custom_minimum_size.y=42
		button.add_theme_font_override("font",Fonts.body())
		button.add_theme_font_size_override("font_size",22)
		button.text="鍛錬 · 병종 연습"
		button.pressed.connect(func(): callbacks+=1)
		host.add_child(button)
		await frames()
		inspect(button.ruby_text,button.text,"typed Button body")
		check(button.get_theme_stylebox("normal")!=null,"native Button material retained")
		button.pressed.emit()
		check(callbacks>0,"original Button callback retained")
		old_y=button.ruby_text.position.y
		button.size.y+=40
		await frames()
		check(is_equal_approx(button.ruby_text.position.y,old_y+20),"height-only Button centering updates")
		button.add_theme_font_override("font",Fonts.japanese())
		await frames()
		check(button.ruby_text.font==Fonts.japanese(),"same-size font swap updates Ruby font")
		button.add_theme_color_override("font_color",Color("79b3d4"))
		await frames()
		check(button.ruby_text.ink.is_equal_approx(Color("79b3d4")),"theme ink update retained")
		button.text="연습"
		await frames()
		check(button.text=="연습" and not button.ruby_text.visible,"Kana/Korean-only native text retained")
		check(is_equal_approx(button.custom_minimum_size.y,42),"Kanji to Korean restores native Button minimum")
		var tip: Control=Ruby.make_tooltip("春信 · 하루노부\n全国地図 · 지도",[{"jp":"春信","reading":"はるのぶ"}])
		host.add_child(tip)
		await frames()
		inspect(tip.get_node("TooltipRuby"),"春信 · 하루노부\n全国地図 · 지도","actual contextual tooltip")
		check(tip.size.y<resolution.y,"tooltip fits viewport height")
		check(not Readings.uncovered_kanji(Readings.for_text("戦闘")).is_empty(),"unknown compound never guesses music 戦 reading")
		var field: Node2D=FeedbackField.new()
		field.field_rect.size.x=resolution.x-24
		host.add_child(field)
		var feedback: Node2D=Feedback.new()
		feedback.battle=field
		host.add_child(feedback)
		feedback.consume_event({"type":"wavebegin","wave":3})
		check(feedback.banner=="第 03 陣  ·  敵襲" and is_equal_approx(feedback.banner_clock,1.15),"wave event content and lifetime unchanged")
		var banner_layout: Dictionary=feedback.annotated_text_layout(feedback.banner,19)
		var kana: int=0
		for run_value in banner_layout.runs:
			if run_value.role=="reading": kana+=1; check(int(run_value.size)>=16,"wave banner reading >=16px")
		check(kana>0 and Readings.uncovered_kanji(Readings.for_text(feedback.banner)).is_empty(),"actual wave draw path uses complete annotated runs")
		feedback.consume_event({"type":"waveend"})
		check(feedback.banner=="陣を守り抜いた  ·  방어 성공" and is_equal_approx(feedback.banner_clock,1.05),"defense event content and lifetime unchanged")
		check(Readings.uncovered_kanji(Readings.for_text(feedback.banner)).is_empty(),"defense sentence covered without guessed readings")
		host.queue_free()
		await frames()
	var after: Dictionary=source_hashes()
	check(source_before==after,"exact consumed sources unchanged")
	var report: Dictionary={"status":"PASS" if failures.is_empty() else "FAIL","scope":"Focused display-only native Label/Button/tooltip contract; no full Main, gameplay, GPU or style acceptance","checks":checks,"failures":failures,"cases":cases,"sourcesBefore":source_before,"sourcesAfter":after,"sourcesFrozen":source_before==after}
	var file: FileAccess=FileAccess.open("user://qa-vis01-furigana.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("VIS01_FURIGANA ",report.status," ",checks," / ",failures.size()," ",ProjectSettings.globalize_path("user://qa-vis01-furigana.json"))
	for failure in failures: print("FAIL ",failure)
	quit(0 if failures.is_empty() else 1)
