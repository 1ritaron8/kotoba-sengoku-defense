extends Control
## Independent drill controller. It reads account state and never awards campaign rewards.
signal completed(unit_id: String)
signal closed

const Battle = preload("res://native/game.gd")
const Troops3D = preload("res://native/troops_3d.gd")
const PaintedStage = preload("res://native/painted_stage.gd")
const CombatFeedback = preload("res://native/combat_feedback.gd")
const BattleAudio = preload("res://native/battle_audio.gd")
const RubyText = preload("res://native/ruby_label.gd")
const UnitPreview = preload("res://native/barracks_portrait.gd")
const UIStyle = preload("res://native/sengoku_ui.gd")
const UIPresentation = preload("res://native/battlefield_hud.gd")
const GameFonts = preload("res://native/game_fonts.gd")
const TRAINING_LIMIT_SECONDS: float = 75.0
const UNIT_ORDER: Array = ["archer","spear","samurai","gunner","monk","commander","ninja"]
const LESSONS: Dictionary = {
	"archer":{"titleKo":"사격 진지에 궁병 배치","deployKo":"빈자리가 있는 사격 진지를 클릭해 궁병을 배치하십시오.","attackKo":"배치한 궁병의 화살이 연습 적에게 명중하도록 지키십시오.","useKo":"고정된 진지에서 적 경로를 향해 화살을 쏩니다."},
	"spear":{"titleKo":"기지에서 창병 출진","deployKo":"출진을 누르면 창병이 아군 기지에서 출발합니다.","attackKo":"창병이 전진해 연습 적을 창으로 공격하는 모습을 확인하십시오.","useKo":"아군 기지에서 적의 진입구를 향해 전진하며 가까운 적과 교전합니다."},
	"samurai":{"titleKo":"사무라이의 전진과 교전","deployKo":"출진을 눌러 사무라이를 기지에서 내보내십시오.","attackKo":"사무라이가 적에게 접근해 칼을 명중하도록 지키십시오.","useKo":"기지에서 전진해 근접 교전을 이어갑니다."},
	"gunner":{"titleKo":"조총병 배치 연습","deployKo":"표시된 배치 지점을 클릭해 조총병을 배치하십시오.","attackKo":"제자리에 선 조총병의 탄환이 가까운 연습 적에게 명중하도록 지키십시오.","useKo":"적 경로 가까이에 배치하고 제자리에서 화승총을 쏩니다."},
	"naginata":{"titleKo":"성벽·사격 진지 호위","deployKo":"청록색 진지 주변에 장도병을 배치하십시오.","attackKo":"장도병이 방어 구역 안에서 기지 공격자를 저지하고 칼날을 명중하는지 확인하십시오.","useKo":"타워 방어 구역 안에서 기지 공격자를 막고 표적을 잃으면 배치 지점으로 복귀합니다."},
	"monk":{"titleKo":"승병의 아군 치료","deployKo":"청록색 지원 지점에 승병을 배치하십시오.","attackKo":"부상 연습병의 체력이 승병의 실제 치료로 회복되는지 확인하십시오.","useKo":"공격 대신 부상 아군을 치료합니다. 진언 지원 스킬은 영구 Lv.3·5·8에서 열립니다."},
	"commander":{"titleKo":"기마 무장의 기지 출진","deployKo":"출진을 눌러 기마 무장을 기지에서 내보내십시오.","attackKo":"말을 탄 무장이 전진해 연습 적과 교전하는 모습을 확인하십시오.","useKo":"기지에서 출진해 빠르게 전진하고 가까운 적과 교전합니다."},
	"ninja":{"titleKo":"소모성 닌자의 타워 진지 암살","deployKo":"표시한 적 타워 진지에 접근할 수 있는 보라색 엄폐 지점에 닌자를 배치하십시오.","attackKo":"적 타워형 진지의 실제 피해와 파괴, 닌자의 임무 완료 후 소모를 확인하십시오. 자동 표적을 사용하거나 진지를 클릭해 명령할 수 있습니다.","useKo":"적 고정 타워형 진지를 공격합니다. 임무 종료·표적 소멸·접근 불가·대상 부재 시 퇴장하며 재사용하거나 환불받을 수 없습니다."}
}

class GuideLayer extends Control:
	var markers: Array = []
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for marker in markers:
			var point: Vector2 = Vector2(float(marker.x),float(marker.y))*size
			var tint: Color = Color(str(marker.get("color","e0c688")))
			draw_arc(point,22.0,0,TAU,32,tint,2.0,true)
			draw_line(point+Vector2(-29,0),point+Vector2(-20,0),tint,2.0,true)
			draw_line(point+Vector2(20,0),point+Vector2(29,0),tint,2.0,true)

var progress: RefCounted
var maps: Array = []
var font: Font
var render_enabled: bool = true
var battle: Node2D
var troop_renderer: Control
var feedback: Node2D
var audio: Node
var view: String = "closed"
var phase: String = "closed"
var unit_id: String = ""
var source_stage: Dictionary = {}
var catalog: Array = []
var field_clip: Control
var guide: GuideLayer
var header: Label
var goal_label: Label
var hint_label: Label
var observation_label: Label
var action_button: Button
var order_button: Button
var retry_button: Button
var menu_button: Button
var footer_box: HBoxContainer
var footer_hint: Label
var session_completed: Dictionary = {}
var observations: Dictionary = {}
var error_ko: String = ""
var elapsed_seconds: float = 0.0
var actor_id: int = -1
var recommended: Vector2 = Vector2(-1,-1)
var route_index: int = 0
var _first_position: Vector2 = Vector2.ZERO
var _first_distance: float = 0.0
var _target_ids: Array = []
var _fort_target: Dictionary = {}
var _fort_initial_hp: float = 0.0
var _patient: Dictionary = {}
var _patient_initial_hp: float = 0.0
var _completion_sent: bool = false
var _open: bool = false

