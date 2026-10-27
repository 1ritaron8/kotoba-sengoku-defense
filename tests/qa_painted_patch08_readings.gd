extends SceneTree
## HQ-only engine execution. Read-only source/data QA; no save or asset writes.
const Ruby = preload("res://native/ruby_label.gd")
const Readings = preload("res://native/ruby_readings.gd")
const UI = preload("res://native/sengoku_ui.gd")
const Fonts = preload("res://native/game_fonts.gd")
var checks: Array=[]
var failures: Array=[]

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, name: String, detail: Variant={}) -> void:
	checks.append({"name":name,"pass":ok,"detail":detail})
	if not ok: failures.append(name)

func _linear(value: float) -> float:
	return value/12.92 if value<=.04045 else pow((value+.055)/1.055,2.4)

func _luminance(ink: Color) -> float:
	return _linear(ink.r)*.2126+_linear(ink.g)*.7152+_linear(ink.b)*.0722

func _word(name: String, value: Dictionary, dark: bool=false, minimum_groups: int=1) -> void:
	var ruby: Control=Ruby.new()
	ruby.size.x=760
	ruby.wrap_japanese=true
	ruby.ink=Color("30251b") if dark else Color("eee8d9")
	ruby.reading_ink=ruby.ink
	ruby.set_word(value,24,true)
	var parts: Array=Readings.for_word(value)
	var layout: Dictionary=ruby.get_text_layout()
	var body: Dictionary={}
	var kana: Dictionary={}
	var consistent: bool=true
	for run in layout.runs:
		if run.role=="body": body[int(run.group)]=Color(run.color)
		elif run.role=="reading": kana[int(run.group)]=Color(run.color)
	for group in kana:
		if not body.has(group) or body[group]!=kana[group]: consistent=false
	_check(Readings.uncovered_kanji(parts).is_empty(),name+":verified_annotation",parts)
	_check(int(layout.colouredGroups)>=minimum_groups,name+":coloured_groups",layout.colouredGroups)
	_check(consistent and not kana.is_empty(),name+":body_reading_correspondence")
	var colours: Array=[]
	for group in kana:
		var pigment: Color=kana[group]
		if not colours.has(pigment): colours.append(pigment)
		if dark:
			var contrast: float=(_luminance(Color("ebdfc8"))+.05)/(_luminance(pigment)+.05)
			_check(contrast>=4.5,name+":paper_contrast_%d"%group,contrast)
	if minimum_groups>1: _check(colours.size()>1,name+":distinct_semantic_colours")
	if minimum_groups==1 and int(layout.colouredGroups)==1:
		_check(colours[0]!=ruby.ink,name+":single_word_palette_applied")
	ruby.free()

func _collect(value: Variant, path: String, collected: Array, limit: int) -> void:
	if collected.size()>=limit: return
	if value is Dictionary:
		if value.has("jp") and Readings.contains_kanji(str(value.jp)) and (value.has("reading") or value.has("parts")):
			collected.append({"path":path,"word":value})
		for key in value:
			_collect(value[key],path+"/"+str(key),collected,limit)
	elif value is Array:
		for index in range(value.size()): _collect(value[index],path+"/%d"%index,collected,limit)

func _run() -> void:
	for sample in [{"name":"home_heading","jp":"言葉の戦場"},{"name":"catalog_heading","jp":"戦記　出陣之書"},{"name":"catalog_tab","jp":"初陣"},{"name":"sortie_button","jp":"出陣"},{"name":"barracks_heading","jp":"兵舎"},{"name":"training_heading","jp":"鍛錬"},{"name":"volume_heading","jp":"音量 · 音声\n음량 · 음성"},{"name":"resume_button","jp":"続行"}]:
		_word(sample.name,{"jp":sample.jp},false)
	_word("pause_semantic_groups",{"jp":"作戦会議","reading":"さくせんかいぎ"},false,2)
	_word("paper_geographic_groups",{"jp":"尾張国・丸根砦","reading":"おわりのくに・まるねとりで","ko":"오와리국 · 마루네 요새"},true,2)
	_word("paper_single_group",{"jp":"出陣","reading":"しゅつじん"},true)
	for source in ["units.json","hero_catalog.json","learning_plans.json","curriculum.json"]:
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://native/"+source))
		var samples: Array=[]
		_collect(data,source,samples,12)
		_check(not samples.is_empty(),source+":actual_authored_samples_found")
		for item in samples: _word(item.path,item.word,false)
	var unknown: Array=Readings.for_word({"jp":"未知複合語"})
	_check(not Readings.uncovered_kanji(unknown).is_empty(),"unknown_compound_not_guessed",unknown)
	for button_mode in [false,true]:
		var control: Control=UI.TooltipButton.new() if button_mode else UI.TooltipLabel.new()
		control.theme=Fonts.theme()
		control.text="作戦会議" if button_mode else "出陣"
		control.size=Vector2(440,140)
		root.add_child(control)
		control.call("refresh_ruby")
		var child: Control=control.get_node_or_null("VisibleAnnotatedText")
		_check(child!=null,"shared_control_child_%s"%str(button_mode))
		if child!=null: _check(int(child.get_text_layout().colouredGroups)>=1,"shared_control_colours_%s"%str(button_mode))
		control.free()
	var disabled: Array=[]
	var draw_bypasses: Array=[]
	var pattern: RegEx=RegEx.new()
	pattern.compile("colour_reading_groups\\s*=\\s*false")
	for file_name in DirAccess.get_files_at("res://native"):
		if not file_name.ends_with(".gd"): continue
		var source_text: String=FileAccess.get_file_as_string("res://native/"+file_name)
		for match in pattern.search_all(source_text): disabled.append({"file":file_name,"line":source_text.left(match.get_start()).count("\n")+1})
		if file_name in ["combat_feedback.gd","game.gd"]:
			var source_lines: PackedStringArray=source_text.split("\n")
			for line_index in range(source_lines.size()):
				var line: String=source_lines[line_index]
				if "draw_string(" in line and "run.text" in line and not "run.color" in line:
					draw_bypasses.append({"file":file_name,"line":line_index+1,"source":line.strip_edges()})
	_check(disabled.is_empty(),"configured_colour_exceptions",disabled)
	print("PATCH08_READINGS_QA "+JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"drawColourBypassCandidates":draw_bypasses,"sourceWrites":false}))
	quit(0 if failures.is_empty() else 1)
