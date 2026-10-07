extends SceneTree
## Independent UI flow and geometry QA. All navigation uses real pressed callbacks.
## Campaign mutations belong to this test's isolated save, never player progress.

const Store = preload("res://native/progress.gd")
const Portrait = preload("res://native/barracks_portrait.gd")
var app: Node
var checks: int = 0
var failures: Array = []
var stages_seen: Array = []
var deployment_rects: Dictionary = {}
var save_path: String

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("UI REDESIGN QA " + message)

func settle(frames: int = 8) -> void:
	for frame in range(frames):
		await process_frame

func named(parent: Node, node_name: String) -> Node:
	for node in parent.find_children(node_name,"",true,false):
		if node is Control and node.is_visible_in_tree() and not node.is_queued_for_deletion():
			return node
	return null

func text_button(parent: Node, text: String, contains: bool = false) -> Button:
	for node in parent.find_children("*","Button",true,false):
		if not node.is_visible_in_tree() or node.is_queued_for_deletion():
			continue
		if node.text.contains(text) if contains else node.text==text:
			return node
	return null

func press(button: Button, context: String) -> void:
	check(button!=null,context+": button exists in the actual visible screen")
	if button==null:
		return
	check(not button.disabled,context+": button is enabled")
	if button.disabled:
		return
	button.pressed.emit()
	await settle()

func inside(control: Control, rect: Rect2) -> bool:
	if control==null or not control.is_visible_in_tree():
		return false
	var actual: Rect2=control.get_global_rect()
	return actual.size.x>1 and actual.size.y>1 and rect.grow(1.0).encloses(actual)

func portrait_matches(id: String) -> bool:
	var portrait: Control=named(app.barracks,"SelectedArmyPortrait")
	var evolution: int=int(app.progress.army_evolution(id).stage)
	if portrait==null or not portrait.has_method("diagnostics"):
		return false
	var state: Dictionary=portrait.diagnostics()
	var source: Dictionary=Portrait.resolve_source(id,evolution)
	return str(state.get("unitId",""))==id and int(state.get("evolution",-1))==evolution and bool(state.get("ready",false)) and str(state.get("sourceKind",""))=="authored-idle-sheet" and not source.is_empty() and str(state.get("sourcePath",""))==str(source.path) and int(state.get("row",-1))==int(source.row) and portrait.texture!=null and portrait.output.texture==portrait.texture and int(state.get("frames",0))==6

func check_idle_motion() -> void:
	var portrait: Control=named(app.barracks,"SelectedArmyPortrait")
	check(portrait!=null and portrait.has_method("diagnostics"),"Selected detail uses the authored standing-pose portrait helper")
	if portrait==null or not portrait.has_method("diagnostics"):
		return
	var clock: float=float(portrait.diagnostics().animationClock)
	var region: Vector4=portrait.output.material.get_shader_parameter("frame_a")
	await create_timer(1.0/float(portrait.diagnostics().fps)+.05).timeout
	var moved: bool=region!=portrait.output.material.get_shader_parameter("frame_a")
	check(float(portrait.diagnostics().animationClock)>clock and moved,"Visible selected portrait actually advances to a different authored idle pose")
	check(bool(portrait.diagnostics().active) and portrait.output.visible and portrait.output.texture==portrait.texture and portrait.output.material is ShaderMaterial,"Selected portrait is presented through its active source texture and pose-sampling material")

func return_barracks() -> void:
	var portrait: Control=named(app.barracks,"SelectedArmyPortrait")
	await press(text_button(app.barracks,"돌아가기"),"barracks return")
	check(app.front_end.visible and app.front_end.view=="home" and not app.barracks.visible,"Barracks return callback restores home")
	if is_instance_valid(portrait) and portrait.has_method("diagnostics"):
		var clock: float=float(portrait.diagnostics().animationClock)
		await settle()
		check(not bool(portrait.diagnostics().active) and not portrait.is_processing() and float(portrait.diagnostics().animationClock)==clock,"Returning home suspends hidden portrait animation")