func _ready() -> void:
	theme = GameFonts.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 1800
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()
	set_process(false)

func configure(account: RefCounted, stage_maps: Array, face: Font) -> void:
	if progress!=account:
		session_completed.clear()
	progress=account
	maps=stage_maps.duplicate(true)
	font=face if face!=null else GameFonts.body()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json"))
	catalog=parsed.get("units",[]) if parsed is Dictionary else []
	if view=="menu":
		_build_menu()

func _definition(id: String) -> Dictionary:
	for entry in catalog:
		if str(entry.id)==id:
			return entry
	return {}

func _unlocked(id: String) -> bool:
	var definition: Dictionary = _definition(id)
	return not definition.is_empty() and bool(definition.get("active",true)) and (progress==null or id in progress.unlocked_units())

func _trained(id: String) -> bool:
	if progress!=null and progress.has_method("is_unit_trained"):
		return bool(progress.is_unit_trained(id)) or bool(session_completed.get(id,false))
	return bool(session_completed.get(id,false))

func open_menu(focused_unit: String = "") -> void:
	_dispose_battle()
	unit_id=focused_unit
	view="menu"
	phase="menu"
	error_ko=""
	_open=true
	show()
	set_process(false)
	_build_menu()

func open(id: String, stage: Dictionary) -> bool:
	if catalog.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json"))
		catalog=parsed.get("units",[]) if parsed is Dictionary else []
	if not LESSONS.has(id) or not _unlocked(id):
		error_ko="아직 해금되지 않은 병종입니다."
		return false
	if stage.is_empty() or not stage.get("paths") is Array or stage.paths.is_empty() or not stage.get("objectives") is Array or stage.objectives.is_empty():
		error_ko="연무에 사용할 전장의 경로를 확인할 수 없습니다."
		return false
	_dispose_battle()
	unit_id=id
	var use_3d: bool = bool(ProjectSettings.get_setting("application/config/use_3d_units",false))
	source_stage=stage.duplicate(true) if use_3d else PaintedStage.apply(stage)
	view="training"
	phase="ready"
	_open=true
	error_ko=""
	elapsed_seconds=0.0
	actor_id=-1
	_completion_sent=false
	_target_ids.clear()
	_fort_target.clear()
	_fort_initial_hp=0.0
	_patient.clear()
	_patient_initial_hp=0.0
	observations={"deployments":0,"shots":0,"hits":0,"damage":0.0,"heals":0,"healingAmount":0.0,"kills":0,"orders":0,"chargeImpacts":0,"distanceAdvanced":0.0,"returnObserved":false,"fortDamage":0.0,"fortDestroyed":false,"fortHits":0,"missionObserved":false,"missionTargetId":-1,"consumptionObserved":false,"consumeReason":"","consumedTargetId":-1,"unitFallen":false,"invalidPlacements":0,"trainingOnly":true}
	_build_training()
	var runtime: Dictionary = source_stage.duplicate(true)
	runtime["trainingOnly"]=true
	battle=Battle.new()
	var allow_render: bool = render_enabled and DisplayServer.get_name()!="headless"
	battle.three_d_enabled=allow_render and use_3d
	battle.name="IndependentTrainingBattle"
	battle.input_enabled=true
	battle.external_combat_feedback=true
	battle.external_placement_ghost=true
	field_clip.add_child(battle)
	battle.set_process(false)
	battle.set_process_input(false)
	battle.set_process_unhandled_input(false)
	# Read the real unlocks so a late ninja drill retains the existing enemy
	# emplacement rules. A null account is an isolated, fully available drill.
	var drill_roster: Array=progress.unlocked_units() if progress!=null else UNIT_ORDER
	battle.configure_roster(catalog,drill_roster,{id:1})
	# This isolated drill deliberately rehearses level 1. Fund the exact cost
	# of that runtime roster, including shared recruitment rules.
	runtime["initialGold"]=battle.recruit_cost(id)
	battle.load_map(runtime,0)
	battle.set_seed(3167)
	battle.ui_font=font
	battle.set_floating_label_style(UIStyle.floating_label_style())
	if not battle.three_d_enabled: battle.painted_field.attach_to(battle)
	battle.game_event.connect(_observe_event)
	if battle.actor_overlay!=null:
		battle.actor_overlay.z_as_relative=true
		battle.actor_overlay.z_index=3
	if battle.three_d_enabled:
		troop_renderer=Troops3D.new()
		troop_renderer.battle=battle
		field_clip.add_child(troop_renderer)
		troop_renderer.z_index=0
		troop_renderer.visible=battle.three_d_enabled
		troop_renderer.set_stage(runtime)
		battle.three_d_actor_scale=troop_renderer.actor_base_scale()
		if troop_renderer.side_overlay!=null:
			troop_renderer.side_overlay.z_as_relative=true
			troop_renderer.side_overlay.z_index=2
	if allow_render:
		feedback=CombatFeedback.new()
		feedback.battle=battle
		feedback.troop_renderer=troop_renderer
		feedback.font=font
		field_clip.add_child(feedback)
		feedback.z_index=4
		audio=BattleAudio.new()
		field_clip.add_child(audio)
		audio.setup(true)
		field_clip.move_child(battle,field_clip.get_child_count()-1)
	# The field guide and HUD stay above the projected battlefield.
	field_clip.move_child(guide,field_clip.get_child_count()-1)
	guide.z_index=8
	_layout_field()
	_choose_recommended_position()
	_refresh_ui()
	show()
	set_process(true)
	return true

