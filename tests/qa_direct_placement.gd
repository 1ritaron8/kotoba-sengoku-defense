extends SceneTree
## Observe real previews, input and payments without changing product sources.
## All progress fixtures live in the verifier's isolated APPDATA profile.
const Battle = preload("res://native/game.gd")
const Store = preload("res://native/progress.gd")
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var checks := 0
var failures: Array[String] = []
var observations: Array = []
var events: Array[Dictionary] = []
var app: Node
var maps: Array
var catalog: Array
var engine_deployments := 0
var native_deployments := 0
var native_clicks := 0
var profile := ""

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		if failures.size() <= 35: push_error("DIRECT_PLACEMENT " + message)

func settle(frames: int = 2) -> void:
	for index in range(frames): await process_frame

func record_event(event: Dictionary) -> void:
	events.append(event.duplicate(true))

func action_count(action: String) -> int:
	var count := 0
	for event in events:
		if str(event.get("action", event.get("type",""))) == action: count += 1
	return count

func economy(game: Node) -> Dictionary:
	return {"gold":game.gold,"units":game.units.size(),"recruits":game.recruits,"nextId":game.next_id,
		"ids":game.units.map(func(unit): return int(unit.id))}

func unchanged(game: Node, before: Dictionary, context: String) -> void:
	check(economy(game)==before,context+": money, unit count, recruitment count and IDs remain unchanged")

func point_from(value) -> Vector2:
	if value is Vector2: return value
	return Vector2(float(value.get("x",-1)),float(value.get("y",-1)))

func legal_point(game: Node, type_name: String, avoid_ui: bool = false) -> Vector2:
	for zone in game.zones:
		var point: Vector2 = game._zone_placement_hint(zone,type_name)
		if point.x < 0: continue
		if avoid_ui and (point.y<.12 or point.y>.79): continue
		return point
	return Vector2(-1,-1)

func illegal_point(game: Node, type_name: String) -> Vector2:
	# Search an actual unsupported field point, rather than asserting a photo feature.
	for y in range(2,19):
		for x in range(2,19):
			var point := Vector2(x/20.0,y/20.0)
			if game._eligible_zone(point,type_name).is_empty(): return point
	return Vector2(.01,.01)

func preview_query(game: Node, point: Vector2, type_name: String, context: String) -> Dictionary:
	var before := economy(game)
	var query: Dictionary = game.placement_preview(point)
	unchanged(game,before,context+" preview query")
	check(bool(query.get("active",false)) and str(query.get("type",""))==type_name,context+": preview retains the exact chosen class")
	check(query.has("valid") and query.has("affordable") and query.has("reason") and query.has("position"),context+": preview exposes legality, affordability and actual position")
	check(int(query.get("cost",-1))==int(game.recruit_catalog[type_name].cost),context+": preview cost matches the displayed class definition")
	return query

func begin_preview(game: Node, type_name: String, context: String) -> bool:
	var before := economy(game)
	var deploys := action_count("deploy")
	var recruits := action_count("recruit")
	var started: bool = game.begin_placement(type_name)
	check(started,context+": unlocked class enters preview")
	unchanged(game,before,context+" class selection")
	check(str(game.pending.get("type",""))==type_name and bool(game.pending.get("preview",false)) and int(game.pending.get("paid",-1))==0,context+": pending is an unpaid preview of this class")
	check(game.actor_states().filter(func(actor): return bool(actor.get("friendly",false))).size()==game.units.size(),context+": an unpaid ghost is not a combat unit or friendly actor")
	check(action_count("deploy")==deploys and action_count("recruit")==recruits,context+": selecting a class does not emit paid recruitment/deployment sounds")
	return started

