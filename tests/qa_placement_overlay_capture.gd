extends SceneTree
## Real Main, fresh progress, initial supply and native viewport input dispatch.
## The first-wave learning report is hidden only for unobstructed visual QA.
const Store=preload("res://native/progress.gd")
var app: Node
var checks: int=0
var failures: Array=[]
var observations: Array=[]
var images: Array=[]

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		push_error("PLACEMENT OVERLAY "+message)

func settle() -> void:
	app.learning_field.clear()
	app._process(0.0)
	app.troops_3d.sync_actor_states(app.game.actor_states())
	app.game.queue_redraw()
	app.game.actor_overlay.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func screenshot(name_value: String) -> Image:
	await settle()
	var image: Image=root.get_texture().get_image()
	var path: String="C:/JP_DF/dist/preview-placement-"+name_value+".png"
	check(image.save_png(path)==OK,"Actual GPU screen saves "+name_value)
	images.append(path)
	return image

func legal_hints(type_name: String) -> Array:
	var result: Array=[]
	for index in range(app.game.zones.size()):
		var point: Vector2=app.game.placement_hints[index]
		if point.x<0: continue
		var zone: Dictionary=app.game._eligible_zone(point,type_name)
		check(not zone.is_empty() and zone==app.game.zones[index],type_name+": advertised hint is an actual legal position for its own zone")
		if not zone.is_empty(): result.append({"point":point,"zone":zone,"screen":app.game.field_rect.position+point*app.game.field_rect.size})
	check(not result.is_empty(),type_name+": there is a legal displayed placement hint")
	return result

func check_visible_markers(before: Image,after: Image,hints: Array,type_name: String) -> void:
	var visible: int=0
	for hint in hints:
		var center: Vector2i=Vector2i(hint.screen)
		var changed: int=0
		for y in range(center.y-10,center.y+11):
			for x in range(center.x-10,center.x+11):
				if x<0 or y<0 or x>=after.get_width() or y>=after.get_height(): continue
				var a: Color=before.get_pixel(x,y)
				var b: Color=after.get_pixel(x,y)
				if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>.03: changed+=1
		check(changed>=15,type_name+": actual GPU marker is visibly rendered above the photograph at "+str(hint.point))
		if changed>=15: visible+=1
		observations.append({"type":type_name,"hint":{"x":hint.point.x,"y":hint.point.y},"zoneId":hint.zone.get("id",""),"changedPixels":changed})
	check(visible==hints.size(),type_name+": every legal hint remains visible on the actual screen")

