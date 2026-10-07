extends SceneTree
## Measure production text with the bundled fonts; no GPU/import or player save.
const Fonts = preload("res://native/game_fonts.gd")
const Front = preload("res://native/front_end.gd")
const Training = preload("res://native/unit_training.gd")
const Atlas = preload("res://native/campaign_atlas.gd")
const Field = preload("res://native/learning_field.gd")
const Store = preload("res://native/progress.gd")
const Gate = preload("res://native/learning_gate.gd")

var checks: int = 0
var failures: Array[String] = []
var observations: Array = []
var maps: Array = []
var story: Dictionary = {}
var plans: Dictionary = {}
var geography: Dictionary = {}
var account: RefCounted
var current_scope: String = ""
var captures: Array = []
var capture: bool = false

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(current_scope+": "+note)
		if failures.size()<=35: push_error("GAME_FONTS "+current_scope+": "+note)

func settle(count: int = 6) -> void:
	for frame in range(count): await process_frame

func all_nodes(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		result.append(child)
		result.append_array(all_nodes(child))
	return result

func strings(value: Variant, characters: Dictionary) -> void:
	if value is String:
		for character in value:
			var code: int = character.unicode_at(0)
			if code>=0x3000 and code<=0xD7FF: characters[code] = character
	elif value is Dictionary:
		for entry in value.values(): strings(entry,characters)
	elif value is Array:
		for entry in value: strings(entry,characters)

func font_checks() -> void:
	current_scope = "bundled period lettering"
	check(Fonts.body()==Fonts.body() and Fonts.heading()==Fonts.heading(),"Faces are shared cached resources")
	check(Fonts.japanese()!=Fonts.heading() and Fonts.reading()!=Fonts.body(),"Japanese brush letters and kana use their dedicated faces")
	check(Fonts.heading()!=Fonts.body(),"Heading and body share a family with distinct weights")
	check(Fonts.heading().get_font_name().contains("Myeongjo"),"Korean heading uses traditional Myeongjo lettering")
	check(Fonts.body().get_font_name().contains("Myeongjo"),"Korean text uses the matching Myeongjo family")
	check(Fonts.japanese().get_font_name().contains("Yuji"),"Japanese text uses the bundled brush face")
	check(Fonts.reading().get_font_name().contains("Klee"),"Kana uses the readable handwritten face")
	check(Fonts.theme().default_font==Fonts.body(),"Shared default UI theme uses the readable body face")
	var characters: Dictionary = {}
	for path in ["curriculum","learning_plans","campaign_story","campaign_geography","units","hero_catalog","maps"]:
		strings(JSON.parse_string(FileAccess.get_file_as_string("res://native/"+path+".json")),characters)
	for code in characters:
		check(Fonts.heading().has_char(int(code)),"Heading can display authored CJK glyph "+str(characters[code]))
		check(Fonts.body().has_char(int(code)),"Body/kana can display authored CJK glyph "+str(characters[code]))
	observations.append({"scope":current_scope,"heading":Fonts.heading().get_font_name(),"body":Fonts.body().get_font_name(),"glyphs":characters.size(),"headingHeight66":Fonts.heading().get_height(66),"bodyHeight20":Fonts.body().get_height(20),"kanaHeight22":Fonts.reading().get_height(22),"headingSha256":FileAccess.get_sha256(Fonts.HEADING_PATH) if FileAccess.file_exists(Fonts.HEADING_PATH) else "packed/imported"})

func geometry(node: Control, scope: String) -> void:
	current_scope = scope
	var screen: Rect2 = root.get_visible_rect()
	var count: int = 0
	for control in all_nodes(node):
		if not control is Control or not control.is_visible_in_tree(): continue
		var shown: Rect2 = control.get_global_rect()
		var parent: Node = control.get_parent()
		while parent!=null and parent!=node:
			if parent is Control and parent.clip_contents: shown = shown.intersection(parent.get_global_rect())
			parent = parent.get_parent()
		if not shown.has_area(): continue
		if control is Label or control is Button or control.has_method("get_text_layout"):
			check(screen.grow(2).encloses(shown),"Visible text/control fits viewport "+str(control.name)+" "+str(shown))
		if control is Label:
			var face: Font = control.get_theme_font("font")
			var points: int = control.get_theme_font_size("font_size")
			check(points>=20,"UI labels remain >=20px: "+control.text.left(30))
			check(control.get_minimum_size().y<=control.size.y+1,"Full wrapped label height: "+control.text.left(80)+" wanted="+str(control.get_minimum_size())+" actual="+str(control.size))
			if control.autowrap_mode==TextServer.AUTOWRAP_OFF:
				for line in control.text.split("\n"):
					check(face.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,points).x<=control.size.x+1,"Unwrapped label width: "+line)
			count += 1
		elif control is Button and not control is OptionButton and not control.text.is_empty():
			var face: Font = control.get_theme_font("font")
			var points: int = control.get_theme_font_size("font_size")
			var style: StyleBox = control.get_theme_stylebox("normal")
			var usable_width: float = control.size.x-style.get_content_margin(SIDE_LEFT)-style.get_content_margin(SIDE_RIGHT)
			check(points>=20,"Button labels remain >=20px")
			check(control.get_minimum_size().y<=control.size.y+1,"Full button text height: "+control.text)
			if control.autowrap_mode==TextServer.AUTOWRAP_OFF:
				check(face.get_string_size(control.text,HORIZONTAL_ALIGNMENT_LEFT,-1,points).x<=usable_width+1,"Button glyphs fit: "+control.text)
			count += 1
		elif control.has_method("get_text_layout"):
			var layout: Dictionary = control.get_text_layout()
			check(control.font==Fonts.japanese(),"Japanese ruby uses the common Mincho face")
			check(control.reading_font==Fonts.reading() and control.meaning_font==Fonts.body(),"Kana and Korean ruby meanings use the common readable face")
			check(layout.ruby_size>=16,"Authored readings stay >=16px")
			for run in layout.runs:
				check(Rect2(Vector2.ZERO,control.size).grow(1).encloses(run.bounds),"Complete ruby "+str(run.role)+" glyphs fit: "+str(run.text)+" run="+str(run.bounds)+" size="+str(control.size))
			count += 1
	observations.append({"scope":scope,"viewport":root.size,"measuredControls":count})

