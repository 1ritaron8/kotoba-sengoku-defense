extends SceneTree
## Production menu text is measured in an isolated, in-memory account.
const Front = preload("res://native/front_end.gd")
const Barracks = preload("res://native/barracks.gd")
const Training = preload("res://native/unit_training.gd")
const Store = preload("res://native/progress.gd")
const Gate = preload("res://native/learning_gate.gd")
const Fonts = preload("res://native/game_fonts.gd")
const Battlefield = preload("res://native/battlefield_3d.gd")
const Presentation = preload("res://native/battlefield_presentation.gd")
var checks: int = 0
var failures: Array[String] = []
var observations: Array = []
var captures: Array[String] = []
var events: Dictionary = {}
var capture: bool = false
var maps: Array = []
var account: RefCounted

func _initialize() -> void:
	Engine.max_fps=120
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		if failures.size()<35: push_error("SENGOKU_MENU "+note)

func settle() -> void:
	for frame in range(5): await process_frame

func geometry(node: Control, scope: String) -> void:
	var measured: int = 0
	for control in node.find_children("*","Control",true,false):
		if not control.is_visible_in_tree(): continue
		if not (control is Label or control is Button or control.has_method("get_text_layout")): continue
		var shown: Rect2=control.get_global_rect()
		var ancestor: Node=control.get_parent()
		while ancestor!=null and ancestor!=node:
			if ancestor is Control and ancestor.clip_contents:
				shown=shown.intersection(ancestor.get_global_rect())
			ancestor=ancestor.get_parent()
		if not shown.has_area(): continue
		check(root.get_visible_rect().grow(2).encloses(shown),scope+": text inside screen "+control.name)
		if control is Label:
			var points: int=control.get_theme_font_size("font_size")
			check(points>=20,scope+": readable label "+control.text.left(32))
			check(control.get_minimum_size().y<=control.size.y+1,scope+": complete wrapped height "+control.text.left(32))
			if control.autowrap_mode==TextServer.AUTOWRAP_OFF:
				for line in control.text.split("\n"):
					check(control.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,points).x<=control.size.x+1,scope+": complete unwrapped text "+line.left(32))
		elif control is Button and not control.text.is_empty():
			var points: int=control.get_theme_font_size("font_size")
			var style: StyleBox=control.get_theme_stylebox("normal")
			var usable: float=control.size.x-style.get_content_margin(SIDE_LEFT)-style.get_content_margin(SIDE_RIGHT)
			check(points>=20,scope+": readable button "+control.text)
			check(control.get_minimum_size().y<=control.size.y+1,scope+": complete button height "+control.text)
			if control.autowrap_mode==TextServer.AUTOWRAP_OFF:
				check(control.get_theme_font("font").get_string_size(control.text,HORIZONTAL_ALIGNMENT_LEFT,-1,points).x<=usable+1,scope+": complete button glyphs "+control.text)
		elif control.has_method("get_text_layout"):
			var layout: Dictionary=control.get_text_layout()
			check(control.font==Fonts.japanese(),scope+": Japanese brush face")
			check(float(layout.ruby_size)>=16,scope+": readable kana")
			for glyph_run in layout.runs:
				check(Rect2(Vector2.ZERO,control.size).grow(1).encloses(glyph_run.bounds),scope+": full ruby glyphs "+str(glyph_run.text))
		measured+=1
	observations.append({"scope":scope,"screen":{"w":root.size.x,"h":root.size.y},"measuredTextControls":measured})

func gap_above(upper: Control, lower: Control, minimum: float, note: String) -> void:
	check(upper.get_global_rect().end.y+minimum<=lower.get_global_rect().position.y,note)

func shot(name_hint: String) -> void:
	if not capture: return
	# Capture the settled screen, rather than the initial menu fade.
	await create_timer(.35).timeout
	await RenderingServer.frame_post_draw
	var path: String="user://sengoku-"+name_hint+".png"
	check(root.get_texture().get_image().save_png(path)==OK,"Actual UI capture written "+name_hint)
	captures.append(ProjectSettings.globalize_path(path))