func _dispose_battle() -> void:
	if is_instance_valid(audio):
		audio.shutdown()
	if is_instance_valid(battle):
		battle.running=false
		battle.input_enabled=false
		battle.set_process(false)
	if is_instance_valid(troop_renderer):
		troop_renderer.set_process(false)
	battle=null
	troop_renderer=null
	feedback=null
	audio=null
	field_clip=null
	guide=null
	_clear_ui()

func _clear_ui() -> void:
	for child in get_children():
		if child is CanvasItem:
			child.hide()
		child.queue_free()

func close() -> void:
	if not _open:
		return
	_open=false
	_dispose_battle()
	view="closed"
	phase="closed"
	hide()
	set_process(false)
	closed.emit()

func retry() -> bool:
	if view!="training" or source_stage.is_empty():
		return false
	var stage: Dictionary=source_stage.duplicate(true)
	return open(unit_id,stage)

func _practice_map(id: String) -> Dictionary:
	if maps.is_empty():
		return {}
	var threshold: int=int(_definition(id).get("unlockClears",0))
	return maps[clampi(threshold,0,maps.size()-1)]

func practice_available(id: String) -> bool:
	var stage: Dictionary=_practice_map(id)
	return _unlocked(id) and stage.get("paths") is Array and not stage.paths.is_empty() and stage.get("objectives") is Array and not stage.objectives.is_empty()

func _enter_from_menu(id: String) -> void:
	if not open(id,_practice_map(id)):
		if hint_label!=null:
			hint_label.text=error_ko

func _label(parent: Node, text: String, points: int = 20, color: String = UIStyle.TEXT) -> Label:
	var label: Label=UIStyle.TooltipLabel.new()
	label.text=text
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x=1
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",GameFonts.heading() if points>=26 else GameFonts.body())
	label.add_theme_font_size_override("font_size",maxi(20,points))
	label.add_theme_color_override("font_color",Color(color))
	label.add_theme_color_override("font_shadow_color",Color("100d0bb3"))
	label.add_theme_constant_override("shadow_offset_y",1)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button: Button=UIStyle.TooltipButton.new()
	button.text=text
	button.custom_minimum_size=Vector2(0,48)
	UIPresentation.apply_button(button)
	button.add_theme_font_override("font",GameFonts.body())
	button.add_theme_font_size_override("font_size",22)
	button.pressed.connect(callback)
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	return button

func _shell() -> VBoxContainer:
	_clear_ui()
	var background: TextureRect=TextureRect.new()
	background.name="TrainingWarroom"
	background.texture=_warroom_texture()
	background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade: ColorRect=ColorRect.new()
	shade.name="TrainingBackdropShade"
	shade.color=Color("14181996")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(shade)
	var margin: MarginContainer=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+edge,24)
	add_child(margin)
	var stack: VBoxContainer=VBoxContainer.new()
	stack.add_theme_constant_override("separation",16)
	margin.add_child(stack)
	return stack

func _warroom_texture() -> Texture2D:
	var path: String="res://assets/ui/barracks-warroom.png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var image: Image=Image.load_from_file(path)
	return null if image==null or image.is_empty() else ImageTexture.create_from_image(image)

func _build_menu() -> void:
	var shell: VBoxContainer=_shell()
	var heading: HBoxContainer=HBoxContainer.new()
	heading.add_theme_constant_override("separation",18)
	shell.add_child(heading)
	var title: Label=_label(heading,"鍛錬",36,UIStyle.TEXT)
	title.name="TrainingTitle"
	title.add_theme_font_override("font",GameFonts.japanese())
	title.custom_minimum_size.x=120
	var subtitle: Label=_label(heading,"병종 연습 · 병종 연무",22,UIStyle.MUTED)
	subtitle.name="TrainingSubtitle"
	subtitle.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	subtitle.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	_label(shell,"참가비 무료. 익숙한 전장에서 병종별 배치와 출진을 연습하십시오.",20)
	var scroller: ScrollContainer=ScrollContainer.new()
	scroller.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroller)
	var grid: GridContainer=GridContainer.new()
	grid.columns=4 if get_viewport_rect().size.x>=1150 else 2
	grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",14)
	grid.add_theme_constant_override("v_separation",14)
	scroller.add_child(grid)
	for id in UNIT_ORDER:
		var definition: Dictionary=_definition(id)
		if definition.is_empty() or not bool(definition.get("active",true)):
			continue
		var available: bool=_unlocked(id)
		var can_enter: bool=practice_available(id)
		var card: PanelContainer=PanelContainer.new()
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.custom_minimum_size=Vector2(245,0)
		card.name="TrainingCard_"+str(id)
		card.add_theme_stylebox_override("panel",UIStyle.textured_panel("ink"))
		grid.add_child(card)
		var column: VBoxContainer=VBoxContainer.new()
		column.add_theme_constant_override("separation",8)
		card.add_child(column)
		var thumbnail: Control=UnitPreview.new()
		thumbnail.name="TrainingUnitPreview_"+str(id)
		thumbnail.custom_minimum_size=Vector2(1,118)
		thumbnail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		thumbnail.configure(str(id),0,available)
		column.add_child(thumbnail)
		var ruby: Control=RubyText.new()
		ruby.font=GameFonts.japanese()
		ruby.reading_font=GameFonts.reading()
		ruby.meaning_font=GameFonts.body()
		ruby.set_word({"jp":definition.get("jp",""),"reading":definition.get("reading",""),"ko":definition.get("name",""),"parts":definition.get("parts",[])},30,true)
		column.add_child(ruby)
		var badge: String="수련 완료" if _trained(id) else "첫 연무" if available else "%d개 전투 완수 후 해금" % int(definition.get("unlockClears",0))
		_label(column,badge,20,"acd0af" if _trained(id) else UIStyle.BLUE if available else UIStyle.MUTED)
		_label(column,str(LESSONS[id].useKo),20,UIStyle.TEXT)
		var enter: Button=_button(column,"연무 입장" if can_enter else "새 전장 준비 중" if available else "미해금",func(): _enter_from_menu(str(id)))
		enter.disabled=not can_enter
		if available and not can_enter: enter.tooltip_text="새 전장이 준비되면 연습할 수 있습니다."
		enter.set_meta("trainingUnit",str(id))
	hint_label=_label(shell,error_ko,20,"d8b889")
	var footer: HBoxContainer=HBoxContainer.new()
	footer_box=footer
	footer.custom_minimum_size.y=52
	footer.size_flags_vertical=Control.SIZE_FILL
	footer.add_theme_constant_override("separation",18)
	shell.add_child(footer)
	_button(footer,"뒤로",close)
	footer_hint=_label(footer,"새 전장이 준비되면 연습할 수 있습니다." if maps.is_empty() else "언제든 다시 연습할 수 있습니다.",20,UIStyle.MUTED)
	footer_hint.autowrap_mode=TextServer.AUTOWRAP_OFF
	footer_hint.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer_hint.size_flags_vertical=Control.SIZE_SHRINK_CENTER

