extends SceneTree
## Production UI, real fonts and native geometry; capture is opt-in for root GPU QA.
const Front=preload("res://native/front_end.gd")
const Atlas=preload("res://native/campaign_atlas.gd")
const Preview=preload("res://native/battlefield_preview.gd")
const NativeBattlefield=preload("res://native/battlefield_3d.gd")
const Store=preload("res://native/progress.gd")
const Gate=preload("res://native/learning_gate.gd")
const Fonts=preload("res://native/game_fonts.gd")
const REPRESENTATIVE_STAGES: Array[int]=[0,7,16,25,26,36,39]
var checks: int=0
var failures: Array[String]=[]
var observations: Array=[]
var captures: Array=[]
var scope: String=""
var maps: Array=[]
var story: Dictionary={}
var geography: Dictionary={}
var plans: Dictionary={}
var account: RefCounted
var capture: bool=false
var cleanup: Dictionary={}
var basis_observations: Array=[]

func stage_geography(id: String) -> Dictionary:
	for entry in geography.get("stages",[]):
		if str(entry.get("stageId",""))==id: return entry
	return {}

func basis_label_geometry(label: Label) -> void:
	check(label.get_theme_font_size("font_size")>=20,"Map basis body is20px or larger: "+str(label.name))
	check(label.max_lines_visible==-1 and label.visible_characters==-1,"Map basis keeps every authored line and character: "+str(label.name))
	check(label.text_overrun_behavior==TextServer.OVERRUN_NO_TRIMMING,"Map basis does not ellipsize or trim its text: "+str(label.name))
	check(label.get_minimum_size().y<=label.size.y+1,"Map basis label has its full wrapped line height: "+str(label.name))

func catalog_basis(front: Control,index: int,dimensions: Vector2i) -> void:
	var id: String=str(maps[index].id)
	var geo: Dictionary=stage_geography(id)
	var scroll: ScrollContainer=front.get_node("StageTacticalDescriptionScroll")
	var facts: Label=scroll.get_node("StageTacticalDescription")
	check(facts.text.ends_with("\n제작 근거 · "+str(geo.renderingBasisKo)),"Catalog final basis row belongs to the selected stage: "+id)
	basis_label_geometry(facts)
	check(scroll.horizontal_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"Catalog basis wraps within its facts pane")
	scroll.scroll_vertical=1000000
	await settle(3)
	check(facts.get_global_rect().end.y<=scroll.get_global_rect().end.y+2 and facts.get_global_rect().end.y>=scroll.get_global_rect().position.y+20,"Catalog scrolling reaches the full final basis line: "+id)
	var source: LinkButton=front.get_node("MapBasisSources")
	var urls: Array=geo.get("sources",[])
	check(source.text=="맵 제작 참고 자료" and not source.disabled,"Selected catalog offers its reference link: "+id)
	check(source.tooltip_text=="\n".join(PackedStringArray(urls)),"Reference link carries exactly this stage's source URLs: "+id)
	var connections: Array=source.get_signal_connection_list("pressed")
	check(connections.size()==1 and connections[0].callable.is_valid(),"Reference link has one production click callback: "+id)
	check(root.get_visible_rect().grow(1).encloses(source.get_global_rect()),"Reference link fits the viewport: "+id)
	check(source.get_theme_font("font")==Fonts.body() and source.get_theme_font_size("font_size")>=20,"Reference link uses the real readable body font")
	check(source.get_minimum_size().x<=source.size.x and source.get_minimum_size().y<=source.size.y,"Reference link has room for its complete text")
	check(source.get_theme_font("font").get_string_size(source.text,HORIZONTAL_ALIGNMENT_LEFT,-1,source.get_theme_font_size("font_size")).x<=source.size.x-12,"Reference link retains at least12px horizontal text space")
	check(source.get_global_rect().position.y-front.get_node("CatalogSortie").get_global_rect().end.y>=8,"Reference link has clear vertical space below the sortie button")
	check(not source.get_global_rect().intersects(scroll.get_global_rect()),"Reference link does not cover map basis body")
	basis_observations.append({"kind":"catalog","dimensions":dimensions,"stageId":id,"basis":geo.renderingBasisKo,"sourceUrls":urls,"clickTargetByProductionBinding":str(urls[0]),"linkRect":source.get_global_rect(),"factsRect":facts.get_global_rect(),"factsScrollRect":scroll.get_global_rect(),"scrollVertical":scroll.scroll_vertical})