func engine_matrix() -> void:
	var game: Node = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.game_event.connect(record_event)
	var levels := {"archer":1,"spear":3,"samurai":4,"gunner":7,"naginata":8,"monk":9,"commander":8,"ninja":10}
	game.configure_roster(catalog,TYPES,levels)
	for map in maps:
		for type_name in TYPES:
			game.load_map(map)
			events.clear()
			var context: String = str(map.id)+" "+type_name
			if not begin_preview(game,type_name,context): continue
			var initial := economy(game)
			var point := legal_point(game,type_name)
			check(point.x>=0,context+": this actual map provides a legal class-specific position")
			if point.x<0:
				game.cancel_recruit()
				continue
			var query := preview_query(game,point,type_name,context)
			check(bool(query.get("valid",false)) and bool(query.get("affordable",false)),context+": initial map funds cover a legal preview")
			check(str(query.get("placementRole",""))==("ranged" if type_name=="archer" else "ground"),context+": preview role agrees with class tactics")
			var invalid := illegal_point(game,type_name)
			var invalid_query := preview_query(game,invalid,type_name,context+" wrong terrain")
			check(not bool(invalid_query.get("valid",true)) and not str(invalid_query.get("reason","")).is_empty(),context+": wrong terrain explains why placement is rejected")
			check(not game.place_unit(invalid.x,invalid.y),context+": wrong terrain cannot create a unit")
			unchanged(game,initial,context+" invalid click")
			check(action_count("recruit")==0 and action_count("deploy")==0,context+": invalid clicks emit no successful deployment/recruit audio")
			game.cancel_recruit()
			unchanged(game,initial,context+" cancellation")
			check(game.pending.is_empty(),context+": cancellation removes the preview")
			if not begin_preview(game,type_name,context+" retry"): continue
			query=preview_query(game,point,type_name,context+" commit")
			check(game.place_unit(point.x,point.y),context+": one valid click commits deployment")
			var cost: int = int(game.recruit_catalog[type_name].cost)
			check(game.gold==int(initial.gold)-cost and game.units.size()==1 and game.recruits==int(initial.recruits)+1 and game.next_id==int(initial.nextId)+1,context+": the valid commit charges and allocates exactly once")
			check(game.pending.is_empty(),context+": successful commit clears the unpaid preview")
			check(action_count("deploy")==1 and action_count("recruit")==0,context+": the direct flow emits one deploy and no duplicate paid recruitment event")
			if game.units.is_empty(): continue
			engine_deployments += 1
			var unit: Dictionary=game.units[0]
			check(str(unit.type)==type_name and int(unit.get("campaignLevel",0))==int(levels[type_name]),context+": committed model retains class and saved training")
			check(point_from(query.position).distance_to(unit.position)<.00001,context+": the preview's projected foot becomes the actual deployed foot")
			var committed := economy(game)
			check(not game.place_unit(point.x,point.y),context+": a duplicate stale click cannot commit again")
			unchanged(game,committed,context+" duplicate click")
			game.cancel_recruit()
			unchanged(game,committed,context+" post-commit cancellation")
			# Retrying on the occupied foot must reject even when the zone is legal.
			if game.gold>=cost and begin_preview(game,type_name,context+" overlap"):
				var overlap := preview_query(game,unit.position,type_name,context+" occupied foot")
				check(not bool(overlap.get("valid",true)),context+": occupied-foot preview is invalid")
				check(not game.place_unit(unit.position.x,unit.position.y),context+": overlap cannot charge or add a unit")
				unchanged(game,committed,context+" overlap click")
				check(action_count("deploy")==1,context+": overlap produces no successful deployment sound")
				game.cancel_recruit()
			observations.append({"mapId":map.id,"unitType":type_name,"initialGold":initial.gold,"cost":cost,"position":query.position,"role":query.placementRole})
	await engine_boundaries(game)
	game.queue_free()
	await settle()