func shot(name_hint: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	var path: String = "user://fonts_"+name_hint+".png"
	root.get_texture().get_image().save_png(path)
	captures.append(ProjectSettings.globalize_path(path))

func frontend_checks() -> void:
	print("GAME_FONTS stage=frontend")
	var menu: Control = Front.new()
	menu.maps = maps
	menu.font = Fonts.body()
	menu.progress = account
	menu.campaign_story = story
	menu.learning_plans = plans
	menu.battle_active = true
	root.add_child(menu)
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		menu.show_home()
		await settle()
		geometry(menu,"home "+str(dimensions))
		check(not menu.get_node("HomeTitle").get_global_rect().intersects(menu.get_node("HomeSubtitle").get_global_rect()),"The Mincho headline has its own height above the Korean subtitle")
		await shot("home_"+str(dimensions.x))
		menu.view = "settings"
		menu._rebuild()
		await settle()
		geometry(menu,"settings "+str(dimensions))
		var volume: Control = menu.get_node("VolumeControls")
		check(volume.sliders.size()==4,"All four independent volume controls are present")
		var emitted: Dictionary = {}
		menu.audio_volume_changed.connect(func(key,value): emitted[key] = value,CONNECT_ONE_SHOT)
		volume.sliders.masterVolume.value = 67
		check(is_equal_approx(float(emitted.get("masterVolume",-1)),.67),"The real settings slider forwards its normalized save value")
		await shot("settings_"+str(dimensions.x))
		for tier in range(4):
			print("GAME_FONTS frontend viewport=%s tier=%d"%[str(dimensions),tier])
			for index in range(10):
				menu.selected_stage = index
				menu.show_catalog(tier,false)
				await settle(3)
				geometry(menu,"catalog %s/%d %s"%[str(tier),index,str(dimensions)])
				if index==9 and tier==3: await shot("catalog_"+str(dimensions.x))
	menu.free()
	await settle()

func atlas_checks() -> void:
	print("GAME_FONTS stage=atlas")
	var atlas: Control = Atlas.new()
	atlas.configure(account,maps,story,geography,Fonts.body())
	root.add_child(atlas)
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		print("GAME_FONTS atlas viewport="+str(dimensions))
		for entry in maps:
			atlas.show_stage(str(entry.id),true)
			await settle(3)
			geometry(atlas,"atlas "+str(entry.id)+" "+str(dimensions))
		await shot("atlas_"+str(dimensions.x))
	atlas.free()
	await settle()

func training_checks() -> void:
	print("GAME_FONTS stage=training")
	var drill: Control = Training.new()
	drill.render_enabled = false
	root.add_child(drill)
	drill.configure(account,maps,Fonts.body())
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		drill.open_menu()
		await settle()
		geometry(drill,"training menu "+str(dimensions))
		await shot("training_menu_"+str(dimensions.x))
		for id in Training.UNIT_ORDER:
			check(drill.open(id,maps[14]),"Real isolated training opens "+id)
			drill.set_process(false)
			await settle()
			geometry(drill,"training "+id+" "+str(dimensions))
			check(drill.battle.gold==drill.battle.recruit_cost(id),"The isolated Lv1 drill funds its actual recruitment cost")
			check(drill.deploy(),"Real placement/production action remains enabled: "+id)
			if not drill.battle.pending.is_empty():
				check(drill.place_at(drill.recommended),"The real recommended placement submits production: "+id)
			check(drill.battle.gold==0 and drill.battle.recruitment_queue.size()==1,"One training order pays its runtime cost exactly once: "+id)
			await settle()
			geometry(drill,"training producing "+id+" "+str(dimensions))
			drill.phase = "success"
			drill._refresh_ui()
			await settle()
			geometry(drill,"training result "+id+" "+str(dimensions))
			if id=="ninja": await shot("training_ninja_"+str(dimensions.x))
	var levels_before: Dictionary = account.data.army.levels.duplicate(true)
	account.data.army.levels.ninja = 8
	check(drill.open("ninja",maps[14]),"An upgraded ninja account still opens the Lv1 basic drill")
	drill.set_process(false)
	check(drill.battle.gold==drill.battle.recruit_cost("ninja"),"An account discount cannot underfund the intentionally Lv1 practice roster")
	check(drill.deploy() and drill.place_at(drill.recommended),"An upgraded account can still pay for its isolated basic ninja placement")
	account.data.army.levels = levels_before
	drill.close()
	drill.free()
	await settle()

func field_checks() -> void:
	print("GAME_FONTS stage=context")
	var field: Control = Field.new()
	field.font = Fonts.body()
	root.add_child(field)
	field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		for stage_id in plans.get("stages",{}):
			for mission in plans.stages[stage_id].get("missions",[]):
				field.begin_choice(mission,false)
				await settle(2)
				geometry(field,"context "+str(mission.id)+" "+str(dimensions))
				for card in field.target_buttons:
					check(card.get_global_rect().grow(1).encloses(card.get_node("DestinationWord").get_global_rect()),"The full kana/Japanese/Korean choice is visible inside its card")
					check(not card.get_global_rect().intersects(field.report_card.get_global_rect()),"Question paper and choice card do not overlap")
					check(not card.get_global_rect().intersects(field.action_card.get_global_rect()),"Choice card leaves all answer/result actions clear")
				check(not field.report_text.word.jp==mission.report.jp,"The source answer stays blank during question/resize")
				field.show_hint()
				await settle(2)
				geometry(field,"context hint "+str(mission.id)+" "+str(dimensions))
				for card in field.target_buttons:
					check(card.get_global_rect().grow(1).encloses(card.get_node("DestinationWord").get_global_rect()),"The full choice remains visible after the longer original is revealed")
				check(field.report_text.word.jp==mission.report.jp,"Hint restores the authored sentence")
				if str(stage_id)==str(maps[-1].id): await shot("context_"+str(dimensions.x))
	field.free()
	await settle()

func run() -> void:
	if not OS.get_environment("APPDATA").replace("\\","/").to_lower().begins_with("c:/jp_df/tests/profiles/fonts/"):
		push_error("Refusing a non-isolated fonts QA profile")
		quit(2)
		return
	capture = "--capture" in OS.get_cmdline_user_args()
	font_checks()
	if not "--fonts-only" in OS.get_cmdline_user_args():
		maps = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
		story = JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
		plans = JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
		geography = JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_geography.json"))
		account = Store.new()
		account.save_path = "user://fonts-account-must-not-be-written.json"
		for entry in maps:
			account.data.maps[entry.id] = {"wins":1}
			var lesson: Dictionary = account.stage_lessons[entry.id]
			var required: int = lesson.newWords.size()+lesson.get("grammarSteps",[]).size()
			if not account.data.learning.has("assessments"): account.data.learning.assessments = {}
			account.data.learning.assessments[entry.id] = {"passed":true,"complete":true,"correctCount":required,"count":required,"scopeHash":Gate.scope_hash(lesson)}
		var before: String = JSON.stringify(account.data)
		var only: String = ""
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--only="): only = argument.trim_prefix("--only=")
		if only.is_empty() or only=="frontend": await frontend_checks()
		if only.is_empty() or only=="atlas": await atlas_checks()
		if only.is_empty() or only=="training": await training_checks()
		if only.is_empty() or only=="context": await field_checks()
		current_scope = "isolation"
		check(JSON.stringify(account.data)==before,"All display/navigation fixtures preserve account, SRS, skill and economy state")
		check(not FileAccess.file_exists(account.save_path),"No player progress or settings save was written")
	var report: Dictionary = {"checks":checks,"failures":failures,"observations":observations,"captures":captures,"scope":"Bundled official font family/glyph coverage and production FrontEnd/Atlas/Training/Context text geometry at 1280x800, 1440x900, 1920x1080; no system font install, no import, no player save."}
	var suffix: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): suffix = "_"+argument.trim_prefix("--only=")
	var path: String = ("user://" if "--packed" in OS.get_cmdline_user_args() else "res://tests/")+"qa_game_fonts"+suffix+".json"
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("GAME_FONTS checks=%d failures=%d observations=%d report=%s"%[checks,failures.size(),observations.size(),ProjectSettings.globalize_path(path)])
	quit(0 if failures.is_empty() else 1)