func run() -> void:
	root.size=Vector2i(1280,800)
	root.content_scale_size=Vector2i(1280,800)
	save_path="user://ui-redesign-%d.json" % Time.get_ticks_usec()
	var fixture=Store.new()
	fixture.save_path=save_path
	fixture.data.army.currency=100000
	fixture.data.army.levels.archer=3
	fixture.data.settings={"music":false,"voice":false}
	check(fixture.write_save(),"Isolated UI fixture is persisted")
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path=save_path
	root.add_child(app)
	await settle(16)
	app.set_process(false)
	app.game.set_process(false)
	app.player.stop()
	check(root.get_visible_rect().size==Vector2(1280,800),"Minimum supported 1280x800 viewport is actually used")
	check(app.front_end.visible and app.front_end.view=="home","Actual Main starts at home")
	for menu_name in ["HomeSortie","HomeBarracks","HomeDictionary"]:
		check(inside(named(app.front_end,menu_name),root.get_visible_rect()),menu_name+": home menu is visible within the viewport")
	# Inspecting a locked class remains possible; its training action must be locked.
	await press(named(app.front_end,"HomeBarracks"),"HomeBarracks")
	check(app.barracks.visible and not app.front_end.visible and app.barracks.can_train,"Home opens the trainable barracks")
	await press(named(app.barracks,"ArmyCard_gunner"),"locked gunner roster row")
	check(app.barracks.selected_unit_id=="gunner" and portrait_matches("gunner"),"Locked row selects its own real portrait")
	var locked_train: Button=named(app.barracks,"Train_gunner")
	check(locked_train!=null and locked_train.disabled,"Locked gunner cannot train")
	await press(named(app.barracks,"ArmyCard_archer"),"archer roster row")
	check(portrait_matches("archer"),"Selected archer detail uses its current evolution portrait")
	var funds: int=int(app.progress.data.army.currency)
	var training_cost: int=app.progress.army_upgrade_cost("archer")
	await press(named(app.barracks,"Train_archer"),"real archer training")
	check(app.progress.army_level("archer")==4 and int(app.progress.data.army.currency)==funds-training_cost,"Training callback debits once and advances Lv3 to Lv4")
	check(portrait_matches("archer"),"Training across an evolution updates selected portrait to e1")
	await check_idle_motion()
	await return_barracks()
	# Unlock all classes in the isolated fixture to inspect the full command layout.
	for stage in app.maps:
		app.progress.data.maps[str(stage.id)]={"wins":1}
	check(app.progress.write_save(),"All-class layout fixture is saved independently")
	await press(named(app.front_end,"HomeBarracks"),"all-class barracks")
	for definition in app.progress.unit_catalog:
		var id: String=str(definition.id)
		await press(named(app.barracks,"ArmyCard_"+id),id+" roster selection")
		check(app.barracks.selected_unit_id==id and portrait_matches(id),id+": row selection binds the requested class's authored standing poses and current evolution metadata")
		var train: Button=named(app.barracks,"Train_"+id)
		check(train!=null and not train.disabled,id+": unlocked affordable below-max training is available")
	await return_barracks()
	# Dictionary must preserve the field rather than resetting a different map.
	var original_id: String=str(app.game.config.id)
	var original_gold: int=app.game.gold
	await press(named(app.front_end,"HomeDictionary"),"HomeDictionary")
	check(app.front_end.view=="catalog" and app.front_end.study_mode,"Dictionary menu opens the study catalog")
	var dictionary_row: Button=named(app.front_end,"Stage_basic-forest")
	if dictionary_row==null:
		var first_stage: Dictionary=app.maps.filter(func(stage): return str(stage.tier)=="basic")[0]
		dictionary_row=named(app.front_end,"Stage_"+str(first_stage.id))
	await press(dictionary_row,"dictionary stage row")
	var dictionary_index: int=app.front_end.selected_stage
	await press(named(app.front_end,"CatalogSortie"),"CatalogSortie dictionary")
	check(app.modal_context=="study" and str(app.catalog_study_lesson.id)==str(app.curriculum.basic[dictionary_index].id),"Dictionary callback opens the selected lesson")
	check(str(app.game.config.id)==original_id and app.game.gold==original_gold,"Dictionary preserves the underlying field and supply")
	await press(text_button(app.modal,"도감 목록으로",true),"dictionary return")
	check(app.front_end.visible and app.front_end.study_mode and app.modal==null,"Dictionary return callback restores study catalog")
	await press(text_button(app.front_end,"돌아가기"),"catalog home return")
	await press(named(app.front_end,"HomeSortie"),"HomeSortie")
	check(app.front_end.view=="catalog" and not app.front_end.study_mode,"Sortie menu opens the battle catalog")
	var background_paths: Dictionary={}
	for tier in range(4):
		await press(text_button(app.front_end,app.front_end.TIER_NAMES[tier]),"tier %d" % tier)
		var available: Array=app.maps.filter(func(stage): return str(stage.tier)==app.TIER_IDS[tier])
		var scroll: ScrollContainer=named(app.front_end,"StageCatalogScroll")
		check(scroll!=null and scroll.get_child(0).get_child_count()==10,"Tier %d exposes exactly ten real stage rows" % tier)
		for index in range(10):
			var stage: Dictionary=available[index]
			var row: Button=named(app.front_end,"catalogStage_"+str(stage.id))
			if row==null: row=named(app.front_end,"Stage_"+str(stage.id))
			await press(row,"stage "+str(stage.id))
			check(app.front_end.selected_tier==tier and app.front_end.selected_stage==index,str(stage.id)+": row callback retains the correct tier and index")
			var matching_preview: TextureRect=null
			for picture in app.front_end.find_children("*","TextureRect",true,false):
				if picture.is_visible_in_tree() and picture.texture!=null and picture.texture.resource_path==str(stage.background):
					matching_preview=picture
			check(matching_preview!=null and inside(matching_preview,root.get_visible_rect()),str(stage.id)+": selected preview loads this stage's actual background within the screen")
			check(inside(named(app.front_end,"CatalogSortie"),root.get_visible_rect()),str(stage.id)+": selected-stage sortie action remains visible")
			var description: String=str(stage.get("tactics",{}).get("descriptionKo",stage.get("trait",{}).get("descriptionKO",stage.get("description",""))))
			for label in app.front_end.find_children("*","Label",true,false):
				if label.is_visible_in_tree() and label.text==description:
					check(label.size.x<=551 and label.autowrap_mode!=TextServer.AUTOWRAP_OFF,str(stage.id)+": real stage description wraps within its assigned width")
			background_paths[str(stage.background)]=true
			stages_seen.append(str(stage.id))
	check(stages_seen.size()==40 and background_paths.size()==40,"All forty independent stage previews are observed")
	var chosen_stage: Dictionary=app.maps.filter(func(stage): return str(stage.tier)=="advanced")[9]
	await press(named(app.front_end,"CatalogSortie"),"selected advanced stage sortie")
	check(str(app.current_map.id)==str(chosen_stage.id) and app.modal_context=="briefing","Sortie callback opens the selected final-stage briefing")
	var start_button: Button=text_button(app.modal,"출진")
	check(inside(start_button,root.get_visible_rect()),"Minimum-viewport briefing start action is visible without scrolling")
	await press(start_button,"briefing battle start")
	check(app.battle_started and app.modal==null and not app.front_end.visible,"Briefing start callback enters the battlefield")
	var expected_field=Rect2(24,116,890,522)
	check(app.field_clip.get_global_rect()==expected_field and app.game.field_rect==expected_field,"UI redesign preserves the existing minimum-size battlefield rectangle")
	app.game.gold=10000
	app.game._emit_state()
	await settle()
	check(app.army_grid.get_child_count()==8,"Battle command grid contains all eight actual class buttons")
	check(app.army_scroll.scroll_vertical==0,"All-class deployment starts without scrolling")
	for definition in app.progress.unit_catalog:
		var id: String=str(definition.id)
		var card: Button=named(app.army_grid,"DeployCard_"+id)
		app.army_scroll.ensure_control_visible(card)
		await settle()
		check(inside(card,app.army_scroll.get_global_rect()) and inside(card,root.get_visible_rect()),id+": deployment button is fully accessible while tactical status remains visible")
		if card!=null:
			deployment_rects[id]={"position":[card.global_position.x,card.global_position.y],"size":[card.size.x,card.size.y]}
			check(not card.get_global_rect().intersects(app.recruit_button.get_global_rect()),id+": deployment button does not overlap the recruit action")
			for label in card.find_children("*","Label",true,false):
				var width: float=label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x
				check(width<=label.size.x+0.5,id+": actual card label fits without clipped characters: "+label.text)
		await press(card,id+" deployment card")
		check(app.chosen_unit_id==id and str(app.progress.data.army.selected)==id,id+": actual card callback selects and persists this class")
		var cost: int=int(definition.cost)
		check(app.recruit_button.text.contains(str(cost)),id+": recruit action displays this class's real supply cost")
		var supply: int=app.game.gold
		var wallet: int=int(app.progress.data.army.currency)
		await press(app.recruit_button,id+" recruit")
		check(str(app.game.pending.get("type",""))==id and supply-app.game.gold==cost,id+": real recruit callback creates this class and charges its displayed cost once")
		check(int(app.progress.data.army.currency)==wallet,id+": recruitment preserves permanent army funds")
		await press(app.recruit_button,id+" recruit cancel")
		check(app.game.pending.is_empty() and app.game.gold==supply,id+": cancel callback refunds exactly once")
	check(inside(app.army_tactics,app.army_panel.get_global_rect()),"Tactical status remains visible while selecting every class")
	# Open the same barracks from a paused active field; training stays locked.
	app._show_home()
	await settle()
	await press(named(app.front_end,"HomeBarracks"),"active-battle barracks")
	check(not app.barracks.can_train,"Active battle locks permanent training")
	for definition in app.progress.unit_catalog:
		var id: String=str(definition.id)
		await press(named(app.barracks,"ArmyCard_"+id),id+" active-battle detail")
		var train: Button=named(app.barracks,"Train_"+id)
		check(train!=null and train.disabled,id+": active-battle detail keeps training disabled")
	await return_barracks()
	var preserved_id: String=str(app.game.config.id)
	var preserved_gold: int=app.game.gold
	await press(named(app.front_end,"HomeSortie"),"active-battle catalog")
	await press(text_button(app.front_end,"전장 복귀"),"catalog active-field return")
	check(not app.front_end.visible and app.ui.visible and app.field_clip.visible and str(app.game.config.id)==preserved_id and app.game.gold==preserved_gold,"Catalog return callback restores the same active battlefield and supply")
	var report={"checks":checks,"failures":failures,"viewport":[1280,800],"stageIds":stages_seen,"deploymentRects":deployment_rects,"savePath":save_path,"scope":"Actual pressed callbacks, resource identity, minimum-viewport button bounds and isolated-wallet observations. Headless checks geometry and interaction; root's GPU screenshots assess visual typography and aesthetic quality."}
	var file=FileAccess.open("user://qa_ui_redesign.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("UI_REDESIGN_QA ",JSON.stringify({"checks":checks,"failures":failures,"stages":stages_seen.size(),"deployCards":deployment_rects.size(),"report":ProjectSettings.globalize_path("user://qa_ui_redesign.json")}))
	app.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)