func engine_boundaries(game: Node) -> void:
	game.load_map(maps[0])
	game.configure_roster(catalog,TYPES,{})
	events.clear()
	var baseline := economy(game)
	for index in range(40):
		var type_name: String=TYPES[index%TYPES.size()]
		begin_preview(game,type_name,"rapid engine swap %d"%index)
	unchanged(game,baseline,"forty rapid class swaps")
	check(action_count("recruit")==0 and action_count("deploy")==0,"Rapid class swaps cannot leak any successful audio event")
	game.cancel_recruit()
	unchanged(game,baseline,"cancel after rapid swaps")
	# Defend the commit boundary if funds change after a valid preview was selected.
	begin_preview(game,"archer","budget commit boundary")
	var point := legal_point(game,"archer")
	for budget in [59,0,-1]:
		game.gold=budget
		var before := economy(game)
		var query := preview_query(game,point,"archer","budget %d"%budget)
		check(not bool(query.get("affordable",true)) and not bool(query.get("valid",true)),"Changed budget %d yields an unaffordable preview"%budget)
		check(not game.place_unit(point.x,point.y),"Changed budget %d cannot commit"%budget)
		unchanged(game,before,"insufficient or negative budget %d"%budget)
	game.cancel_recruit()
	game.gold=60
	begin_preview(game,"archer","exact budget")
	check(game.place_unit(point.x,point.y) and game.gold==0,"An exact budget pays once and reaches zero without going negative")
	game.load_map(maps[0])
	game.configure_roster(catalog,["archer","spear"],{})
	var locked_before := economy(game)
	check(not game.begin_placement("ninja"),"Locked class cannot begin a preview")
	check(not game.begin_placement("not-a-unit"),"Unknown class cannot silently fall back to a different class")
	unchanged(game,locked_before,"locked/unknown class")
	check(game.pending.is_empty(),"Locked/unknown requests leave no wrong-class preview")
	game.configure_roster(catalog,TYPES,{})
	begin_preview(game,"spear","finite coordinate guard")
	var finite_before := economy(game)
	for bad in [Vector2(-1,.5),Vector2(2,.5),Vector2(NAN,.5),Vector2(.5,INF)]:
		check(not game.place_unit(bad.x,bad.y),"Non-field/non-finite placement is rejected: "+str(bad))
		unchanged(game,finite_before,"invalid coordinate "+str(bad))
	game.cancel_recruit()
	game.finished=true
	check(not game.begin_placement("archer"),"Finished battles cannot enter paid deployment")
	unchanged(game,finite_before,"finished battle")