func atlas_basis(atlas: Control,id: String,dimensions: Vector2i) -> void:
	var geo: Dictionary=stage_geography(id)
	var basis: Label=atlas.find_child("AtlasMapBasis",true,false)
	check(basis!=null,"Selected Atlas stage has its own map basis: "+id)
	if basis==null: return
	check(basis.text=="제작 근거 · "+str(geo.renderingBasisKo),"Atlas basis belongs to the selected stage: "+id)
	check(basis.tooltip_text=="\n".join(PackedStringArray(geo.get("sources",[]))),"Atlas basis source tooltip matches its own stage: "+id)
	basis_label_geometry(basis)
	atlas.detail_scroll.ensure_control_visible(basis)
	await settle(3)
	check(atlas.detail_scroll.get_global_rect().grow(2).encloses(basis.get_global_rect()),"Atlas scrolling exposes the complete wrapped basis: "+id)
	basis_observations.append({"kind":"atlas","dimensions":dimensions,"stageId":id,"basis":geo.renderingBasisKo,"basisRect":basis.get_global_rect(),"scrollRect":atlas.detail_scroll.get_global_rect()})

func main_briefing_basis() -> void:
	complete_through(40)
	var app: Node=load("res://native/main.tscn").instantiate()
	var fixture: String="user://historical-map-basis-main-%d.json"%Time.get_ticks_usec()
	app.progress.save_path=fixture
	app.progress.data.settings.music=false
	app.progress.data.settings.effects=false
	app.progress.data.settings.voice=false
	root.add_child(app)
	app.set_process(false)
	app.game.set_process(false)
	app.atmosphere.set_process(false)
	app.troops_3d.set_process(false)
	app.combat_feedback.set_process(false)
	app.japanese_voice=""
	app._stop_narration()
	app.player.stop()
	app.battle_audio.set_enabled(false)
	app._apply_audio_settings()
	app.progress.data.maps=account.data.maps.duplicate(true)
	app.progress.data.learning["assessments"]=account.data.learning.assessments.duplicate(true)
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size=dimensions
		root.content_scale_size=dimensions
		await settle(3)
		for index in range(40):
			var id: String=str(maps[index].id)
			scope="Main briefing basis "+id+" "+str(dimensions)
			app._choose_stage(index/10,index%10,false)
			await settle(5)
			check(app.current_map.id==id and app.modal_context=="briefing","Actual Main stage selection enters this stage's briefing")
			var basis: Label=app.modal_body.find_child("StoryMapBasis",true,false)
			check(basis!=null,"Actual Main briefing includes the map basis")
			if basis==null: continue
			var geo: Dictionary=stage_geography(id)
			check(basis.text=="맵 제작 근거 · "+str(geo.renderingBasisKo),"Main briefing basis matches the actual selected stage")
			basis_label_geometry(basis)
			app.modal_scroll.ensure_control_visible(basis)
			await settle(3)
			check(app.modal_scroll.get_global_rect().grow(2).encloses(basis.get_global_rect()),"Main briefing scroll reveals the complete map basis")
			check(root.get_visible_rect().grow(1).encloses(app.modal_scroll.get_global_rect()),"Main basis reading pane fits the actual viewport")
			basis_observations.append({"kind":"mainBriefing","dimensions":dimensions,"stageId":id,"basis":geo.renderingBasisKo,"basisRect":basis.get_global_rect(),"scrollRect":app.modal_scroll.get_global_rect()})
	check(ProjectSettings.globalize_path(app.progress.save_path).replace("\\","/").simplify_path().to_lower().begins_with(OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower()+"/"),"Actual Main exposure writes remain in the unique isolated fixture")
	app._stop_narration()
	app.player.stop()
	app.player.stream=null
	for service in [app.battle_audio,app.battle_narrator,app.battle_announcer,app.voice_director]:
		if service!=null: service.shutdown()
	await create_timer(.5).timeout
	app.free()
	await settle(12)