func front_checks() -> void:
	var menu: Control=Front.new()
	menu.progress=account
	menu.maps=maps
	menu.font=Fonts.body()
	menu.campaign_story=JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
	menu.learning_plans=JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	menu.battle_active=true
	menu.barracks_requested.connect(func(): events.barracks=int(events.get("barracks",0))+1)
	menu.training_requested.connect(func(): events.training=int(events.get("training",0))+1)
	menu.resume_requested.connect(func(): events.resume=int(events.get("resume",0))+1)
	root.add_child(menu)
	for dimensions in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dimensions
		root.content_scale_size=dimensions
		menu.show_home()
		await settle()
		geometry(menu,"home "+str(dimensions))
		var home_bounds: Dictionary={"scope":"home bounds","screen":{"w":dimensions.x,"h":dimensions.y},"controls":{}}
		for home_name in ["HomeDictionary","HomeSettings","HomeResume","HomeProgressFooter"]:
			var home_rect: Rect2=menu.get_node(home_name).get_global_rect()
			home_bounds.controls[home_name]={"x":home_rect.position.x,"y":home_rect.position.y,"w":home_rect.size.x,"h":home_rect.size.y}
		observations.append(home_bounds)
		check(menu.get_node("HomeMotifJP").text=="戦国絵巻　天下統一への道","Approved campaign title is displayed verbatim")
		check(menu.get_node("HomeMotifKO").text=="전국시대, 천하 통일의 이야기","Korean campaign meaning is displayed")
		check(menu.get_node("HomeMotifJP").get_theme_font("font")==Fonts.japanese(),"Japanese title uses bundled brush font")
		gap_above(menu.get_node("HomeTitle"),menu.get_node("HomeSubtitle"),1,"Japanese main title clears its Korean subtitle")
		gap_above(menu.get_node("HomeMotifJP"),menu.get_node("HomeMotifKO"),8,"Campaign JP and KR have separate rows")
		gap_above(menu.get_node("HomeResume"),menu.get_node("HomeProgressFooter"),10,"Resume action clears fixed footer")
		gap_above(menu.get_node("HomeDictionary"),menu.get_node("HomeSettings"),10,"Main menu clears utility buttons")
		gap_above(menu.get_node("HomeSettings"),menu.get_node("HomeResume"),8,"Utility buttons clear the resume action")
		check(menu.get_node("HomeBarracks/MenuRuby").word.jp=="兵舎" and menu.get_node("HomeBarracks/MenuRuby").word.ko=="병영","Barracks keeps Japanese and Korean meaning")
		check(menu.get_node("HomeTraining/MenuRuby").word.jp=="鍛錬" and menu.get_node("HomeTraining/MenuRuby").word.ko=="훈련 던전","Training keeps Japanese and Korean meaning")
		for name_hint in ["HomeBarracks","HomeTraining","HomeResume"]:
			menu.get_node(name_hint).pressed.emit()
		await shot("home-"+str(dimensions.x))
		if "--home-only" in OS.get_cmdline_user_args():
			menu.hide()
			continue
		menu.view="settings"
		menu._rebuild()
		await settle()
		geometry(menu,"settings "+str(dimensions))
		check(menu.get_node("SettingsTitle").text=="設定","Settings has Japanese heading")
		check(menu.get_node("VolumeControls").sliders.size()==4,"Four independent volume sliders remain present")
		await shot("settings-"+str(dimensions.x))
		for study in [false,true]:
			for tier in range(4):
				for stage in range(10):
					if capture and (tier!=0 or stage!=0): continue
					menu.selected_stage=stage
					menu.show_catalog(tier,study)
					if not capture: menu.get_node("CatalogBattlefieldPreview").hide()
					await settle()
					geometry(menu,"catalog %s/%d/%d/%s"%[str(dimensions),tier,stage,study])
					check(menu.get_node("CatalogBattlefieldPreview").image.flip_h==Presentation.mirror_for_stage(maps[tier*10+stage]),"Catalog preview uses the shared stage orientation")
					gap_above(menu.get_node("CatalogTitle"),menu.get_node("CatalogSubtitle"),4,"Catalog Japanese title clears Korean meaning")
					gap_above(menu.get_node("StageBattleTitle"),menu.get_node("StageTacticalDescriptionScroll"),10,"Long battle title clears historical details")
					gap_above(menu.get_node("StageTacticalDescriptionScroll"),menu.get_node("CatalogProgressFooter"),12,"Historical scroll clears fixed footer")
					check(menu.get_node("StageTacticalDescriptionScroll").size.y>=70,"Long battle titles retain useful scroll height")
					if not study:
						check(menu.get_node("CatalogBattlePreparations").text=="戦支度 · 전투 시간","Preparation label preserves Korean purpose")
						check(not menu.get_node("CatalogBattlePreparations").get_global_rect().intersects(menu.get_node("BattleMinutes10").get_global_rect()),"Preparation caption clears duration controls")
					if (capture and tier==0 and stage==0) or (not capture and tier==3 and stage==9):
						await shot(("dictionary-" if study else "catalog-")+str(dimensions.x))
		if capture:
			menu.selected_stage=7
			menu.show_catalog(2,false)
			await settle()
			geometry(menu,"longest campaign title "+str(dimensions))
			gap_above(menu.get_node("StageBattleTitle"),menu.get_node("StageTacticalDescriptionScroll"),10,"Longest battle title clears its historical scroll")
			await shot("catalog-long-"+str(dimensions.x))
		menu.hide()
	check(events.get("barracks",0)==2 and events.get("training",0)==2 and events.get("resume",0)==2,"Main menu action signals are preserved")
	menu.free()
	await settle()

