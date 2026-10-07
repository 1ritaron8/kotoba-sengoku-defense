extends SceneTree
## Headless projection, static UI, real Progress gates and FrontEnd callbacks.
## Synthetic coordinates test clustering only; researched locations are separate.
const Atlas=preload("res://native/campaign_atlas.gd")
const Front=preload("res://native/front_end.gd")
const Store=preload("res://native/progress.gd")
const Gate=preload("res://native/learning_gate.gd")
var checks: int=0
var failures: Array[String]=[]
var samples: Array=[]
var events: Dictionary={}
var menu: Control
var account: RefCounted
var atlas: Control
var maps: Array=[]
var story: Dictionary={}
var geography: Dictionary={}
var font: Font

func _initialize() -> void:
	Engine.max_fps=120
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		if failures.size()<35: push_error("ATLAS "+note)

func settle() -> void:
	for frame in range(5): await process_frame

func fixture_geography() -> Dictionary:
	var entries: Array=[]
	for index in range(maps.size()):
		var lon: float=130.8+float(index%8)*1.3
		var lat: float=32.0+float(index/8)*1.0
		if index<3: lon=136.95; lat=35.06
		entries.append({"stageId":maps[index].id,"stageNumber":index+1,"lat":lat,"lon":lon,"oldNameJP":"尾張国・丸根砦","oldNameReading":"おわりのくに・まるねとりで","oldNameKo":"시험용 오와리국 · 마루네 요새","modernNameJP":"愛知県名古屋市緑区・丸根砦跡","modernNameReading":"あいちけん なごやし みどりく・まるねとりであと","modernNameKo":"시험용 나고야시 미도리구 · 마루네 요새터","sources":[],"season":{"labelKo":"계절 미확인"},"weather":{"labelKo":"기상 기록 미확인"},"terrain":{"labelKo":"시험용 좌표"}})
	entries[4]["phaseLocation"]={"lon":135.6,"lat":34.5,"reasonKo":"실제 국면 좌표 우선 동작의 합성 시험"}
	return {"status":"synthetic_fixture_only","stages":entries,"dataCredits":[]}

func geometry(scope: String) -> void:
	var screen: Rect2=root.get_visible_rect()
	for control in atlas.find_children("*","Control",true,false):
		if not control.is_visible_in_tree(): continue
		var shown: Rect2=control.get_global_rect()
		var owner: Node=control.get_parent()
		while owner!=null and owner!=atlas:
			if owner is Control and owner.clip_contents: shown=shown.intersection(owner.get_global_rect())
			owner=owner.get_parent()
		if not shown.has_area(): continue
		check(screen.grow(2).encloses(shown),scope+": visible control fits viewport: "+control.name+" "+str(shown)+(": "+control.text.left(70) if control is Label else ""))
		if control is Label:
			check(control.get_theme_font_size("font_size")>=20,scope+": label font >=20")
			check(control.get_minimum_size().y<=control.size.y+1,scope+": label height: "+control.text.left(36))
		if control is Button:
			check(control.get_theme_font_size("font_size")>=20,scope+": button font >=20")
			check(control.get_minimum_size().y<=control.size.y+1,scope+": button height: "+control.text.left(36))
			check(control.size.y>=44,scope+": interactive button >=44 high")
			check(control.get_minimum_size().x<=control.size.x+1,scope+": button width: "+control.text.left(36))
		if control.has_method("get_text_layout"):
			var layout: Dictionary=control.get_text_layout()
			check(float(layout.ruby_size)>=16,scope+": furigana >=16")
			for run in layout.runs: check(Rect2(Vector2.ZERO,control.size).grow(2).encloses(run.bounds),scope+": ruby "+str(run.role)+" fits")
	var diagnostic: Dictionary=atlas.diagnostics()
	check(diagnostic.static and not diagnostic.processing and not diagnostic.fade,scope+": map is static without fade or processing")
	check(not diagnostic.historicalTerritoryMap,scope+": campaign progress is not territorial ownership")
	check(Rect2(Vector2.ZERO,Vector2(5400,2700)).encloses(diagnostic.sourceCrop),scope+": equirectangular source crop fits original")
	var groups: Array=diagnostic.pinGroups
	var ids: Dictionary={}
	for a in range(groups.size()):
		check(diagnostic.photoRect.grow(44).encloses(groups[a].rect),scope+": pin is adjacent to actual map anchor")
		for b in range(a+1,groups.size()): check(not groups[a].rect.intersects(groups[b].rect),scope+": pin labels do not overlap")
		for id in groups[a].stageIds:
			check(not ids.has(id),scope+": stage belongs to one pin group")
			ids[id]=true
			var geo: Dictionary=atlas.geography_by_id[id]
			var actual: Vector2=atlas.coordinates(geo)
			var anchor: Dictionary=diagnostic.anchors[id]
			check(Vector2(anchor.lon,anchor.lat).is_equal_approx(actual),scope+": source coordinates preserved")
			check(anchor.display.is_equal_approx(atlas.project(actual)),scope+": displayed dot uses actual projection")
	check(ids.size()==diagnostic.anchors.size(),scope+": all anchors belong to one clickable group")
	samples.append({"scope":scope,"viewport":root.size,"selectedStage":diagnostic.selectedStageId,"geoCount":diagnostic.geographyCount,"pinCount":groups.size(),"crop":diagnostic.sourceCrop,"photoRect":diagnostic.photoRect})