func mouse_click(point: Vector2) -> void:
	# Leave the OS pointer alone: the event's coordinates must drive placement.
	var press=InputEventMouseButton.new()
	press.position=point
	press.global_position=point
	press.button_index=MOUSE_BUTTON_LEFT
	press.button_mask=MOUSE_BUTTON_MASK_LEFT
	press.pressed=true
	Input.parse_input_event(press)
	await process_frame
	var release=InputEventMouseButton.new()
	release.position=point
	release.global_position=point
	release.button_index=MOUSE_BUTTON_LEFT
	release.pressed=false
	Input.parse_input_event(release)
	await process_frame

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/placement-overlay/") or DisplayServer.get_name()=="headless":
		push_error("Placement visual QA requires its isolated GPU profile")
		quit(2)
		return
	root.size=Vector2i(1440,900)
	var fixture=Store.new()
	fixture.save_path="user://placement-overlay-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	fixture.data.settings={"music":false,"voice":false}
	check(fixture.write_save(),"Fresh isolated progress saves")
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path=fixture.save_path
	root.add_child(app)
	await process_frame
	app._select_tier(0)
	app._select_map(0)
	app._begin_battle()
	app.set_process(false)
	app.game.set_process(false)
	app.player.stop()
	# Let the normal map transition finish so photo fading cannot be counted
	# as marker visibility, and the passive screenshot shows final brightness.
	await create_timer(.7).timeout
	app._process(0.0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var passive_path: String="C:/JP_DF/dist/preview-placement-battle-passive.png"
	check(root.get_texture().get_image().save_png(passive_path)==OK,"Actual full battlefield with passive report saves")
	images.append(passive_path)
	check(app.army_toolbar.is_visible_in_tree() and app.army_grid.get_child_count()==8,"All eight roster slots remain visible in the fixed bottom toolbar")
	check(app.learning_panel.is_visible_in_tree(),"Learning remains visible above the roster")
	check(app.learning_panel.get_theme_stylebox("panel") is StyleBoxEmpty and app.learning_panel.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Passive learning subtitle has no background and permits battlefield input")
	check(app.active_word.outline_size==2 and app.example_label.outline_size==2,"Word and example outlines keep Japanese, reading and translation readable over the battlefield")
	check(app.game.field_rect.encloses(app.learning_panel.get_global_rect()),"Passive learning subtitle is drawn over the battlefield")
	for card in app.army_grid.get_children():
		check(app.army_toolbar.get_global_rect().encloses(card.get_global_rect()),"Roster card stays inside the toolbar: "+str(card.name))
	check(not app.learning_field.choosing and app.learning_field.target_buttons.is_empty(),"Passive battle report creates no choice-card obstruction")
	check(app.learning_field.report_card.get_theme_stylebox("panel") is StyleBoxEmpty and app.learning_field.report_text.outline_size==2,"The passive messenger report also uses outlined text without a panel")
	check(not app.toast_label.visible,"The passive banner does not overlap a duplicate toast")
	check(app.progress.data.maps.is_empty(),"Fixture has no fabricated campaign clears")
	check(app.game.input_enabled and app.modal==null and not app.front_end.visible,"Actual battle field input is available")
	var initial_gold: int=app.game.gold
	await settle()
	var before: Image=root.get_texture().get_image()
	app._choose_unit("archer")
	app.recruit_button.pressed.emit()
	check(str(app.game.pending.get("type",""))=="archer","Actual recruit button creates an archer pending placement")
	check(app.game.gold==initial_gold-int(app.progress.unit_definition("archer").cost),"Archer pending charges only the actual catalog cost")
	var ranged_hints: Array=legal_hints("archer")
	var ranged: Image=await screenshot("ranged")
	check_visible_markers(before,ranged,ranged_hints,"archer")
	app.recruit_button.pressed.emit()
	check(app.game.pending.is_empty() and app.game.gold==initial_gold,"Actual cancel button refunds the archer without adding money")
	app._choose_unit("spear")
	await settle()
	before=root.get_texture().get_image()
	app.recruit_button.pressed.emit()
	check(str(app.game.pending.get("type",""))=="spear","Actual recruit button creates a spear pending placement")
	check(app.game.gold==initial_gold-int(app.progress.unit_definition("spear").cost),"Spear pending uses the original initial supply")
	var ground_hints: Array=legal_hints("spear")
	var ground: Image=await screenshot("ground")
	check_visible_markers(before,ground,ground_hints,"spear")
	if not ground_hints.is_empty():
		await mouse_click(ground_hints[0].screen)
		check(app.game.units.size()==1 and app.game.pending.is_empty(),"Real viewport mouse input places the pending spear")
		var selected: Dictionary=app.game.snapshot().selected
		check(str(selected.get("type",""))=="spear" and not str(selected.get("postName","")).is_empty(),"Placed infantry has its actual ground post name")
		check(float(selected.get("maxHp",0))>0 and float(selected.get("hp",0))==float(selected.get("maxHp",0)),"Placed infantry has intact finite initial health")
		check(app.army_health.visible and app.army_tactics.text.contains(str(selected.get("postName",""))) and app.army_tactics.text.contains("체력"),"Actual sidebar shows the selected post and health")
		check(not app.hint_bar.visible,"The selected information popup does not overlap a redundant hint strip")
		var selected_screen: Vector2=app.game.field_rect.position+Vector2(float(selected.get("x",0)),float(selected.get("y",0)))*app.game.field_rect.size
		check(not app.army_panel.get_global_rect().intersects(Rect2(selected_screen-Vector2(18,55),Vector2(36,65))),"The selected information popup does not cover the selected soldier")
		observations.append({"placed":"spear","postName":selected.get("postName",""),"health":selected.get("hp",0),"maximumHealth":selected.get("maxHp",0),"sidebar":app.army_tactics.text})
		await screenshot("ground-placed")
	# Verify the other placement role with a second paid native-input click too.
	app._choose_unit("archer")
	app.recruit_button.pressed.emit()
	var final_hints: Array=legal_hints("archer")
	if not final_hints.is_empty():
		await mouse_click(final_hints[0].screen)
		check(app.game.units.size()==2 and app.game.pending.is_empty(),"Real viewport mouse input also places a paid ranged unit")
	check(app.game.gold==initial_gold-int(app.progress.unit_definition("spear").cost)-int(app.progress.unit_definition("archer").cost),"Both native-input placements preserve normal starting-supply accounting")
	root.size=Vector2i(1280,800)
	await settle()
	check(app.army_toolbar.is_visible_in_tree() and app.army_grid.get_child_count()==8,"Minimum-size screen keeps all eight roster cards visible")
	for card in app.army_grid.get_children():
		check(app.army_toolbar.get_global_rect().encloses(card.get_global_rect()),"Minimum-size toolbar contains its roster card: "+str(card.name))
		for child in card.get_children():
			if child is Label:
				check(card.get_global_rect().encloses(child.get_global_rect()),"Minimum-size roster label fits its actual card: "+str(child.text))
	check(app.active_word.base_size==36 and app.example_label.base_size==24,"Minimum-size learning panel preserves 36px word and 24px example")
	await screenshot("minimum")
	var report={"checks":checks,"failures":failures,"images":images,"observations":observations,"initialSupply":initial_gold,"remainingSupply":app.game.gold,"adapter":RenderingServer.get_video_adapter_name(),"scope":"Actual Main with fresh isolated progress, catalog-cost recruit/cancel, native Input.parse_input_event mouse coordinates, actual GPU marker pixel visibility and sidebar health; first-wave learning report cleared only for unobstructed visual QA."}
	var file=FileAccess.open("user://qa_placement_overlay_capture.json",FileAccess.WRITE)
	check(file!=null,"Isolated QA report opens")
	report["checks"]=checks
	if file!=null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("PLACEMENT_OVERLAY_GPU ",JSON.stringify({"checks":checks,"failures":failures,"images":images,"adapter":RenderingServer.get_video_adapter_name()}))
	app.player.stream=null
	app.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit(0 if failures.is_empty() else 1)