func barracks_checks() -> void:
	var barracks: Control=Barracks.new()
	barracks.progress=account
	barracks.font=Fonts.body()
	root.add_child(barracks)
	for dimensions in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dimensions
		root.content_scale_size=dimensions
		for definition in account.unit_catalog:
			for level in [1,8,10]:
				if capture and (str(definition.id)!="naginata" or level!=8): continue
				account.data.army.levels[definition.id]=level
				barracks.selected_unit_id=str(definition.id)
				barracks.open()
				await settle()
				geometry(barracks,"barracks %s/%s/Lv%d"%[str(dimensions),str(definition.id),level])
				var header: Control=barracks.get_node("BarracksHeader")
				check(header.get_node("BarracksTitle").text=="兵舎","Barracks title matches home menu")
				check(header.get_node("BarracksTitle").get_theme_font("font")==Fonts.japanese(),"Barracks heading uses bundled brush font")
				check(not header.get_node("BarracksTitle").get_global_rect().intersects(header.get_node("BarracksSubtitle").get_global_rect()),"Barracks title clears Korean meaning")
				check(barracks.get_node("BarracksTraining").text=="鍛錬 · 훈련 던전","Barracks training action matches training screen")
				check(barracks.get_node_or_null("SelectedArmyPortrait")!=null,"Commander portrait remains present after palette setup")
				var commander_name: Control=barracks.get_node("CommanderNamePlaque/CommanderName")
				check(commander_name.reading_group_palette[0]==Color("725022") and commander_name.reading_group_palette[1]==Color("285266"),"Paper readings alternate two dark, readable colours")
				check(not barracks.get_node("CommanderDetail").get_global_rect().intersects(barracks.get_node("BarracksRoster").get_global_rect()),"Detail panel clears fixed roster")
				if str(definition.id)=="naginata" and level==8:
					await shot("barracks-"+str(dimensions.x))
		barracks.hide()
	barracks.free()
	await settle()

func training_checks() -> void:
	var drill: Control=Training.new()
	drill.render_enabled=false
	root.add_child(drill)
	drill.configure(account,maps,Fonts.body())
	for dimensions in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dimensions
		root.content_scale_size=dimensions
		drill.open_menu()
		await settle()
		geometry(drill,"training menu "+str(dimensions))
		check(drill.find_child("TrainingTitle",true,false).text=="鍛錬","Training heading matches menu actions")
		check(drill.find_child("TrainingSubtitle",true,false).text.contains("훈련 던전"),"Training Korean meaning remains visible")
		await shot("training-menu-"+str(dimensions.x))
		for id in Training.UNIT_ORDER:
			check(drill.open(str(id),maps[14]),"Production training screen opens "+str(id))
			drill.set_process(false)
			await settle()
			geometry(drill,"training practice %s/%s"%[str(dimensions),str(id)])
			check(drill.header.text.begins_with("鍛錬 · "),"Practice title remains Japanese with Korean unit name")
			check(not drill.footer_box.get_global_rect().intersects(drill.field_clip.get_global_rect()),"Practice field clears fixed footer")
			for phase in ["failed","success"]:
				drill.phase=phase
				drill.error_ko="표시한 엄폐 지점과 같은 둑의 경로에서 다시 연습하십시오. 물이나 막힌 지형은 건너지 않습니다." if phase=="failed" else ""
				drill._refresh_ui()
				await settle()
				geometry(drill,"training result %s/%s/%s"%[str(dimensions),str(id),phase])
				if str(id)=="ninja" and phase=="success": await shot("training-practice-"+str(dimensions.x))
		drill.close()
	drill.free()
	await settle()

