extends SceneTree
## Isolated front-end callbacks and measured text geometry; no GPU or player save.
const Front = preload("res://native/front_end.gd")
const Store = preload("res://native/progress.gd")
const Style = preload("res://native/sengoku_ui.gd")
var checks: int = 0
var failures: Array[String] = []
var warnings: Array[String] = []
var events: Dictionary = {}
var samples: Array = []
var menu: Control
var store: RefCounted

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		if failures.size()<30: push_error("TEXTURED_FRONT "+note)

func settle() -> void:
	for frame in range(5): await process_frame

func named(id: String) -> Node:
	return menu.get_node_or_null(id)

func press(button: Button) -> void:
	check(button!=null and not button.disabled,"Actual requested menu action is available")
	if button!=null and not button.disabled:
		button.pressed.emit()
		await settle()

func record_event(id: String) -> void:
	events[id] = int(events.get(id,0))+1

func geometry(scope: String) -> void:
	var window: Rect2 = root.get_visible_rect()
	for control in menu.find_children("*","Control",true,false):
		if not control.is_visible_in_tree(): continue
		var visible_rect: Rect2 = control.get_global_rect()
		var owner: Node = control.get_parent()
		while owner!=null and owner!=menu:
			if owner is Control and owner.clip_contents:
				visible_rect = visible_rect.intersection(owner.get_global_rect())
			owner = owner.get_parent()
		if not visible_rect.has_area(): continue
		check(window.grow(2).encloses(visible_rect),scope+": control inside viewport: "+control.name)
		if control is Label:
			var point_size: int = control.get_theme_font_size("font_size")
			check(point_size>=20,scope+": label remains >=20px")
			var face: Font = control.get_theme_font("font")
			if control.autowrap_mode==TextServer.AUTOWRAP_OFF:
				for line in control.text.split("\n"):
					check(face.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x<=control.size.x+1,scope+": label width: "+line.left(35))
			check(control.get_minimum_size().y<=control.size.y+1,scope+": label height: "+control.text.left(35))
		if control is Button:
			check(control.get_theme_font_size("font_size")>=20,scope+": button remains >=20px")
			check(control.get_minimum_size().y<=control.size.y+1,scope+": button text fits height: "+control.text.left(35))
			var surface: StyleBox = control.get_theme_stylebox("normal")
			check(surface is StyleBoxTexture if Style.material_texture("lacquer")!=null else surface is StyleBoxFlat,scope+": native button style draws grain before text")
		if control.has_method("get_text_layout"):
			var layout: Dictionary = control.get_text_layout()
			check(float(layout.ruby_size)>=16,scope+": furigana is readable")
			for run in layout.runs:
				check(Rect2(Vector2.ZERO,control.size).grow(2).encloses(run.bounds),scope+": ruby "+str(run.role)+" run fits")
	samples.append({"view":menu.view,"study":menu.study_mode,"size":root.size,"tier":menu.selected_tier,"stage":menu.selected_stage})

func run() -> void:
	var profile: String = OS.get_environment("APPDATA").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/textured-front-end/"):
		push_error("Refusing non-isolated menu test profile")
		quit(2)
		return
	store = Store.new()
	store.save_path = "user://textured-front-end-progress.json"
	var original_data: String = JSON.stringify(store.data)
	menu = Front.new()
	menu.progress = store
	menu.font = load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	menu.maps.assign(JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json")))
	menu.learning_plans = JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	menu.campaign_story = JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
	menu.stage_chosen.connect(func(tier,index,study): events.stage=[tier,index,study])
	menu.barracks_requested.connect(func(): record_event("barracks"))
	menu.training_requested.connect(func(): record_event("training"))
	menu.exit_requested.connect(func(): record_event("exit"))
	menu.resume_requested.connect(func(): record_event("resume"))
	menu.music_toggled.connect(func(): record_event("music"))
	menu.voice_toggled.connect(func(): record_event("voice"))
	menu.battle_minutes_selected.connect(func(value): events.minutes=value)
	root.add_child(menu)
	for surface in ["lacquer","paper"]:
		if Style.material_texture(surface)==null:
			warnings.append(surface+" bitmap not available: flat fallback is under test")
	for dimensions in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		menu.selected_tier = 0
		menu.selected_stage = 0
		menu.show_home()
		await settle()
		geometry("home "+str(dimensions))
		await press(named("HomeBarracks"))
		await press(named("HomeTraining"))
		await press(named("HomeSortie"))
		check(menu.view=="catalog" and not menu.study_mode,"Home sortie opens actual stage catalog")
		await press(named("CatalogSortie"))
		check(events.get("stage",[])==[0,0,false],"Catalog sortie emits first real stage")
		for study in [false,true]:
			for tier in range(4):
				for stage in range(10):
					menu.selected_stage = stage
					menu.show_catalog(tier,study)
					await settle()
					geometry("catalog %s/%d/%d/%s"%[str(dimensions),tier,stage,study])
					var chosen: Button = named("CatalogSortie")
					check(chosen.disabled==not store.map_unlocked(str(menu.maps[tier*10+stage].id)),"Actual unlock action remains correct")
		menu.show_home()
		await settle()
		await press(named("HomeDictionary"))
		check(menu.view=="catalog" and menu.study_mode,"Dictionary opens its study catalog")
		menu.view = "settings"
		menu._rebuild()
		await settle()
		geometry("settings "+str(dimensions))
		for prefix in ["배경 음악","일본어 음성"]:
			for button in menu.find_children("*","Button",true,false):
				if button.text.begins_with(prefix):
					await press(button)
					break
	check(int(events.get("barracks",0))==2 and int(events.get("training",0))==2,"Both home callbacks survive at both sizes")
	check(int(events.get("music",0))==2 and int(events.get("voice",0))==2,"Both settings callbacks survive at both sizes")
	check(JSON.stringify(store.data)==original_data,"Read-only presentation test preserves progression data")
	menu.free()
	await process_frame
	var report: Dictionary = {"checks":checks,"failures":failures,"warnings":warnings,"events":events,"samples":samples,
		"scope":"CPU front-end geometry, font/furigana bounds and actual callbacks; no GPU visual claim and no player save"}
	var output: FileAccess = FileAccess.open("user://qa_textured_front_end.json",FileAccess.WRITE)
	if output==null:
		push_error("Cannot write isolated QA report")
		quit(2)
		return
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("TEXTURED_FRONT checks=%d failures=%d warnings=%d report=%s"%[checks,failures.size(),warnings.size(),ProjectSettings.globalize_path("user://qa_textured_front_end.json")])
	quit(0 if failures.is_empty() else 1)