func press(button: Button) -> void:
	check(button!=null and not button.disabled,"requested actual UI button is available")
	if button!=null and not button.disabled:
		button.pressed.emit()
		await settle()

func named(id: String) -> Button:
	return atlas.find_child(id,true,false) as Button

func install_atlas(data: Dictionary) -> void:
	if is_instance_valid(atlas): atlas.free()
	atlas=Atlas.new()
	atlas.configure(account,maps,story,data,font)
	atlas.show_stage(str(maps[0].id),true)
	root.add_child(atlas)
	await settle()

func unlock_fixture() -> void:
	# Populate isolated in-memory valid receipts only; never call write_save.
	for entry in maps:
		var lesson: Dictionary=account.stage_lessons[entry.id]
		var required: int=lesson.newWords.size()+lesson.get("grammarSteps",[]).size()
		account.data.maps[entry.id]={"wins":1}
		if not account.data.learning.has("assessments"): account.data.learning.assessments={}
		account.data.learning.assessments[entry.id]={"passed":true,"complete":true,"correctCount":required,"count":required,"scopeHash":Gate.scope_hash(lesson)}

func frontend_checks() -> void:
	if is_instance_valid(atlas): atlas.free()
	menu=Front.new()
	menu.maps=maps
	menu.font=font
	menu.progress=account
	menu.campaign_story=story
	menu.learning_plans=JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	menu.stage_chosen.connect(func(tier,index,study): events.stage=[tier,index,study])
	menu.assessment_requested.connect(func(tier,index): events.assessment=[tier,index])
	menu.resume_requested.connect(func(): events.resume=int(events.get("resume",0))+1)
	root.add_child(menu)
	var unchanged: String=JSON.stringify(account.data)
	for dimensions in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dimensions
		root.content_scale_size=dimensions
		menu.show_home()
		await settle()
		var entry: Button=menu.get_node_or_null("HomeCampaignMap")
		check(entry!=null,"home has nationwide atlas entry")
		check(root.get_visible_rect().encloses(entry.get_global_rect()),"home map entry fits "+str(dimensions))
		await press(entry)
		check(menu.view=="atlas" and menu.modulate.a==1,"home atlas opens immediately without fade")
		atlas=menu.get_node_or_null("CampaignAtlas")
		geometry("frontend atlas "+str(dimensions))
		await press(named("AtlasSortie"))
		check(events.get("stage",[])==[0,0,false],"actual first atlas sortie maps to tier/index callback")
		var count_before: Array=events.get("stage",[]).duplicate()
		atlas.stage_requested.emit("missing-id")
		atlas.stage_requested.emit(str(maps[1].id))
		check(events.get("stage",[])==count_before,"invalid and locked direct requests cannot bypass unlock")
		await press(named("AtlasCatalog"))
		check(menu.view=="catalog" and not menu.study_mode,"atlas returns to real battle catalog")
		var catalog_entry: Button=menu.get_node_or_null("CatalogCampaignMap")
		check(catalog_entry!=null,"catalog has nationwide atlas entry")
		check(root.get_visible_rect().encloses(catalog_entry.get_global_rect()),"catalog map entry fits "+str(dimensions))
		menu.selected_tier=2
		menu.selected_stage=4
		menu.show_catalog(2,false)
		await settle()
		await press(menu.get_node("CatalogCampaignMap"))
		atlas=menu.get_node("CampaignAtlas")
		check(atlas.selected_stage_id==str(maps[24].id),"catalog selected stage propagates exact ID")
		check(atlas.action_button.disabled,"locked catalog selected stage has no sortie")
		await press(named("AtlasHome"))
		check(menu.view=="home","atlas returns to existing home")
		menu.battle_active=true
		menu.show_campaign_map(str(maps[0].id))
		await settle()
		atlas=menu.get_node("CampaignAtlas")
		await press(named("AtlasResume"))
		check(int(events.get("resume",0))>0,"active battle resumes through existing callback")
	check(JSON.stringify(account.data)==unchanged,"all real navigation and requests preserve player progression")
	# A cleared first stage without its assessment exposes the existing exam.
	account.data.maps[str(maps[0].id)]={"wins":1}
	menu.show_campaign_map(str(maps[1].id))
	await settle()
	atlas=menu.get_node("CampaignAtlas")
	check(atlas.gate_button.visible and atlas.gate_button.text=="이전 전투 해금 시험","locked next stage exposes previous stage's real assessment")
	var exam_state: String=JSON.stringify(account.data)
	await press(named("AtlasAssessment"))
	check(events.get("assessment",[])==[0,0],"atlas assessment callback maps previous actual stage")
	check(JSON.stringify(account.data)==exam_state,"assessment entry does not write or grant unlock")
	unlock_fixture()
	var fully_unlocked: String=JSON.stringify(account.data)
	for index in range(maps.size()):
		menu.show_campaign_map(str(maps[index].id))
		await settle()
		atlas=menu.get_node("CampaignAtlas")
		await press(named("AtlasSortie"))
		check(events.get("stage",[])==[int(index/10),index%10,false],"each unlocked actual stage maps to its exact tier/index")
	check(JSON.stringify(account.data)==fully_unlocked,"all 40 real sortie callbacks preserve valid in-memory progression")
	menu.free()
	atlas=null
	await process_frame