func training_presentation_checks() -> void:
	var drill: Control=Training.new()
	drill.render_enabled=false
	root.add_child(drill)
	drill.configure(account,maps,Fonts.body())
	root.size=Vector2i(1280,800)
	root.content_scale_size=root.size
	for stage_index in [13,0]:
		var stage: Dictionary=maps[stage_index]
		for id in Training.UNIT_ORDER:
			check(drill.open(str(id),stage),"Orientation fixture opens "+str(id))
			drill.set_process(false)
			await settle()
			var mirrored: bool=Presentation.mirror_for_stage(stage)
			check(drill.battle.presentation_mirrored==mirrored,"Practice uses shared orientation")
			check(mirrored==(stage_index==0),"Opposite presentation cases are exercised")
			var recommended: Vector2=drill.recommended
			check(recommended.x>=0 and not drill.guide.markers.is_empty(),"Practice has a visible recommended marker")
			if recommended.x<0 or drill.guide.markers.is_empty(): continue
			var marker: Dictionary=drill.guide.markers[0]
			var shown: Vector2=Presentation.to_view(recommended,mirrored)
			check(Vector2(float(marker.x),float(marker.y)).is_equal_approx(shown),"Recommended marker matches the displayed field")
			check(drill.deploy(),"Actual practice action submits "+str(id))
			if not drill.battle.pending.is_empty():
				var motion: InputEventMouseMotion=InputEventMouseMotion.new()
				motion.position=shown*drill.field_clip.size
				drill._field_input(motion)
				check(drill.battle.placement_cursor.is_equal_approx(recommended),"Displayed pointer maps to canonical placement")
				var click: InputEventMouseButton=InputEventMouseButton.new()
				click.button_index=MOUSE_BUTTON_LEFT
				click.pressed=true
				click.position=motion.position
				drill._field_input(click)
			check(drill.battle.recruitment_queue.size()==1,"Displayed action queues one actual troop")
			if drill.battle.recruitment_queue.size()==1:
				var job: Dictionary=drill.battle.recruitment_queue[0]
				check(job.position.is_equal_approx(recommended),"Production destination retains the original canonical position")
				observations.append({"scope":"practice orientation","stageId":str(stage.id),"unitId":str(id),"mirrored":mirrored,"canonical":{"x":recommended.x,"y":recommended.y},"display":{"x":shown.x,"y":shown.y},"actualProductionPosition":{"x":job.position.x,"y":job.position.y}})
		drill.close()
	drill.free()
	await settle()

func run() -> void:
	var profile: String=OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower()
	var local_profile: String=OS.get_environment("LOCALAPPDATA").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/sengoku-menu-layout-").to_lower()) or not local_profile.begins_with(qa_project_path("tests/profiles/sengoku-menu-layout-").to_lower()):
		push_error("Refusing a non-isolated UI profile")
		quit(2)
		return
	capture="--capture" in OS.get_cmdline_user_args()
	check(not capture or DisplayServer.get_name()!="headless","Actual captures require GPU")
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	account=Store.new()
	account.save_path="user://sengoku-layout-account-must-not-be-written.json"
	for stage in maps:
		account.data.maps[stage.id]={"wins":1}
		var lesson: Dictionary=account.stage_lessons[stage.id]
		var count: int=lesson.get("newWords",[]).size()+lesson.get("grammarSteps",[]).size()
		if not account.data.learning.has("assessments"): account.data.learning.assessments={}
		account.data.learning.assessments[stage.id]={"passed":true,"complete":true,"correctCount":count,"count":count,"scopeHash":Gate.scope_hash(lesson)}
	var original_levels: Dictionary=account.data.army.levels.duplicate(true)
	var before: String=JSON.stringify(account.data)
	if "--orientation-only" in OS.get_cmdline_user_args():
		await training_presentation_checks()
	else:
		await front_checks()
		if not "--home-only" in OS.get_cmdline_user_args():
			await barracks_checks()
			account.data.army.levels=original_levels
			await training_checks()
			await training_presentation_checks()
	check(JSON.stringify(account.data)==before,"Presentation fixtures preserve progression and economy")
	check(not FileAccess.file_exists(account.save_path),"No save file was created or read")
	Battlefield.release_shared_resources()
	var report: Dictionary={"checks":checks,"failures":failures,"observations":observations,"captures":captures,"scope":"Production FrontEnd, Barracks, Training at 1280x800 and 1920x1080. Measured font/glyph/ruby bounds, Korean meanings, title/footer gaps, callbacks. Isolated synthetic account; no player save. GPU screenshots only when captures are listed."}
	var file: FileAccess=FileAccess.open("user://sengoku-menu-layout-report.json",FileAccess.WRITE)
	if file==null:
		push_error("Cannot write isolated QA report")
		quit(2)
		return
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("SENGOKU_MENU checks=%d failures=%d observations=%d captures=%d report=%s"%[checks,failures.size(),observations.size(),captures.size(),ProjectSettings.globalize_path("user://sengoku-menu-layout-report.json")])
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