func _initialize() -> void:
	Engine.max_fps=120
	call_deferred("run")

func check(value: bool,note: String) -> void:
	checks+=1
	if not value:
		failures.append(scope+": "+note)
		if failures.size()<=30: push_error("HISTORICAL_MAP_UI "+scope+": "+note)

func settle(count: int=6) -> void:
	for frame in range(count): await process_frame

func release_preview_resources() -> void:
	scope="native preview shutdown"
	var retained_previews: int=0
	for node in nodes(root):
		if node.get_script()==Preview: retained_previews+=1
	check(retained_previews==0,"All native preview nodes exit before shared renderer resources are released")
	var before: Dictionary=NativeBattlefield.shared_cache_diagnostics()
	NativeBattlefield.release_shared_resources()
	await settle(24)
	var after: Dictionary=NativeBattlefield.shared_cache_diagnostics()
	check(after.modelVariantGroups==0 and after.primitiveMeshes==0,"Shared battlefield model and primitive caches are empty after teardown")
	check(after.materials.textureCount==0 and after.materials.materialCount==0,"Shared battlefield material and texture caches are empty after teardown")
	cleanup={"retainedPreviewNodes":retained_previews,"sharedCachesBefore":before,"sharedCachesAfter":after,"framesAfterRelease":24,"sequence":"Free production screens and previews; release_shared_resources; wait24process frames; write report; quit"}
	print("HISTORICAL_MAP_UI_CLEANUP retainedPreviews=%d sharedCachesAfter=%s"%[retained_previews,str(after)])

func nodes(parent: Node) -> Array:
	var result: Array=[]
	for child in parent.get_children():
		result.append(child)
		result.append_array(nodes(child))
	return result

func text_geometry(ui: Control) -> void:
	var screen: Rect2=root.get_visible_rect()
	for node in nodes(ui):
		if not node is Control or not node.is_visible_in_tree(): continue
		var shown: Rect2=node.get_global_rect()
		var ancestor: Node=node.get_parent()
		while ancestor!=null and ancestor!=ui:
			if ancestor is Control and ancestor.clip_contents: shown=shown.intersection(ancestor.get_global_rect())
			ancestor=ancestor.get_parent()
		if not shown.has_area(): continue
		if node is Label or node is Button or node.has_method("get_text_layout"):
			check(screen.grow(2).encloses(shown),"Visible text fits the viewport: "+str(node.name))
		if node is Label:
			check(node.get_theme_font_size("font_size")>=20,"Readable body remains20px or larger")
			check(node.get_minimum_size().y<=node.size.y+1,"Wrapped label has its complete line height: "+node.text.left(65))
			if node.autowrap_mode==TextServer.AUTOWRAP_OFF:
				for line in node.text.split("\n"):
					check(node.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,node.get_theme_font_size("font_size")).x<=node.size.x+1,"Unwrapped glyphs fit their width")
		elif node is Button and not node is OptionButton and not node.text.is_empty():
			check(node.get_minimum_size().y<=node.size.y+1,"Native button fits its real font height: "+node.text.left(65))
		elif node.has_method("get_text_layout"):
			var layout: Dictionary=node.get_text_layout()
			check(layout.ruby_size>=16,"Furigana stays16px or larger")
			for run in layout.runs:
				check(Rect2(Vector2.ZERO,node.size).grow(1).encloses(run.bounds),"Ruby glyph fits: "+str(run.text))