func _build_training() -> void:
	var shell: VBoxContainer=_shell()
	var head: HBoxContainer=HBoxContainer.new()
	shell.add_child(head)
	header=_label(head,"鍛錬 · "+str(_definition(unit_id).get("name",""))+" 연무",30,UIStyle.TEXT)
	header.name="TrainingPracticeTitle"
	header.tooltip_text="たんれん · 병종 연무"
	header.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(head,"훈련 목록",func(): open_menu(unit_id))
	_button(head,"뒤로",close)
	_label(shell,"연무 전장 · "+str(source_stage.get("title","전장"))+"   /   전투 연습",20,UIStyle.MUTED)
	var body: HBoxContainer=HBoxContainer.new()
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",18)
	shell.add_child(body)
	field_clip=Control.new()
	field_clip.custom_minimum_size=Vector2(240,300)
	field_clip.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	field_clip.size_flags_vertical=Control.SIZE_EXPAND_FILL
	field_clip.clip_contents=true
	field_clip.mouse_filter=Control.MOUSE_FILTER_STOP
	field_clip.gui_input.connect(_field_input)
	field_clip.mouse_exited.connect(func():
		if is_instance_valid(battle):
			battle.placement_cursor_visible=false
			battle.queue_redraw()
	)
	field_clip.resized.connect(_layout_field)
	body.add_child(field_clip)
	guide=GuideLayer.new()
	guide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	field_clip.add_child(guide)
	var panel: PanelContainer=PanelContainer.new()
	panel.name="TrainingInstructionPanel"
	panel.custom_minimum_size=Vector2(280,0)
	panel.add_theme_stylebox_override("panel",UIStyle.textured_panel("ink"))
	body.add_child(panel)
	var column: VBoxContainer=VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	panel.add_child(column)
	var definition: Dictionary=_definition(unit_id)
	var ruby: Control=RubyText.new()
	ruby.font=GameFonts.japanese()
	ruby.reading_font=GameFonts.reading()
	ruby.meaning_font=GameFonts.body()
	ruby.set_word({"jp":definition.jp,"reading":definition.reading,"ko":definition.name,"parts":definition.get("parts",[])},34,true)
	column.add_child(ruby)
	goal_label=_label(column,"",22,UIStyle.TEXT)
	goal_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hint_label=_label(column,"",20)
	observation_label=_label(column,"",20,UIStyle.MUTED)
	var spacer: Control=Control.new()
	spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	retry_button=_button(column,"다시 연습",func(): retry())
	menu_button=_button(column,"목록으로",func(): open_menu(unit_id))
	var footer: HBoxContainer=HBoxContainer.new()
	footer_box=footer
	footer.custom_minimum_size.y=52
	footer.size_flags_vertical=Control.SIZE_FILL
	footer.add_theme_constant_override("separation",18)
	shell.add_child(footer)
	action_button=_button(footer,"",func(): deploy())
	action_button.custom_minimum_size.x=240
	order_button=_button(footer,"표시한 진지 암살",func(): issue_assassination())
	order_button.visible=unit_id=="ninja"
	footer_hint=_label(footer,"배치/출진 [R]    ·    전장 클릭    ·    뒤로 [Esc]",20,UIStyle.MUTED)
	footer_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	footer_hint.custom_minimum_size.x=1
	footer_hint.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer_hint.size_flags_vertical=Control.SIZE_SHRINK_CENTER

func _layout_field() -> void:
	if not is_instance_valid(battle) or field_clip==null:
		return
	var field_size: Vector2=Vector2(maxf(2,field_clip.size.x),maxf(2,field_clip.size.y))
	battle.position=Vector2.ZERO
	battle.set_field_rect(Rect2(Vector2.ZERO,field_size))
	if is_instance_valid(troop_renderer):
		troop_renderer.position=Vector2.ZERO
		troop_renderer.set_field_size(field_size)
	if is_instance_valid(audio):
		audio.set_field_rect(Rect2(Vector2.ZERO,field_size))

func _choose_recommended_position() -> void:
	recommended=Vector2(-1,-1)
	route_index=0
	if str(battle.placement_contract(unit_id).deploymentKind)=="marching":
		var bases: Array=battle.snapshot().get("marchBases",[])
		if not bases.is_empty():
			route_index=int(bases[0].pathIndex)
			recommended=Vector2(float(bases[0].x),float(bases[0].y))
		_refresh_guide()
		return
	var best_score: float=INF
	for zone in battle.zones:
		if str(zone.get("placementRole",""))!=str(battle.placement_contract(unit_id).placementRole):
			continue
		var candidate: Vector2=battle._zone_placement_hint(zone,unit_id)
		if candidate.x<0:
			continue
		var nearest: Dictionary=_nearest_route(candidate,int(zone.get("pathIndex",-1)))
		if nearest.is_empty():
			continue
		var score: float=float(nearest.gap)
		if unit_id=="ninja":
			var fort: Dictionary=battle._fortification_position(int(nearest.pathIndex))
			if fort.is_empty():
				continue
			score=candidate.distance_to(fort.position)
		if score<best_score:
			best_score=score
			recommended=candidate
			route_index=int(nearest.pathIndex)
	_refresh_guide()