func run() -> void:
	var profile: String=OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/campaign-atlas/").to_lower()):
		push_error("Refusing non-isolated campaign atlas profile")
		quit(2)
		return
	account=Store.new()
	account.save_path="user://atlas-test-never-written.json"
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	story=JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
	font=load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	var path: String="res://native/campaign_geography.json"
	if FileAccess.file_exists(path): geography=JSON.parse_string(FileAccess.get_file_as_string(path))
	var before_data: String=JSON.stringify(account.data)
	var image_before: String=FileAccess.get_sha256("res://assets/atlas/world-july-2004.jpg")
	var image_manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/atlas/manifest.json"))
	check(image_before==str(image_manifest.sha256),"NASA original raster matches downloaded provenance hash")
	check(image_manifest.get("pixelSize",[]).size()==2 and int(image_manifest.pixelSize[0])==5400 and int(image_manifest.pixelSize[1])==2700,"source provenance fixes the original equirectangular dimensions")
	var synthetic: Dictionary=fixture_geography()
	await install_atlas(synthetic)
	check(atlas.source_point(Vector2(121,46)).is_equal_approx(Vector2(4515,660)),"NASA northwest source pixel is exact")
	check(atlas.source_point(Vector2(149,24)).is_equal_approx(Vector2(4935,990)),"NASA southeast source pixel is exact")
	check(not atlas.valid_coordinates({"lat":NAN,"lon":135}),"NaN coordinate rejected")
	check(not atlas.valid_coordinates({"lat":35,"lon":INF}),"infinite coordinate rejected")
	check(not atlas.valid_coordinates({"lat":91,"lon":135}),"out-of-range latitude rejected")
	check(not atlas.valid_coordinates({"lat":"35","lon":135}),"non-numeric coordinate rejected")
	check(atlas.coordinates(synthetic.stages[4]).is_equal_approx(Vector2(135.6,34.5)),"documented separate phase location takes precedence")
	check(atlas.coordinates({"lon":135.0,"lat":35.0,"phaseLocation":{"lon":INF,"lat":35.5}}).is_equal_approx(Vector2(135,35)),"invalid optional phase coordinate falls back to canonical location")
	for dimensions in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dimensions
		root.content_scale_size=dimensions
		atlas.show_stage(str(maps[0].id),true)
		await settle()
		geometry("fixture campaign "+str(dimensions))
		var grouped: Array=[]
		for group in atlas.pin_groups:
			if str(maps[0].id) in group: grouped=group; break
		check(grouped.size()>=3,"same-location labels form one group")
		atlas._select_region(grouped)
		await settle()
		geometry("fixture grouped "+str(dimensions))
		check(atlas.region_ids==grouped,"cluster opens exact stage list")
		check(atlas.stage_scroll.find_children("AtlasStage_*","Button",true,false).size()==grouped.size(),"cluster list preserves every overlapping battle")
		await press(named("JapanZoom"))
		check(atlas.bounds==Atlas.JAPAN,"full Japan zoom uses specified coordinate bounds")
		check(atlas.crop_rect.is_equal_approx(Rect2(4515,660,420,330)),"full Japan crop is exact original pixels")
		geometry("fixture Japan "+str(dimensions))
		var filter: OptionButton=atlas.get_node("AtlasTierFilter")
		filter.item_selected.emit(4)
		await settle()
		check(atlas.tier_filter==3 and atlas.source_anchors.size()==10,"advanced filter preserves all 10 eligible locations")
		geometry("fixture advanced "+str(dimensions))
		atlas.tier_filter=-1
		atlas.all_japan=false
	if not geography.is_empty():
		await install_atlas(geography)
		if str(geography.get("status",""))=="verified_complete":
			check(geography.stages.size()==40 and int(geography.get("verifiedStageCount",0))==40,"final geography provides all forty verified stage entries")
			var by_number: Dictionary={}
			for entry in geography.stages: by_number[int(entry.stageNumber)]=entry
			for pair in [[7,8],[16,17],[21,23],[26,28],[31,32]]:
				var first: Dictionary=by_number[pair[0]]
				var second: Dictionary=by_number[pair[1]]
				check(Vector2(float(first.lon),float(first.lat)).is_equal_approx(Vector2(float(second.lon),float(second.lat))),"repeat historical event preserves canonical coordinates "+str(pair))
			for number in [17,32]:
				var entry: Dictionary=by_number[number]
				check(entry.get("phaseLocation") is Dictionary and atlas.coordinates(entry).is_equal_approx(Vector2(float(entry.phaseLocation.lon),float(entry.phaseLocation.lat))),"documented actual battle phase uses separate site "+str(number))
			var honnoji: Dictionary=by_number[27]
			check(atlas.coordinates(honnoji).is_equal_approx(Vector2(float(honnoji.lon),float(honnoji.lat))),"Honnoji pin uses the Kyoto event, not the fictional Takamatsu mission")
			check(bool(honnoji.stageMissionLocation.get("isFictionalMission",false)) and atlas.coordinates(honnoji).distance_to(Vector2(float(honnoji.stageMissionLocation.lon),float(honnoji.stageMissionLocation.lat)))>1.0,"Honnoji event and Takamatsu player mission remain explicitly separate")
			atlas.show_stage(str(honnoji.stageId),true)
			await settle()
			var mission_note: String=str(honnoji.stageMissionLocation.get("reasonKo",""))
			var mission_visible: bool=false
			for label in atlas.find_children("*","Label",true,false):
				if label.text==mission_note: mission_visible=true
			check(not mission_note.is_empty() and mission_visible,"Atlas details display the fictional Takamatsu mission boundary explanation")
		check(atlas.geography_by_id.size()==geography.stages.size(),"all researched geographic entries have valid coordinates")
		check(atlas.diagnostics().credits.contains("NASA Earth Observatory"),"NASA image credit available")
		for item in geography.get("dataCredits",[]): check(atlas.diagnostics().credits.contains(str(item.get("credit",""))),"exact geographic dataset attribution preserved")
		for dimensions in [Vector2i(1280,800),Vector2i(1920,1080)]:
			root.size=dimensions
			root.content_scale_size=dimensions
			for geo in geography.stages:
				atlas.show_stage(str(geo.stageId),true)
				await settle()
				geometry("researched %s %s"%[geo.stageId,str(dimensions)])
				check(atlas.selected_stage_id==geo.stageId,"actual researched battle selection preserved")
				check(not atlas.stage(str(geo.stageId)).is_empty(),"researched geographic ID belongs to real stage catalog")
				check(atlas.story_by_id[str(geo.stageId)].battleEventId==geo.battleEventId,"battle coordinates match exact story event")
			await press(named("AtlasCredits"))
			var popup: Control=atlas.get_node_or_null("AtlasSourceCredits")
			check(popup!=null and popup.visible,"actual source attribution dialog opens")
			if popup!=null:
				var label: Label=popup.find_child("CreditText",true,false)
				check(label.get_theme_font_size("font_size")>=20,"source attribution remains readable")
				check(root.get_visible_rect().encloses(popup.find_child("CreditPaper",true,false).get_global_rect()),"attribution dialog fits minimum supported screen")
				check(label.get_minimum_size().y<=label.size.y+1,"full source credit text fits scrolling dialog")
				check(label.text==atlas.diagnostics().credits,"credits dialog preserves exact source text")
				geometry("researched source credits "+str(dimensions))
				popup.find_child("AtlasCreditClose",true,false).pressed.emit()
				await settle()
	else: check(true,"geography pending; only explicit synthetic fixture tested")
	await install_atlas({})
	check(atlas.pin_buttons.is_empty(),"missing geography never fabricates pins")
	check(not atlas.action_button.disabled,"safe first-stage selection remains available without geography")
	geometry("missing geography")
	check(JSON.stringify(account.data)==before_data,"atlas display never mutates progression")
	await frontend_checks()
	check(not FileAccess.file_exists(account.save_path),"no player or fixture progress save was written")
	check(FileAccess.get_sha256("res://assets/atlas/world-july-2004.jpg")==image_before,"original NASA image bytes unchanged")
	var report: Dictionary={"checks":checks,"failures":failures,"samples":samples,"events":events,"actualGeographyCount":geography.get("stages",[]).size(),"actualGeographyStatus":geography.get("status","pending"),"imageSha256":image_before,"scope":"Headless native coordinate projection, same-location clusters, measured fonts/furigana geometry, existing real Progress gates and FrontEnd callbacks. Synthetic coordinates are separate and not historical assertions. No GPU/import or user save."}
	var output: FileAccess=FileAccess.open("user://qa_campaign_atlas.json",FileAccess.WRITE)
	if output==null: push_error("Cannot write isolated atlas report"); quit(2); return
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("CAMPAIGN_ATLAS checks=%d failures=%d researched=%d report=%s"%[checks,failures.size(),geography.get("stages",[]).size(),ProjectSettings.globalize_path("user://qa_campaign_atlas.json")])
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
