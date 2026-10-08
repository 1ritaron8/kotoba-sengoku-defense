extends SceneTree
const Atlas=preload("res://native/campaign_atlas.gd")
const Store=preload("res://native/progress.gd")
const Gate=preload("res://native/learning_gate.gd")
var failures: Array=[]
var checks: int=0
var samples: Array=[]
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message); push_error(message)
func settle() -> void:
	for frame in range(4): await process_frame
func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var safe_root: String=ProjectSettings.globalize_path("res://tests/profiles/atlas-cities/").replace("\\","/").to_lower()
	if not profile.begins_with(safe_root): quit(2); return
	var account=Store.new()
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var story: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
	var geography: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_geography.json"))
	var atlas=Atlas.new()
	atlas.configure(account,maps,story,geography,null)
	root.add_child(atlas)
	await settle()
	check(atlas.revealed_ids.size()==2,"new account reveals first and immediate next battle")
	check(atlas.pin_buttons.size()==10,"all ten tier battles can be previewed")
	check(atlas.available_chapters==[0,1,2,3],"all four tiers can be selected")
	check(not atlas.action_button.disabled,"first stage sortie stays enabled")
	atlas._select_stage(str(maps[1].id))
	await settle()
	check(atlas.action_button.disabled,"next stage stays locked")
	atlas._change_chapter(3)
	await settle()
	check(atlas.chapter_index==3 and atlas.selected_stage_id==str(maps[30].id),"locked advanced tier opens first battle information")
	check(atlas.action_button.disabled,"advanced preview does not grant sortie")
	for entry in maps:
		var lesson: Dictionary=account.stage_lessons[entry.id]
		var count: int=lesson.newWords.size()+lesson.get("grammarSteps",[]).size()
		account.data.maps[entry.id]={"wins":1}
		if not account.data.learning.has("assessments"): account.data.learning.assessments={}
		account.data.learning.assessments[entry.id]={"passed":true,"complete":true,"correctCount":count,"count":count,"scopeHash":Gate.scope_hash(lesson)}
	var before: String=JSON.stringify(account.data)
	for dimensions in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dimensions
		root.content_scale_size=dimensions
		for zoom in [false,true]:
			atlas.all_japan=zoom
			for chapter in range(4):
				atlas.show_stage(str(maps[chapter*10].id))
				await settle()
				var diag: Dictionary=atlas.diagnostics()
				var scope: String=str(dimensions)+" japan="+str(zoom)+" chapter="+str(chapter)
				check(diag.visibleStageIds.size()==10,scope+" all chapter labels visible")
				check(atlas.selected_place_rect==Rect2(),scope+" no large map overlay")
				check(diag.cityLabels.size()==(7 if zoom else 5),scope+" major city count")
				check(diag.cityBattleLinks.size()==10,scope+" city links cover all known battles")
				for link in diag.cityBattleLinks:
					var endpoint: Vector2=Vector2(clampf(link.cityAnchor.x,link.labelRect.position.x,link.labelRect.end.x),clampf(link.cityAnchor.y,link.labelRect.position.y,link.labelRect.end.y))
					check(link.cityAnchor.distance_to(endpoint)>=109.9,scope+" city leaders visibly extend at least 110 pixels")
				for city in diag.cityLabels:
					var japanese: Label=atlas.get_node("AtlasCity_"+city.jp)
					var korean: Label=atlas.get_node("AtlasCityKo_"+city.jp)
					check(korean.text=="("+str(city.ko)+")" and korean.position.y>=japanese.position.y+japanese.size.y,scope+" Korean city name appears below kanji in parentheses")
					check(korean.get_theme_font_size("font_size")>=20 and korean.get_minimum_size().x<=korean.size.x+.1,scope+" Korean city name remains readable and fits")
					check(city.anchor.is_equal_approx(atlas.project(Vector2(city.lon,city.lat))),scope+" city projection "+city.jp)
					check(diag.mapArea.encloses(city.rect),scope+" city label fits")
				for index in range(diag.pinGroups.size()):
					var group: Dictionary=diag.pinGroups[index]
					check(diag.mapArea.encloses(group.rect),scope+" battle label fits")
					for next in range(index+1,diag.pinGroups.size()): check(not group.rect.intersects(diag.pinGroups[next].rect),scope+" battle labels do not overlap")
					for city in diag.cityLabels: check(not group.rect.intersects(city.rect),scope+" cities and battles do not overlap")
					var id: String=group.stageIds[0]
					check(group.anchor.is_equal_approx(atlas.project(atlas.coordinates(atlas.geography_by_id[id]))),scope+" exact battle anchor retained")
				for button in atlas.pin_buttons:
					check(button.get_theme_stylebox("normal") is StyleBoxEmpty,scope+" battle label has no paper background")
					check(button.text.contains(atlas._atlas_label(str(button.get_meta("stage_ids")[0]),"battleKo")),scope+" visible battle name")
					check(button.get_minimum_size().x<=button.size.x+1,scope+" battle title width")
				samples.append({"scope":scope,"pins":diag.pinGroups.size(),"cities":diag.cityLabels.size(),"cache":diag.coastProjectionCacheCount})
	check(before==JSON.stringify(account.data),"atlas changes never mutate progression")
	var cache_before: int=atlas.coast_projection_cache.size()
	atlas._select_stage(str(maps[31].id))
	await settle()
	check(atlas.coast_projection_cache.size()==cache_before,"stage selection reuses coastline projection")
	var file=FileAccess.open("user://qa_atlas_cities.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples},"  "))
	print("ATLAS_CITIES checks=%d failures=%d report=%s"%[checks,failures.size(),ProjectSettings.globalize_path("user://qa_atlas_cities.json")])
	quit(0 if failures.is_empty() else 1)