func _nearest_route(point: Vector2, required_path: int = -1) -> Dictionary:
	var result: Dictionary={}
	var best: float=INF
	for path_index in range(battle.paths.size()):
		if required_path>=0 and required_path!=path_index:
			continue
		var safe: Dictionary=battle.ground_combat._base_for_path(path_index)
		if safe.is_empty():
			continue
		var points: Array=battle.paths[path_index].points
		for segment in range(points.size()-1):
			var nearest: Vector2=Geometry2D.get_closest_point_to_segment(point,points[segment],points[segment+1])
			var distance: float=battle.ground_combat.point_distance(path_index,segment,nearest)
			if distance<float(safe.routeMin)+.006 or distance>float(safe.routeMax):
				continue
			var gap: float=point.distance_to(nearest)
			if gap<best:
				best=gap
				result={"pathIndex":path_index,"distance":distance,"position":nearest,"gap":gap,"routeMin":float(safe.routeMin),"routeMax":float(safe.routeMax)}
	return result

func _refresh_guide() -> void:
	if guide==null:
		return
	guide.markers.clear()
	if actor_id<0 and recommended.x>=0:
		var color: String="b997ff" if unit_id=="ninja" else "73e5d2" if unit_id in ["monk","gunner"] else "e0c688" if unit_id=="archer" else "67c6ff"
		var point: Vector2=battle.view_point(recommended)
		guide.markers.append({"x":point.x,"y":point.y,"color":color})
	if not _fort_target.is_empty() and not bool(observations.get("fortDestroyed",false)):
		var point: Vector2=battle.view_point(_point(_fort_target.get("position",{})))
		guide.markers.append({"x":point.x,"y":point.y,"color":"ff6472"})
	guide.queue_redraw()