func complete_through(number: int) -> void:
	account.data.maps.clear()
	account.data.learning["assessments"]={}
	for index in range(number):
		var id: String=str(maps[index].id)
		account.data.maps[id]={"wins":1}
		var lesson: Dictionary=account.stage_lessons[id]
		var count: int=lesson.newWords.size()+lesson.get("grammarSteps",[]).size()
		account.data.learning.assessments[id]={"passed":true,"count":count,"correctCount":count,"scopeHash":Gate.scope_hash(lesson),"attemptId":"historical-ui-fixture-"+id}

func shot(label: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	var folder: String="user://qa_historical_map_ui_captures"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path: String=folder+"/"+label+".png"
	var screenshot: Image=root.get_texture().get_image()
	check(screenshot!=null and not screenshot.is_empty(),"Actual GPU screenshot has rendered pixels")
	if screenshot!=null and not screenshot.is_empty():
		screenshot.save_png(path)
		captures.append(ProjectSettings.globalize_path(path))

func source_contracts() -> void:
	scope="historical data"
	check(maps.size()==40 and story.stages.size()==40,"Exactly40 stable stages join the story")
	check(geography.get("stages",[]).size()==40,"Exactly40 geography entries provide the map rendering basis")
	var source_code: String=FileAccess.get_file_as_string("res://native/front_end.gd")
	check(source_code.contains('var source_urls: Array=_geography(str(chosen.id)).get("sources",[])') and source_code.contains('var source_url: String=str(source_urls[0])') and source_code.contains('sources.pressed.connect(func(): OS.shell_open(source_url))'),"Production reference-link callback binds the first source URL from the actual selected stage")
	for index in range(40):
		var entry: Dictionary=story.stages[index]
		var map: Dictionary=maps[index]
		var geo: Dictionary=stage_geography(str(map.id))
		check(not geo.is_empty() and int(geo.get("stageNumber",0))==index+1,"Map rendering basis retains the real stage ID/order")
		var basis: String=str(geo.get("renderingBasisKo",""))
		check(not basis.strip_edges().is_empty() and basis.length()<=130,"Map rendering basis is nonempty and at most130characters: "+str(map.id))
		var sources: Array=geo.get("sources",[])
		check(not sources.is_empty(),"Map rendering basis has its authored historical source URLs: "+str(map.id))
		for url in sources: check(str(url).begins_with("https://") and not str(url).contains("\n"),"Reference is an intact HTTPS URL: "+str(map.id))
		check(entry.stageId==map.id and int(map.stageNumber)==index+1,"Story and geography retain their original stage IDs")
		check(str(entry.briefingJP).length()>=40 and str(entry.briefingJP).length()<=75 and str(entry.briefingJP).count("。")==2,"Voice briefing is exactly2 concise Japanese sentences")
		var written: String=""
		var spoken: String=""
		for part in entry.briefingParts:
			written+=str(part.text)
			spoken+=str(part.get("reading",part.text))
		check(written==entry.briefingJP and spoken==entry.briefingReading,"Authored ruby groups concatenate to the exact voice script/reading")
		check(str(entry.briefingKo).count(".")==2 and not str(entry.historySummaryKo).is_empty(),"Korean voice translation and historical summary remain distinct")
		check(str(entry.historyNarrativeKo).count(".")>=3 and str(entry.historyNarrativeKo).count(".")<=4,"Selection uses3–4 narrative sentences")
		check(map.historicalBattlefield.historyNarrativeKo==entry.historyNarrativeKo,"Battle, atlas and selection share the same narrative source")
	for index in [6,7]:
		check(maps[index].historicalBattlefield.groundSeason=="spring" and maps[index].historicalBattlefield.weather.key=="unknown","Kanegasaki uses spring greenery with no invented rain/snow")
	check(maps[26].historicalBattlefield.missionField.locationId==maps[25].historicalBattlefield.missionField.locationId,"Honnoji event leaves the player's physical mission at Takamatsu")

func atlas_progression() -> void:
	scope="fresh atlas"
	complete_through(0)
	var atlas: Control=Atlas.new()
	atlas.configure(account,maps,story,geography,Fonts.body())
	root.add_child(atlas)
	atlas.show_stage(str(maps[0].id),true)
	await settle()
	check(atlas.revealed_ids==[maps[0].id,maps[1].id],"Fresh account shows first battle and only its immediate locked successor")
	check(atlas.available_chapters==[0] and atlas.pin_groups.size()==2,"Future chapters and future battles stay hidden")
	atlas.show_stage(str(maps[39].id),true)
	await settle()
	check(atlas.selected_stage_id==maps[0].id,"Requesting an unreached final battle cannot expose its chapter")
	account.data.maps[maps[0].id]={"wins":1}
	atlas.show_stage(str(maps[1].id),true)
	await settle()
	check(atlas.action_button.disabled and atlas.gate_button.visible,"Clearing a battle alone leaves next battle locked and shows the real exam")
	var emitted: Dictionary={}
	atlas.assessment_requested.connect(func(id): emitted["assessment"]=id,CONNECT_ONE_SHOT)
	atlas.gate_button.pressed.emit()
	check(emitted.get("assessment")==maps[0].id,"Locked stage2 exam targets its actual previous stage1")
	complete_through(4)
	account.data.maps.erase(maps[0].id)
	check(account.map_unlocked(str(maps[4].id)),"Stage5 checks immediate stage4, without rechecking stage1")
	account.data.learning.assessments.erase(maps[3].id)
	atlas.show_stage(str(maps[4].id),true)
	await settle()
	check(atlas.action_button.disabled and atlas._gate_stage()==maps[3].id,"Stage5 points to actual stage4's required exam")
	check(account.map_lock_reason(str(maps[4].id)).contains("04단계") and not account.map_lock_reason(str(maps[4].id)).contains("01단계"),"Lock explanation names the actual predecessor")
	complete_through(10)
	atlas.show_stage(str(maps[10].id),true)
	await settle()
	check(atlas.available_chapters==[0,1] and atlas.pin_groups.size()==2,"Reaching next chapter reveals stages11/12 only")
	for name in ["AtlasHome","AtlasCatalog","AtlasResume"]:
		var result: Dictionary={}
		var signal_name: String={"AtlasHome":"home_requested","AtlasCatalog":"catalog_requested","AtlasResume":"resume_requested"}[name]
		atlas.connect(signal_name,func(): result["fired"]=true,CONNECT_ONE_SHOT)
		atlas.get_node(name).pressed.emit()
		check(result.get("fired")==true,"Navigation callback is preserved: "+name)
	atlas.free()
	await settle()

func atlas_layouts() -> void:
	complete_through(40)
	var atlas: Control=Atlas.new()
	atlas.configure(account,maps,story,geography,Fonts.body())
	root.add_child(atlas)
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size=dimensions
		root.content_scale_size=dimensions
		for chapter in range(4):
			scope="atlas "+str(dimensions)+" chapter"+str(chapter+1)
			atlas.show_stage(str(maps[chapter*10].id),true)
			await settle()
			var diagnostic: Dictionary=atlas.diagnostics()
			check(diagnostic.sourcePath==Atlas.COASTLINE_PATH and diagnostic.coastlineRingCount==34,"Own vector coast uses the actual PD Japan polygons")
			check(diagnostic.pinGroups.size()==10 and diagnostic.visibleStageIds.size()==10,"Only10 individual battles appear in the active chapter")
			check(diagnostic.static and not diagnostic.processing and not diagnostic.historicalTerritoryMap,"Static physical map does not invent historical territory borders")
			for index in range(atlas.pin_buttons.size()):
				var button: Button=atlas.pin_buttons[index]
				check(button.get_meta("stage_ids").size()==1,"Repeated regions keep separate named phase callouts")
				var id: String=str(button.get_meta("stage_ids")[0])
				var map: Dictionary=atlas.stage(id)
				check(button.text=="%02d"%int(map.stageNumber),"Small marker retains its own exact stage number")
				check(button.size.x<=52 and button.size.y<=46 and button.size.is_equal_approx(diagnostic.pinGroups[index].rect.size),"Compact numbered marker uses its actual font minimum for collision layout: "+button.name+" actual="+str(button.size)+" planned="+str(diagnostic.pinGroups[index].rect.size))
				check(button.get_node_or_null("CalloutHistoricPlace")==null and button.get_node_or_null("CalloutModernPlace")==null,"Unselected markers do not repeat large place cards")
				check(atlas.map_area.encloses(button.get_rect()),"Numbered marker fits the actual paper map")
				var geo: Dictionary=atlas.geography_by_id[id]
				var location: Dictionary=geo.get("phaseLocation",geo)
				var expected: Vector2=Vector2(float(location.lon),float(location.lat))
				var anchor: Dictionary=diagnostic.anchors[id]
				check(is_equal_approx(float(anchor.lon),expected.x) and is_equal_approx(float(anchor.lat),expected.y),"Leader retains the authored physical coordinate despite marker fanout")
				check(button.get_meta("real_anchor").is_equal_approx(anchor.display),"Number marker points to its actual coordinate dot")
				for other in range(index): check(not button.get_rect().intersects(atlas.pin_buttons[other].get_rect()),"Individual number markers do not overlap: "+button.name+" "+str(button.get_rect())+" vs "+atlas.pin_buttons[other].name+" "+str(atlas.pin_buttons[other].get_rect()))
			var marker_area: float=0.0
			for button in atlas.pin_buttons: marker_area+=button.size.x*button.size.y
			var selected_ids: Array=diagnostic.visibleStageIds.duplicate()
			for id in selected_ids:
				atlas._select_stage(str(id))
				await settle(2)
				var callout: Control=atlas.get_node("SelectedPlaceCallout")
				check(atlas.map_area.encloses(callout.get_rect()),"Selected place card fits the map")
				check(atlas.find_children("SelectedPlaceCallout","Panel",false,false).size()==1,"Only the selected battle exposes a place card")
				var labels: Dictionary=atlas.stage(str(id)).historicalBattlefield.atlasLabels
				check(callout.get_node("CalloutHistoricPlace").text==labels.historicPlaceKo and callout.get_node("CalloutModernPlace").text==labels.modernPlaceKo,"Selected place card preserves authored historic and modern names")
				check(callout.get_node("CalloutHistoricPlace").position.y<callout.get_node("CalloutModernPlace").position.y,"Selected historic place is above today's place")
				for button in atlas.pin_buttons: check(not callout.get_rect().intersects(button.get_rect()),"Selected place card does not cover numbered markers")
				check((marker_area+callout.size.x*callout.size.y)/(atlas.map_area.size.x*atlas.map_area.size.y)<.2,"At least80percent of the map remains free of place cards and markers")
				text_geometry(callout)
				await atlas_basis(atlas,str(id),dimensions)
			atlas.show_stage(str(maps[chapter*10].id),true)
			await settle(2)
			for link in diagnostic.battleLinks:
				check(link.from in diagnostic.visibleStageIds and link.to in diagnostic.visibleStageIds,"Progression links only join this chapter's actual coordinates")
				check(int(atlas.stage(link.to).stageNumber)==int(atlas.stage(link.from).stageNumber)+1,"Progression arrows follow successive authored battle numbers")
			text_geometry(atlas)
			observations.append({"kind":"atlas","dimensions":dimensions,"chapter":chapter+1,"visible":diagnostic.visibleStageIds,"coastlineRings":diagnostic.coastlineRingCount})
			await shot("atlas_"+str(chapter+1)+"_"+str(dimensions.x))
	atlas.free()
	await settle()

func catalog_layouts() -> void:
	complete_through(40)
	var front: Control=Front.new()
	front.maps=maps
	front.progress=account
	front.font=Fonts.body()
	front.campaign_story=story
	front.learning_plans=plans
	root.add_child(front)
	var dimensions_to_check: Array=[Vector2i(1280,800)] if "--basis-capture" in OS.get_cmdline_user_args() else [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]
	for dimensions in dimensions_to_check:
		root.size=dimensions
		root.content_scale_size=dimensions
		for index in range(40):
			if "--basis-capture" in OS.get_cmdline_user_args() and index not in [0,25,39]: continue
			if OS.get_cmdline_user_args().has("--representative") and index not in REPRESENTATIVE_STAGES: continue
			scope="catalog "+str(index+1)+" "+str(dimensions)
			front.selected_stage=index%10
			front.show_catalog(index/10,false)
			await settle()
			var preview: Control=front.get_node("CatalogBattlefieldPreview")
			check(preview.get_script()==Preview,"Selection uses the actual native3D battlefield wrapper")
			var diagnostic: Dictionary=preview.diagnostics()
			check(diagnostic.nativeBattlefield and diagnostic.terrain.stageId==maps[index].id and not diagnostic.terrain.photoFloor,"The selected stage's actual terrain is built, without a photograph floor")
			if "--require-all-rendered" in OS.get_cmdline_user_args():
				var release_layer: Dictionary=diagnostic.terrain.get("renderLayerContract",{})
				check(str(release_layer.get("mode",""))=="rendered" and bool(release_layer.get("distributionReady",false)) and int(release_layer.get("coverage",0))==40,"Selected catalog uses approved complete40map hybrid art with no fallback")
				check(bool(release_layer.get("sourceDataVerified",false)) and bool(release_layer.get("heightPreserved",false)) and bool(release_layer.get("normalizedUvHeightIndependent",false)),"Selected catalog preserves the source-verified physical height and artwork coordinates")
			check(diagnostic.static and not diagnostic.processing and diagnostic.mouseIgnore,"Static thumbnail does not consume UI input or per-frame processing")
			check(is_equal_approx(float(diagnostic.worldWidth),18.5) and diagnostic.elevation==50,"Thumbnail uses the real combat world width and current50degree projection")
			check(diagnostic.viewportSize.x<=960 and diagnostic.viewportSize.y<=640,"Thumbnail resolution has a bounded GPU budget")
			var requests: int=preview.render_requests
			preview.configure(maps[index])
			await settle(2)
			check(preview.render_requests==requests,"Identical state does not rebuild or render again")
			preview.hide()
			check(preview.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Hidden thumbnail immediately disables GPU updates")
			preview.show()
			await settle(2)
			check(preview.render_requests==requests,"Showing retained static art does not regenerate it")
			var narrative: Label=front.get_node("StageHistoricalNarrativeScroll/StageHistoricalNarrative")
			check(narrative.text==story.stages[index].historyNarrativeKo,"Former role box shows the selected battle's real3–4sentence story")
			check(front.get_node_or_null("DeploymentRoleLegend")==null and front.get_node_or_null("BattleMinutes5")==null,"Old role legend and5minute option are absent")
			check(front.get_node_or_null("BattleMinutes10")!=null and front.get_node_or_null("BattleMinutes20")!=null,"Only10/20minute modes remain")
			var facts: Label=front.get_node("StageTacticalDescriptionScroll/StageTacticalDescription")
			for field in ["때 · ","옛 지명 · ","오늘날 · ","상대 · ","결과 · "]: check(facts.text.contains(field),"Fact panel includes verified "+field)
			await catalog_basis(front,index,dimensions)
			if "--basis-capture" in OS.get_cmdline_user_args():
				var layer: Dictionary=diagnostic.terrain.get("renderLayerContract",{})
				check(bool(layer.get("renderedArtwork",false)) and bool(layer.get("heightPreserved",false)),"Representative catalog shows registered rendered art with real physical terrain height")
				observations.append({"kind":"basisCaptureArt","stageId":maps[index].id,"renderLayerContract":layer})
			text_geometry(front)
			if index in REPRESENTATIVE_STAGES: await shot(("catalog_basis_%02d_%d" if "--basis-capture" in OS.get_cmdline_user_args() else "catalog_%02d_%d")%[index+1,dimensions.x])
			if index==0:
				var selected: Dictionary={}
				front.battle_minutes_selected.connect(func(minutes): selected["minutes"]=minutes,CONNECT_ONE_SHOT)
				front.get_node("BattleMinutes20").pressed.emit()
				check(selected.get("minutes")==20,"Actual mode button forwards20 to the existing save/runtime handler")
			observations.append({"kind":"catalog","dimensions":dimensions,"stageId":maps[index].id,"terrainTriangles":diagnostic.terrain.terrainTriangles,"renderRequests":requests})
	front.show_campaign_map(str(maps[0].id))
	await settle()
	var emitted: Dictionary={}
	front.stage_chosen.connect(func(tier,index,study): emitted["indices"]=[tier,index,study],CONNECT_ONE_SHOT)
	front.get_node("CampaignAtlas").action_button.pressed.emit()
	check(emitted.get("indices")==[0,0,false],"Atlas sortie forwards the existing map index callback")
	front.show_home()
	await settle()
	check(front.get_node_or_null("CatalogBattlefieldPreview")==null,"Leaving selection releases its native thumbnail world")
	front.free()
	await settle()

func run() -> void:
	scope="isolated profile"
	var profile_prefix: String=qa_project_path("tests/profiles/historical-map-ui/").to_lower()
	var appdata: String=OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower().trim_suffix("/")
	var localdata: String=OS.get_environment("LOCALAPPDATA").replace("\\","/").simplify_path().to_lower().trim_suffix("/")
	check(appdata.begins_with(profile_prefix) and localdata.begins_with(profile_prefix),"APPDATA and LOCALAPPDATA both use isolated historical-map-ui profiles")
	check(OS.get_user_data_dir().replace("\\","/").simplify_path().to_lower().begins_with(appdata+"/"),"Actual user data path remains inside isolated APPDATA")
	check(FileAccess.file_exists(appdata+"/profile_guard.json"),"Profile guard exists before source fixtures are created")
	if not failures.is_empty():
		quit(2)
		return
	capture="--capture" in OS.get_cmdline_user_args()
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	story=JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
	geography=JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_geography.json"))
	plans=JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	account=Store.new()
	account.save_path="user://historical-map-ui-must-not-be-written.json"
	source_contracts()
	await atlas_progression()
	if not "--catalog-only" in OS.get_cmdline_user_args(): await atlas_layouts()
	if not "--atlas-only" in OS.get_cmdline_user_args(): await catalog_layouts()
	if "--basis-main" in OS.get_cmdline_user_args(): await main_briefing_basis()
	check(not FileAccess.file_exists(account.save_path),"Read-only UI never writes campaign/SRS/account data")
	check(not FileAccess.file_exists("user://progress.json"),"Default profile save is absent; Main basis QA uses only its unique fixture")
	await release_preview_resources()
	var path: String="user://qa_historical_map_ui.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_historical_map_ui.json"
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"basisObservations":basis_observations,"referenceLinkVerification":"Actual selected-stage sources/tooltip, valid callback connection and production first-URL closure binding; no external browser opened","captures":captures,"mapsSha256":FileAccess.get_sha256("res://native/maps.json"),"geographySha256":FileAccess.get_sha256("res://native/campaign_geography.json"),"appData":appdata,"localAppData":localdata,"actualUserDataDir":OS.get_user_data_dir(),"renderer":RenderingServer.get_video_adapter_name(),"cleanup":cleanup},"\t"))
	file.close()
	print("HISTORICAL_MAP_UI_QA checks="+str(checks)+" failures="+str(failures.size())+" report="+ProjectSettings.globalize_path(path))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
