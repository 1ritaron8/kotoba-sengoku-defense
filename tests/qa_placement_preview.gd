extends SceneTree
const Battle = preload("res://native/game.gd")
const Store = preload("res://native/progress.gd")
var checks: int=0
var failures: Array=[]
var events: Array=[]

func _initialize() -> void: call_deferred("run")

func check(value: bool, description: String) -> void:
	checks+=1
	if not value: failures.append(description);push_error(description)

func count_action(action: String) -> int:
	return events.filter(func(event):return str(event.get("action",event.type))==action).size()

func first_hint(game: Node2D) -> Vector2:
	for hint in game.placement_hints:
		if hint.x>=0: return hint
	return Vector2(-1,-1)

func click(game: Node2D, point: Vector2, button: int=MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton=InputEventMouseButton.new()
	event.pressed=true
	event.button_index=button
	event.position=game._screen(point)
	game._unhandled_input(event)

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/"): quit(2);return
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var store = Store.new()
	var game = Battle.new()
	root.add_child(game)
	game.set_process(false)
	root.size=Vector2i(1280,800)
	root.content_scale_size=Vector2i(1280,800)
	game.configure_roster(store.unit_catalog,["archer","spear","commander"],{"archer":4})
	game.load_map(maps[0])
	game.set_field_rect(Rect2(16,64,1248,636))
	game.game_event.connect(func(event):events.append(event.duplicate(true)))
	var original_gold: int=game.gold
	var original_id: int=game.next_id
	check(game.begin_placement("archer"),"Unlocked affordable class enters preview")
	check(game.gold==original_gold and game.next_id==original_id and game.recruits==0 and game.units.is_empty(),"Beginning preview reserves neither money nor real actor identity")
	check(bool(game.pending.preview) and int(game.pending.paid)==0 and int(game.pending.id)==-1,"Preview metadata distinguishes an uncommitted deployment")
	check(count_action("recruit")==0 and count_action("deploy")==0,"Beginning preview causes no paid recruitment or placement sound event")
	check(game.begin_placement("archer") and game.begin_placement("spear") and game.begin_placement("archer"),"Repeated selection and rapid class switching remain supported")
	check(game.gold==original_gold and game.next_id==original_id and game.recruits==0,"Repeated previews accumulate no charges or ids")
	var hint: Vector2=first_hint(game)
	var preview: Dictionary=game.placement_preview(hint)
	check(bool(preview.valid) and bool(preview.visible) and bool(preview.affordable),"Immediate world preview starts on an advertised legal candidate")
	check(preview.type=="archer" and int(preview.evolution)==1 and int(preview.campaignLevel)==4,"The chosen class and earned evolution reach its world preview")
	game.set_input_enabled(false)
	check(not bool(game.placement_preview(hint).visible),"An overlay input lock hides the render-only ghost")
	click(game,hint)
	check(game.units.is_empty() and game.gold==original_gold,"An overlay cannot click through to commit a hidden ghost")
	game.set_input_enabled(true)
	var before_pending: Dictionary=game.pending.duplicate(true)
	check(not game.begin_placement("monk") and not game.begin_placement("no-such-class"),"Locked and unknown ids cannot borrow an unlocked appearance")
	check(game.pending==before_pending and game.gold==original_gold,"Rejected selection preserves the current valid preview")
	for bad in [Vector2(0,0),Vector2(INF,.5),Vector2(NAN,.5),Vector2(.5,1.1)]:
		check(not game.place_unit(bad.x,bad.y),"Illegal and non-finite clicks cannot commit")
		check(game.gold==original_gold and game.units.is_empty() and game.next_id==original_id and game.recruits==0,"Rejected click preserves budget, roster, id and recruitment count")
	check(count_action("deploy")==0,"Invalid clicking produces no success effect")
	game.gold=int(game.pending.cost)-1
	check(not game.place_unit(hint.x,hint.y) and not bool(game.placement_preview(hint).affordable),"Commit rechecks money changed after preview began")
	check(game.units.is_empty() and game.next_id==original_id and game.recruits==0,"Insufficient-money commit creates no partial unit")
	game.gold=-1
	check(not game.place_unit(hint.x,hint.y) and game.gold==-1,"Negative money cannot become an accidental purchase")
	game.gold=original_gold
	game.start_battle()
	game._spawn_enemy("raider")
	var enemy_id: int=int(game.enemies[0].id)
	click(game,hint)
	check(game.units.size()==1 and game.gold==original_gold-int(store.unit_definition("archer").cost),"The actual click commits and charges the selected class exactly once")
	check(int(game.units[0].id)!=enemy_id and int(game.units[0].id)==original_id+1,"Enemies spawning during preview cannot collide with the committed friendly id")
	check(game.recruits==1 and game.pending.is_empty() and game.selected_id==int(game.units[0].id),"Successful placement clears preview and selects the actual unit")
	check(count_action("deploy")==1 and count_action("recruit")==0,"The direct flow has one successful deployment event without a second purchase sound")
	var paid_gold: int=game.gold
	click(game,hint)
	check(game.units.size()==1 and game.gold==paid_gold and count_action("deploy")==1,"A repeated click selects the existing unit instead of paying twice")
	var selected: int=game.selected_id
	check(game.begin_placement("archer") and game.selected_id==selected,"Preview does not discard the selected deployed unit")
	click(game,game.units[0].position)
	check(not game.pending.is_empty() and game.units.size()==1 and game.gold==paid_gold,"Clicking an occupied unit during placement rejects overlap and keeps the preview")
	click(game,hint,MOUSE_BUTTON_RIGHT)
	check(game.pending.is_empty() and game.gold==paid_gold and not game.placement_cursor_visible,"Right-click cancels with zero cost and removes ghost")
	check(game.begin_placement("spear"),"Ground preview can begin after cancellation")
	hint=first_hint(game)
	var ground_zone: Dictionary=game._eligible_zone(hint,"spear")
	var raw: Vector2=hint+Vector2(0,.01)
	if game._eligible_zone(raw,"spear").is_empty(): raw=hint
	preview=game.placement_preview(raw)
	check(bool(preview.valid) and game._point(preview.position).distance_to(game._placement_position(raw,ground_zone))<.00002,"Ground ghost uses the actual route-projected deployment point")
	var motion: InputEventMouseMotion=InputEventMouseMotion.new()
	motion.position=game._screen(raw)
	game._input(motion)
	check(game.placement_cursor.distance_to(raw)<.00002,"Mouse event coordinates drive the visible world cursor")
	var toolbar: Control=Control.new()
	toolbar.position=Vector2(0,720)
	toolbar.size=Vector2(1280,80)
	toolbar.mouse_filter=Control.MOUSE_FILTER_STOP
	root.add_child(toolbar)
	var toolbar_motion: InputEventMouseMotion=InputEventMouseMotion.new()
	toolbar_motion.position=Vector2(600,760)
	Input.parse_input_event(toolbar_motion)
	Input.flush_buffered_events()
	await process_frame
	check(not game.placement_cursor_visible and not bool(game.placement_preview(raw).visible),"Native motion over a STOP toolbar still removes the world ghost before GUI consumption")
	toolbar.free()
	var field_motion: InputEventMouseMotion=InputEventMouseMotion.new()
	field_motion.position=game._screen(raw)
	Input.parse_input_event(field_motion)
	Input.flush_buffered_events()
	await process_frame
	check(game.placement_cursor_visible and game.placement_cursor.distance_to(raw)<.00002,"Native motion returning to the field restores the correct cursor")
	game.paused=true
	click(game,raw)
	check(game.units.size()==2 and game.units[-1].position.distance_to(game._point(preview.position))<.00002,"Paused placement commits exactly where the ghost stood")
	paid_gold=game.gold
	game.gold=1000
	check(game.begin_placement("spear"),"A subsequent preview remains affordable")
	var escape: InputEventKey=InputEventKey.new()
	escape.pressed=true;escape.keycode=KEY_ESCAPE
	game._unhandled_input(escape)
	check(game.pending.is_empty() and game.gold==1000,"Escape cancels at zero cost")
	check(game.recruit("spear"),"Legacy direct recruitment keeps its prepayment contract")
	var legacy_paid: int=int(game.pending.paid)
	var before_switch: int=game.gold
	check(game.begin_placement("archer"),"An old paid pending can safely switch to an unpaid direct preview")
	check(game.gold==before_switch+legacy_paid and int(game.pending.paid)==0,"Legacy reservation is refunded exactly once during preview conversion")
	game.cancel_recruit();game.cancel_recruit()
	check(game.gold==before_switch+legacy_paid,"Canceling twice cannot duplicate the old refund")
	game.finished=true
	check(not game.begin_placement("spear") and game.pending.is_empty(),"Finished battles cannot reopen placement")
	game.free()
	var report: Dictionary={"checks":checks,"failures":failures,"scope":"Actual game click and motion events, unpaid preview/paid commit boundaries, repeated selections, blocked input, lock/invalid/NaN/INF guards, post-preview budget changes, spawn-time id ownership, occupied-click behavior, road snap, pause placement, right-click/Escape and legacy reservation conversion. Whole-map and Main toolbar integration is independently verified."}
	var path: String="user://qa_placement_preview.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_placement_preview.json"
	var output=FileAccess.open(path,FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
	print("PLACEMENT_PREVIEW_QA ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