func _point(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x",0)),float(value.get("y",0)))
	return Vector2.ZERO

func deploy() -> bool:
	if view!="training" or phase not in ["ready","placing"] or not is_instance_valid(battle):
		return false
	if not battle.pending.is_empty():
		return true
	var success: bool=battle.begin_placement(unit_id,route_index)
	if not success:
		error_ko="병력을 준비하지 못했습니다. 다시 연습을 눌러 시작하십시오."
		_refresh_ui()
		return false
	if battle.pending.is_empty():
		_adopt_deployed_actor()
	else:
		phase="placing"
		if recommended.x>=0:
			battle.placement_cursor=recommended
			battle.placement_cursor_visible=true
		error_ko=""
		_refresh_ui()
	return true

func place_at(point: Vector2) -> bool:
	if phase!="placing" or not is_instance_valid(battle):
		return false
	var preview: Dictionary=battle.placement_preview(point)
	if not bool(preview.get("valid",false)):
		observations.invalidPlacements=int(observations.invalidPlacements)+1
		error_ko=str(preview.get("reason","해당 병종의 배치 지점을 선택하십시오."))
		_refresh_ui()
		return false
	if not battle.place_unit(point.x,point.y):
		return false
	# The consumable actor must find its canonical mission on its first step.
	# Create the existing fort encounter after payment, before production runs.
	if unit_id=="ninja":
		_prepare_fort_challenge()
		if phase=="failed": return true
	_adopt_deployed_actor()
	return true

func _adopt_deployed_actor() -> void:
	for unit in battle.units:
		if str(unit.type)==unit_id:
			actor_id=int(unit.id)
			_first_position=unit.position
			_first_distance=float(unit.get("routeDistance",0))
			route_index=int(unit.get("postPathIndex",route_index))
			break
	if actor_id<0:
		if not battle.snapshot().get("recruitmentQueue",[]).is_empty():
			phase="producing"
			_start_practice_clock()
			_refresh_ui()
		else:
			_fail("배치한 병력을 확인하지 못했습니다.")
		return
	phase="combat"
	error_ko=""
	_start_practice_clock()
	if unit_id=="ninja":
		_prepare_fort_challenge()
	elif unit_id=="monk":
		_prepare_heal_challenge()
	else:
		_prepare_enemy_challenge()
	_refresh_guide()
	_refresh_ui()

func _start_practice_clock() -> void:
	battle.wave=1
	battle.running=true
	battle.paused=false
	battle.between_waves=false
	battle.spawn_queue=["raider"]
	battle.spawn_source_waves=[1]
	battle.spawn_metadata=[{}]
	battle.spawn_clock=3600.0

func _prepare_heal_challenge() -> void:
	var source: Dictionary = _actor()
	var patient_position: Vector2 = source.position
	for offset in [Vector2(.023,0),Vector2(-.023,0),Vector2(0,.023),Vector2(0,-.023)]:
		var candidate: Vector2 = source.position+offset
		if battle.ground_combat.land_segment_safe(source.position,candidate,0.0):
			patient_position = candidate
			break
	# An injured ordinary ally belongs only to this free practice encounter.
	# Recovery uses the same live UnitSkills HP/event path as campaign combat.
	var definition: Dictionary = _definition("archer")
	_patient={"id":battle.next_id,"type":"archer","name":"부상 연습병","campaignLevel":1,"evolution":0,"definition":definition.duplicate(true),"paid":0,"position":patient_position,"cooldown":3600.0,"aim":Vector2.LEFT,"animation":"idle","animationClock":0.0,"animationPhase":0.0,"deploying":false,"attackPlan":{},"pulseClock":0.0,"hitClock":0.0}
	battle.next_id+=1
	battle.ground_combat.initialize_unit(_patient,{"position":patient_position,"pathIndex":route_index,"id":"practice-patient","elevation":0})
	battle.unit_skills.initialize_unit(_patient)
	_patient_initial_hp = minf(30,float(_patient.maxHp)*.35)
	_patient.hp = _patient_initial_hp
	battle.units.append(_patient)
	observations["patientActorId"]=int(_patient.id)
	observations["patientHealthBefore"]=_patient_initial_hp

func _actor() -> Dictionary:
	if not is_instance_valid(battle):
		return {}
	for unit in battle.units:
		if int(unit.id)==actor_id:
			return unit
	return {}

func _prepare_enemy_challenge() -> void:
	var unit: Dictionary=_actor()
	var where: Dictionary=_nearest_route(unit.position,int(unit.get("postPathIndex",-1)))
	if where.is_empty():
		_fail("해당 진지에서 연습할 육지 경로가 없습니다. 다른 표시 지점을 선택하십시오.")
		return
	route_index=int(where.pathIndex)
	var distance: float=float(where.distance)-.07
	if unit_id=="monk":
		distance=float(where.distance)-minf(.03,float(battle.ground_combat.reach(unit))*.75)
	if str(battle.placement_contract(unit_id).deploymentKind)=="marching":
		distance=float(unit.routeDistance)-.16
	distance=clampf(distance,float(where.routeMin)+.01,float(where.routeMax)-.01)
	if unit_id in ["gunner","naginata"]:
		var chosen: bool = false
		for candidate_distance in [distance,float(where.distance)-.045,float(where.distance)-.025,float(where.distance)-.012,float(where.distance)+.025,float(where.distance)+.045,float(where.distance)]:
			var actual_distance: float = clampf(float(candidate_distance),float(where.routeMin)+.002,float(where.routeMax)-.002)
			var candidate: Vector2 = battle.ground_combat.route_point(route_index,actual_distance)
			if battle.ground_combat.land_segment_safe(unit.position,candidate):
				distance = actual_distance
				chosen = true
				break
		if not chosen:
			_fail("이 진지의 같은 둑에 연습 적을 놓을 수 없습니다. 다른 표시 지점을 선택하십시오.")
			return
	if unit_id=="naginata": battle._spawn_enemy("enemy_samurai",1,{"pathIndex":route_index})
	else: battle._spawn_enemy("raider",1)
	var enemy: Dictionary=battle.enemies[-1]
	enemy["pathIndex"]=route_index
	enemy["position"]=battle.ground_combat.route_point(route_index,distance)
	enemy["reward"]=0
	# A practice opponent waits on the authored road. Real hit/counterattack
	# rules still apply; escort AI cannot pull it away toward a moving cart.
	enemy["stationaryEnemy"]=true
	var cumulative: Array=battle.ground_combat.cumulative[route_index]
	for index in range(1,cumulative.size()):
		if distance<float(cumulative[index])-.0000001:
			enemy["pointIndex"]=index
			break
	_target_ids.append(int(enemy.id))

func _prepare_fort_challenge() -> void:
	if not _fort_target.is_empty(): return
	# The fixture uses the engine's ordinary fort HP, armor and attack rules.
	# Some campaign maps choose a route by wave/bridge; align only this spawn.
	var previous_wave: int=battle.wave
	var previous_bridge: int=battle.bridge_index
	battle.wave=route_index+1
	battle.bridge_index=route_index
	_fort_target=battle._spawn_enemy("enemy_archer",1,{"fortification":true,"pathIndex":route_index})
	battle.wave=previous_wave
	battle.bridge_index=previous_bridge
	if not battle.ground_combat.is_tower_attacker(_fort_target):
		_fail("이 엄폐 지점에서 암살할 육지 진지가 없습니다. 다른 표시 지점에서 다시 연습하십시오.")
		return
	_fort_initial_hp=float(_fort_target.get("hp",0))
	_target_ids.append(int(_fort_target.id))
	_refresh_guide()

func issue_assassination(enemy_id: int = -1) -> Dictionary:
	if unit_id!="ninja" or phase!="combat" or not is_instance_valid(battle) or _fort_target.is_empty() or not battle.has_method("order_assassination"):
		return {"accepted":false,"reasonKo":"먼저 닌자를 보라색 엄폐 지점에 배치하십시오."}
	var target_id: int=int(_fort_target.get("id",-1)) if enemy_id<0 else enemy_id
	# The controller owns field input. Open the engine's command gate only for
	# this synchronous command, then restore it before any input is dispatched.
	var input_was_enabled: bool=battle.input_enabled
	battle.input_enabled=true
	var result: Dictionary=battle.order_assassination(target_id,actor_id)
	battle.input_enabled=input_was_enabled
	if bool(result.get("accepted",false)):
		error_ko=""
	else:
		error_ko=str(result.get("reasonKo","명령할 수 없는 진지입니다."))
	_refresh_ui()
	return result

func _field_input(event: InputEvent) -> void:
	if view!="training" or not is_instance_valid(battle):
		return
	if event is InputEventMouseMotion and phase=="placing":
		battle.placement_cursor=battle.model_point(event.position/field_clip.size)
		battle.placement_cursor_visible=true
		battle.queue_redraw()
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var point: Vector2=battle.model_point(event.position/field_clip.size)
		if phase=="placing":
			place_at(point)
		elif unit_id=="ninja" and phase=="combat" and not _fort_target.is_empty() and point.distance_to(_point(_fort_target.get("position",{})))<.085:
			issue_assassination()
		field_clip.accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if not _open or not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode==KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode==KEY_R and view=="training":
		deploy()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if view=="training" and phase in ["producing","combat"] and is_instance_valid(battle):
		advance_training(minf(maxf(0,delta),.25)*float(battle.effective_speed()))

func advance_training(delta: float) -> void:
	if not is_instance_valid(battle) or phase not in ["producing","combat"] or battle.paused or not is_finite(delta) or delta<=0:
		return
	var remaining: float=maxf(0,delta)
	while remaining>.0000001 and phase in ["producing","combat"]:
		var step: float=minf(.05,minf(remaining,TRAINING_LIMIT_SECONDS-elapsed_seconds))
		if step<=.0000001:
			_fail("아직 명중을 확인하지 못했습니다. 표시 지점과 적의 거리를 확인하고 다시 연습하십시오.")
			break
		elapsed_seconds+=step
		battle.advance_simulation(step)
		if phase=="producing" and not battle.units.is_empty():
			_adopt_deployed_actor()
		if phase=="combat":
			_observe_positions()
			_evaluate_completion()
		if is_instance_valid(battle) and battle.finished and phase=="combat":
			_fail("거점이 무너지기 전에 공격을 확인해야 합니다. 다시 연습하십시오.")
		remaining-=step
	if is_instance_valid(battle):
		battle.queue_redraw()
		if battle.actor_overlay!=null:
			battle.actor_overlay.queue_redraw()
	_refresh_ui()

func _observe_event(event: Dictionary) -> void:
	var same_unit: bool=str(event.get("unitType",""))==unit_id and str(event.get("side","friendly"))=="friendly"
	if same_unit and unit_id=="ninja" and str(event.get("type",""))=="placed" and actor_id<0:
		# The actor can complete its mission and disappear within this same
		# simulation step. Retain its authoritative production identity now.
		var produced: Array=event.get("actorIds",[])
		actor_id=int(produced[0]) if not produced.is_empty() else int(event.get("actorId",-1))
		_first_position=_point(event.get("position",{}))
		route_index=int(event.get("pathIndex",route_index))
		var actor: Dictionary=_actor()
		if not actor.is_empty():
			_first_position=actor.position
			_first_distance=float(actor.get("routeDistance",0))
		if phase=="producing" and actor_id>=0: phase="combat"
	var same_actor: bool=actor_id>=0 and int(event.get("actorId",-1))==actor_id
	if same_unit and same_actor and unit_id=="ninja":
		var target_id: int=int(_fort_target.get("id",-1))
		var victim_id: int=int(event.get("victimId",-2))
		match str(event.get("type","")):
			"assassination_ordered":
				observations.orders=int(observations.orders)+1
				if target_id>=0 and victim_id==target_id:
					observations.missionObserved=true
					observations.missionTargetId=target_id
			"shot","hit":
				if target_id>=0 and victim_id==target_id:
					observations.missionObserved=true
					observations.missionTargetId=target_id
					if str(event.type)=="hit" and float(event.get("damage",0))>0: observations.fortHits=int(observations.fortHits)+1
			"unit_consumed":
				observations.consumptionObserved=true
				observations.consumeReason=str(event.get("consumeReason",""))
				observations.consumedTargetId=int(event.get("targetId",-1))
			"unit_fallen": observations.unitFallen=true
	if same_unit:
		match str(event.get("type","")):
			"placed","recruited":
				if str(event.get("type",""))=="placed" or str(battle.placement_contract(unit_id).deploymentKind)=="marching":
					observations.deployments=int(observations.deployments)+1
			"shot":
				observations.shots=int(observations.shots)+1
			"hit":
				if float(event.get("damage",0))>0:
					observations.hits=int(observations.hits)+1
					observations.damage=float(observations.damage)+float(event.damage)
			"killed":
				observations.kills=int(observations.kills)+1
			"charge_impact":
				observations.chargeImpacts=int(observations.chargeImpacts)+1
			"heal":
				if float(event.get("healAmount",0))>0:
					observations.heals=int(observations.heals)+1
					observations.healingAmount=float(observations.healingAmount)+float(event.healAmount)
	if is_instance_valid(feedback):
		feedback.consume_event(event)
	if is_instance_valid(audio):
		audio.consume_event(event)

func _observe_positions() -> void:
	if unit_id=="ninja" and not _fort_target.is_empty():
		observations.fortDamage=maxf(float(observations.fortDamage),_fort_initial_hp-float(_fort_target.get("hp",_fort_initial_hp)))
		observations.fortDestroyed=float(_fort_target.get("hp",_fort_initial_hp))<=0 or bool(_fort_target.get("destroyed",false))
	var unit: Dictionary=_actor()
	if unit.is_empty():
		if unit_id=="ninja" and bool(observations.get("consumptionObserved",false)):
			if _ninja_mission_complete(): return
			var reasons: Dictionary={"no_target":"접근할 수 있는 적 타워 진지가 없어 닌자가 소모되었습니다.","target_lost":"암살 표적을 잃어 닌자가 소모되었습니다.","unreachable":"암살 경로가 막혀 닌자가 소모되었습니다.","target_defeated":"이 닌자의 실제 진지 타격과 파괴를 확인하지 못했습니다."}
			_fail(str(reasons.get(str(observations.get("consumeReason","")),"암살 임무를 완료하기 전에 닌자가 소모되었습니다."))+" 다시 연습하십시오.")
			return
		if unit_id=="ninja" and not bool(observations.get("unitFallen",false)):
			_fail("닌자의 실제 암살 임무와 퇴장을 확인하지 못했습니다. 다시 연습하십시오.")
			return
		_fail("연무 병력이 전사했습니다. 다시 연습해 배치와 교전을 익히십시오.")
		return
	observations.distanceAdvanced=maxf(float(observations.distanceAdvanced),_first_distance-float(unit.get("routeDistance",_first_distance)))
	if unit_id=="monk" and not _patient.is_empty():
		observations["patientHealth"]=float(_patient.get("hp",0))
	if unit_id=="ninja" and int(unit.get("priorityTargetId",-1))==int(_fort_target.get("id",-2)):
		observations.missionObserved=true
		observations.missionTargetId=int(unit.priorityTargetId)

func _ninja_mission_complete() -> bool:
	var target_id: int=int(_fort_target.get("id",-1))
	if target_id<0 or actor_id<0 or bool(observations.get("unitFallen",false)): return false
	if int(observations.get("fortHits",0))<=0 or float(observations.get("fortDamage",0))<=0 or not bool(observations.get("fortDestroyed",false)): return false
	if not bool(observations.get("missionObserved",false)) or int(observations.get("missionTargetId",-2))!=target_id: return false
	return bool(observations.get("consumptionObserved",false)) and str(observations.get("consumeReason",""))=="target_defeated" and int(observations.get("consumedTargetId",-2))==target_id

func _evaluate_completion() -> void:
	if phase!="combat" or actor_id<0:
		return
	var success: bool=int(observations.hits)>0 and float(observations.damage)>0
	if str(battle.placement_contract(unit_id).deploymentKind)=="marching":
		success=success and float(observations.distanceAdvanced)>.015
	if unit_id=="ninja":
		success=_ninja_mission_complete()
	elif unit_id=="monk":
		success=int(observations.heals)>=2 and float(observations.healingAmount)>=12.0 and float(observations.get("patientHealth",0))>_patient_initial_hp
	if not success:
		return
	phase="success"
	battle.running=false
	battle.paused=true
	session_completed[unit_id]=true
	if is_instance_valid(audio):
		audio.set_paused(true)
	if not _completion_sent:
		_completion_sent=true
		completed.emit(unit_id)
	_refresh_guide()

func _fail(reason: String) -> void:
	if phase in ["success","failed","closed","menu"]:
		return
	phase="failed"
	error_ko=reason
	if is_instance_valid(battle):
		battle.running=false
		battle.paused=true
	if is_instance_valid(audio):
		audio.set_paused(true)

func current_goal() -> Dictionary:
	var lesson: Dictionary=LESSONS.get(unit_id,{})
	var hint: String = "병영에서 병력을 생산 중입니다. 완료되면 지정한 위치로 나옵니다." if phase=="producing" else str(lesson.get("deployKo","")) if actor_id<0 else str(lesson.get("attackKo",""))
	return {"unitId":unit_id,"titleKo":lesson.get("titleKo","병종 연무"),"hintKo":hint,"step":1 if actor_id<0 else 2,"total":2,"completed":phase=="success","failed":phase=="failed","status":phase,"errorKo":error_ko}

func diagnostics() -> Dictionary:
	var result: Dictionary=observations.duplicate(true)
	result.merge({"view":view,"status":phase,"unitId":unit_id,"sourceStageId":str(source_stage.get("id","")),"elapsedSeconds":elapsed_seconds,"actorId":actor_id,"routeIndex":route_index,"recommended":recommended,"targetIds":_target_ids.duplicate(),"goal":current_goal(),"rendererActive":is_instance_valid(troop_renderer),"renderMode":"3d" if is_instance_valid(battle) and battle.three_d_enabled else "painted2d" if bool(source_stage.get("paintedPresentation",false)) else "legacy_flat2d","trainingOnly":true},true)
	return result

func _refresh_ui() -> void:
	if view!="training" or goal_label==null:
		return
	var goal: Dictionary=current_goal()
	var action: String="기지 출진" if is_instance_valid(battle) and str(battle.placement_contract(unit_id).deploymentKind)=="marching" else "엄폐 배치" if unit_id=="ninja" else "병력 배치"
	var step_name: String="생산 대기" if phase=="producing" else action if actor_id<0 else "암살과 소모" if unit_id=="ninja" else "아군 회복 확인" if unit_id=="monk" else "실제 명중 확인"
	goal_label.text="연무 완료" if phase=="success" else "다시 연습" if phase=="failed" else "%d / 2 · %s" % [int(goal.step),step_name]
	hint_label.text=error_ko if not error_ko.is_empty() else "배치와 실제 공격을 확인했습니다. 목록에서 다른 병종을 연습할 수 있습니다." if phase=="success" else str(goal.hintKo)
	var evidence: String="실제 명중 %d회 · 피해 %d" % [int(observations.get("hits",0)),roundi(float(observations.get("damage",0)))]
	if unit_id=="ninja":
		evidence="진지 피해 %d · 임무 완료 후 소모 %s" % [roundi(float(observations.get("fortDamage",0))),"확인" if _ninja_mission_complete() else "대기"]
	elif unit_id=="monk":
		evidence="실제 치료 %d회 · 회복 %d\n연습병 체력 %.0f → %.0f" % [int(observations.heals),roundi(float(observations.healingAmount)),_patient_initial_hp,float(observations.get("patientHealth",_patient_initial_hp))]
	if phase=="producing":
		var jobs: Array = battle.snapshot().get("recruitmentQueue",[])
		if not jobs.is_empty(): evidence="생산 완료까지 %.1f초" % float(jobs[0].remainingSeconds)
	observation_label.text=evidence+"\n연무 시간 %.1f초" % elapsed_seconds
	var marching: bool=is_instance_valid(battle) and str(battle.placement_contract(unit_id).deploymentKind)=="marching"
	action_button.text="출진 [R]" if marching else "배치 준비 [R]"
	action_button.disabled=phase not in ["ready","placing"] or phase=="placing"
	order_button.visible=unit_id=="ninja"
	order_button.disabled=phase!="combat" or _fort_target.is_empty()
	retry_button.visible=phase in ["success","failed"] or actor_id>=0
	menu_button.text="수련 마치고 목록으로" if phase=="success" else "목록으로"
