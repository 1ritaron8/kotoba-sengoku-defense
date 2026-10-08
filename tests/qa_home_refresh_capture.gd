extends SceneTree
const Front=preload("res://native/front_end.gd")
const Store=preload("res://native/progress.gd")
const Fonts=preload("res://native/game_fonts.gd")
var checks: int=0
var failures: Array=[]
var observations: Array=[]
var captures: Array=[]
var viewport: SubViewport
var menu: Control
func _initialize() -> void:
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_position(Vector2i(-16000,-16000))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message); push_error("HOME_REFRESH "+message)
func settle() -> void:
	for frame in range(8): await process_frame
func geometry(scope: String) -> void:
	var screen: Rect2=Rect2(Vector2.ZERO,viewport.size)
	for control in menu.find_children("*","Control",true,false):
		if not control.is_visible_in_tree(): continue
		if not (control is Label or control is Button or control.has_method("get_text_layout")): continue
		check(screen.grow(1).encloses(control.get_global_rect()),scope+" text fits viewport: "+control.name)
		if control is Label:
			check(control.get_minimum_size().y<=control.size.y+1,scope+" label height fits: "+control.name)
		if control.has_method("get_text_layout"):
			var layout: Dictionary=control.get_text_layout()
			var previous: Dictionary={}
			var owner: Control=control.get_parent()
			for run in layout.runs:
				check(Rect2(Vector2.ZERO,control.size).grow(.1).encloses(run.bounds),scope+" ruby fits: "+str(run.text))
				check(owner.get_global_rect().grow(.1).encloses(Rect2(control.global_position+run.bounds.position,run.bounds.size)),scope+" painted ruby glyphs fit action button: "+str(run.text)+" owner="+str(owner.get_global_rect())+" ruby="+str(control.get_global_rect()))
				if run.role=="body":
					if not previous.is_empty() and is_equal_approx(run.bounds.position.y,previous.bounds.position.y): check(absf(run.bounds.position.x-previous.bounds.end.x)<.1,scope+" normal Japanese glyph spacing")
					previous=run
	var panel: Control=menu.get_node("HomeMenuSurface")
	for name_hint in ["HomeSortie","HomeBarracks","HomeTraining","HomeDictionary"]:
		check(panel.get_global_rect().grow(.1).encloses(menu.get_node(name_hint).get_global_rect()),scope+" right menu action fits its panel")
	var jp: Label=menu.get_node("HomeMotifJP")
	var ko: Label=menu.get_node("HomeMotifKO")
	var jp_width: float=jp.get_theme_font("font").get_string_size(jp.text,HORIZONTAL_ALIGNMENT_LEFT,-1,jp.get_theme_font_size("font_size")).x
	var ko_width: float=ko.get_theme_font("font").get_string_size(ko.text,HORIZONTAL_ALIGNMENT_LEFT,-1,ko.get_theme_font_size("font_size")).x
	check(absf(jp_width-ko_width)/maxf(jp_width,ko_width)<.08,scope+" Japanese and Korean motif widths match within 8 percent")
	check(jp.get_global_rect().end.y+8<=ko.get_global_rect().position.y,scope+" motif rows have normal separate spacing")
	var preparation: Label=menu.get_node("HomeCatalogPreparation")
	check(preparation.get_minimum_size().y<=preparation.size.y+.1,scope+" 40 stage preparation message fits")
	check(preparation.get_global_rect().end.y+1<=menu.get_node("HomeProgressFooter").get_global_rect().position.y,scope+" preparation status clears footer")
	observations.append({"scope":scope,"motifJPWidth":jp_width,"motifKOWidth":ko_width,"preparationText":preparation.text})
func shot(scope: String) -> void:
	await RenderingServer.frame_post_draw
	var image=viewport.get_texture().get_image()
	var path: String="user://home-refresh-"+scope+".png"
	check(image!=null and image.get_size()==viewport.size,"Actual framebuffer dimensions")
	check(image.save_png(path)==OK,"Capture saved")
	captures.append(ProjectSettings.globalize_path(path))
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var safe_root: String=ProjectSettings.globalize_path("res://tests/profiles/home-refresh-capture/").replace("\\","/").to_lower()
	if not profile.begins_with(safe_root): quit(2); return
	root.size=Vector2i(32,32)
	viewport=SubViewport.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.size=Vector2i(1280,800)
	root.add_child(viewport)
	var account=Store.new()
	account.save_path="user://home-refresh-no-save.json"
	var before: String=JSON.stringify(account.data)
	menu=Front.new()
	menu.progress=account
	menu.maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	menu.font=Fonts.body()
	menu.campaign_story=JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
	menu.learning_plans=JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	menu.battle_active=true
	viewport.add_child(menu)
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		viewport.size=dimensions
		menu.show_home()
		menu.set_catalog_preparation(0,40)
		await settle()
		geometry(str(dimensions)+" preparing")
		for name_hint in ["HomeSortie","HomeDictionary","HomeCampaignMap"]: check(menu.get_node(name_hint).disabled,"Catalog action disabled before preparation completes")
		menu.show_catalog()
		check(menu.view=="home","Catalog entry waits while preparing")
		menu.show_campaign_map()
		check(menu.view=="home","Atlas entry waits while preparing")
		await shot(str(dimensions.x)+"-preparing")
		menu.set_catalog_preparation(39,40)
		await settle()
		check(menu.get_node("HomeSortie").disabled,"39 of 40 stages still waits")
		menu.set_catalog_preparation(40,40)
		await settle()
		geometry(str(dimensions)+" ready")
		for name_hint in ["HomeSortie","HomeDictionary","HomeCampaignMap"]: check(not menu.get_node(name_hint).disabled,"Catalog action enabled after preparation completes")
		check(menu.get_node("HomeCatalogPreparation").text.is_empty(),"Preparation status clears when ready")
		await shot(str(dimensions.x)+"-ready")
	check(JSON.stringify(account.data)==before,"Home presentation preserves progression")
	check(not FileAccess.file_exists(account.save_path),"No fixture or user progress saved")
	var file=FileAccess.open("user://qa_home_refresh.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"captures":captures,"scope":"Actual production FrontEnd rendered into offscreen SubViewport. Preparation UI transitions are injected; main's actual 40-stage prewarm is tested separately."},"  "))
	print("HOME_REFRESH checks=%d failures=%d report=%s"%[checks,failures.size(),ProjectSettings.globalize_path("user://qa_home_refresh.json")])
	quit(0 if failures.is_empty() else 1)