func mouse_event(position: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index=button
	event.pressed=true
	event.position=position
	event.global_position=position
	# No mouse-motion prerequisite: placement must read the actual click coordinates.
	Input.parse_input_event(event)
	var release: InputEventMouseButton=event.duplicate()
	release.pressed=false
	Input.parse_input_event(release)
	native_clicks += 1
	await settle()

func escape_key() -> void:
	var event := InputEventKey.new()
	event.keycode=KEY_ESCAPE
	event.pressed=true
	Input.parse_input_event(event)
	var release: InputEventKey=event.duplicate()
	release.pressed=false
	Input.parse_input_event(release)
	await settle()

func mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position=position
	event.global_position=position
	Input.parse_input_event(event)
	await settle()

func start_stage(index: int) -> void:
	app._select_tier(index/10)
	app._select_map(index%10)
	await settle()
	app._begin_battle()
	app.game.set_process(false)
	await settle()
	events.clear()

func choose_card(type_name: String, native_mouse: bool) -> void:
	var card: Button=app.army_grid.get_node("DeployCard_"+type_name)
	if native_mouse:
		await mouse_event(card.get_global_rect().get_center())
	else:
		card.pressed.emit()
		await settle()

func main_matrix() -> void:
	var fixture=Store.new()
	var save_path: String="user://direct-placement-%d.json"%Time.get_ticks_msec()
	for map in maps: fixture.data.maps[str(map.id)]={"wins":1}
	fixture.data.settings={"music":false,"voice":false,"effects":true,"effectsVolume":.8}
	fixture.save_path=save_path
	check(fixture.write_save(),"Actual Main reads an isolated unlocked campaign fixture")
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path=save_path
	root.add_child(app)
	await settle(4)
	app.set_process(false)
	app.game.set_process(false)
	app.player.stop()
	app.player.stream=null
	app.game.game_event.connect(record_event)
	var wallet: int=int(app.progress.data.army.currency)
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size=dimensions
		root.content_scale_size=dimensions
		app._layout()
		await settle(3)
		# Ground, ranged, harbor, bridge and special-objective maps share input semantics.
		for index in [0,3,4,5]:
			for type_name in TYPES:
				await start_stage(index)
				var context: String=str(app.current_map.id)+" "+str(dimensions)+" "+type_name
				var initial := economy(app.game)
				var audio_before: Dictionary=app.battle_audio.play_counts.duplicate()
				await choose_card(type_name,native_deployments%2==0)
				check(str(app.game.pending.get("type",""))==type_name and bool(app.game.pending.get("preview",false)),context+": one bottom card click starts the exact class preview")
				unchanged(app.game,initial,context+" actual card click")
				check(int(app.progress.data.army.currency)==wallet,context+": selecting a class preserves permanent funds")
				check(not app.army_panel.is_visible_in_tree(),context+": unpaid preview does not pretend to be a selected deployed unit")
				var point := legal_point(app.game,type_name,true)
				check(point.x>=0,context+": actual visible field has a legal target")
				if point.x<0:
					app.game.cancel_recruit()
					continue
				var query := preview_query(app.game,point,type_name,context)
				var invalid := illegal_point(app.game,type_name)
				await mouse_event(app.game._screen(invalid))
				unchanged(app.game,initial,context+" native invalid field click")
				check(str(app.game.pending.get("type",""))==type_name,context+": invalid click keeps the intended class available for retry")
				check(action_count("recruit")==0 and action_count("deploy")==0,context+": preview and invalid clicks produce no successful sound events")
				app.battle_audio._process(.3)
				await mouse_event(app.game._screen(point))
				var cost: int=int(app.progress.unit_definition(type_name).cost)
				check(app.game.gold==int(initial.gold)-cost and app.game.units.size()==1 and app.game.pending.is_empty(),context+": a native valid click pays once and commits one unit")
				check(action_count("deploy")==1 and action_count("recruit")==0,context+": actual Main receives exactly one successful deploy event")
				if app.game.units.is_empty(): continue
				native_deployments += 1
				var unit: Dictionary=app.game.units[0]
				check(str(unit.type)==type_name and point_from(query.position).distance_to(unit.position)<.00001,context+": committed class and foot agree with the preview")
				check(app.army_panel.is_visible_in_tree(),context+": committed unit opens the real selected-unit inspector")
				check(int(app.battle_audio.play_counts.get("deploy",0))==int(audio_before.get("deploy",0))+1 and int(app.battle_audio.play_counts.get("recruit",0))==int(audio_before.get("recruit",0)),context+": actual audio plays deployment once without pre-payment recruitment noise")
				var committed := economy(app.game)
				await mouse_event(app.game._screen(unit.position))
				unchanged(app.game,committed,context+" native duplicate click")
				check(int(app.game.selected_id)==int(unit.id),context+": clicking the placed model selects it instead of buying another")
				var overlap_type: String=type_name if app.game.gold>=cost else "spear"
				await choose_card(overlap_type,false)
				await mouse_event(app.game._screen(unit.position))
				unchanged(app.game,committed,context+" native overlap click")
				check(action_count("deploy")==1,context+": native overlap has no duplicate deploy event")
				await escape_key()
				unchanged(app.game,committed,context+" Escape cancellation")
				check(app.game.pending.is_empty() and app.modal==null,context+": first Escape cancels preview without unexpectedly opening the menu")
	await main_boundaries(wallet)

func main_boundaries(wallet: int) -> void:
	await start_stage(0)
	var before := economy(app.game)
	for index in range(24):
		await choose_card(TYPES[index%TYPES.size()],false)
		check(str(app.game.pending.get("type",""))==str(TYPES[index%TYPES.size()]),"Rapid Main card swap replaces the preview without requiring a cancel %d"%index)
	unchanged(app.game,before,"twenty-four actual Main class swaps")
	await mouse_event(app.game._screen(Vector2(.5,.5)),MOUSE_BUTTON_RIGHT)
	check(app.game.pending.is_empty(),"Actual right-click removes the unpaid preview")
	unchanged(app.game,before,"native right-click cancellation")
	check(int(app.progress.data.army.currency)==wallet,"Rapid swaps/cancellation never leak permanent funds")
	# A pause menu must intercept map input while retaining a reversible selection.
	await choose_card("archer",false)
	var cursor_before := economy(app.game)
	var ghost_point := legal_point(app.game,"archer",true)
	await mouse_motion(app.game._screen(ghost_point))
	check(app.game.placement_cursor_visible and app.game.placement_cursor.distance_to(ghost_point)<.00001,"Native pointer motion moves the unpaid ghost to the actual field point")
	unchanged(app.game,cursor_before,"native ghost movement")
	await mouse_motion(Vector2(2,2))
	check(not app.game.placement_cursor_visible,"Pointer outside the field hides the placement ghost")
	unchanged(app.game,cursor_before,"pointer exits battlefield")
	await mouse_motion(app.game._screen(ghost_point))
	check(app.game.placement_cursor_visible,"Returning to the battlefield restores the same unpaid ghost")
	app._show_pause_menu()
	await settle()
	var point := legal_point(app.game,"archer",true)
	await mouse_event(app.game._screen(point))
	unchanged(app.game,before,"native click behind pause modal")
	check(app.modal!=null,"A blocked map click cannot dismiss the pause modal")
	app._close_modal()
	await settle()
	app.game.cancel_recruit()
	# Starter progress exposes two classes and prevents direct/native locked purchases.
	app.progress.data.maps.clear()
	app.progress.write_save()
	app._rebuild_army_cards()
	app.game.configure_roster(app.progress.unit_catalog,app.progress.unlocked_units(),app.progress.data.army.levels)
	await settle()
	var locked: Button=app.army_grid.get_node("DeployCard_ninja")
	check(locked.disabled,"Locked class is visibly unavailable in the actual toolbar")
	await mouse_event(locked.get_global_rect().get_center())
	unchanged(app.game,before,"native locked card")
	check(app.game.pending.is_empty(),"Clicking a locked card produces no wrong fallback ghost")
	app._choose_unit("ninja")
	unchanged(app.game,before,"direct locked callback defense")
	check(app.game.pending.is_empty(),"Locked callback defense cannot create a preview")
	# Affordability can change while a ghost is active; UI remains recoverable.
	await choose_card("archer",false)
	app.game.gold=0
	app.game._emit_state()
	var poor := economy(app.game)
	await mouse_event(app.game._screen(point))
	unchanged(app.game,poor,"actual zero-budget field click")
	check(action_count("deploy")==0,"Zero-budget Main click emits no successful deployment")
	await escape_key()
	check(app.game.pending.is_empty() and app.modal==null,"Insufficient-budget preview remains cancellable")
	app.game.gold=60
	app.game._emit_state()
	await choose_card("archer",true)
	await mouse_event(app.game._screen(point))
	check(app.game.units.size()==1 and app.game.gold==0,"Restored exact funds allow native deployment without a dead UI state")

func teardown() -> void:
	if app==null: return
	app.player.stop()
	app.player.stream=null
	app.battle_audio.shutdown()
	await create_timer(.5).timeout
	app.queue_free()
	await settle(3)

func run() -> void:
	profile=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("").to_lower()+"/"):
		push_error("Direct placement QA refuses the player's profile")
		quit(2)
		return
	root.size=Vector2i(1440,900)
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	check(maps.size()==40 and catalog.size()==8,"Actual product provides forty maps and eight class definitions")
	var contract: Node=Battle.new()
	var api_ready: bool=contract.has_method("begin_placement") and contract.has_method("placement_preview")
	contract.free()
	check(api_ready,"Production exposes the direct-preview placement API")
	if api_ready:
		await engine_matrix()
		await main_matrix()
		check(engine_deployments==320,"All forty maps and eight classes completed independent payment/deployment checks")
		check(native_deployments==96,"All three viewport sizes, four tactical maps and eight classes completed actual Main deployment")
	await teardown()
	var report := {"checks":checks,"failures":failures,"engineDeployments":engine_deployments,"nativeDeployments":native_deployments,"nativeClicks":native_clicks,"maps":maps.size(),"classes":TYPES,"observations":observations,"profile":profile,"resourceRoot":ProjectSettings.globalize_path("res://"),"packed":OS.get_cmdline_user_args().has("--packed"),"scope":"40x8 engine placement on actual initial map budgets; 3 viewport sizes x4 tactical maps x8 classes through actual Main cards and mouse input, cancelled/invalid/duplicate/overlap/locked/changed-budget paths. Headless tests observe model position/query and actual payment/events; visible raster contrast or ghost opacity require GPU validation."}
	var file:=FileAccess.open("user://qa_direct_placement.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("DIRECT_PLACEMENT_QA ",JSON.stringify({"checks":checks,"failures":failures,"engineDeployments":engine_deployments,"nativeDeployments":native_deployments,"nativeClicks":native_clicks,"report":ProjectSettings.globalize_path("user://qa_direct_placement.json")}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
