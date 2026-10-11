extends Node

const RubyText = preload("res://native/ruby_label.gd")
const RubyReadings = preload("res://native/ruby_readings.gd")
const ProgressStore = preload("res://native/progress.gd")
const Battle = preload("res://native/game.gd")
const FrontEnd = preload("res://native/front_end.gd")
const BattleAtmosphere = preload("res://native/battle_atmosphere.gd")
const Troops3D = preload("res://native/troops_3d.gd")
const DeploymentOverlay = preload("res://native/deployment_drag_overlay.gd")
const BattleCamera = preload("res://native/battle_camera.gd")
const NativeBattlefield = preload("res://native/battlefield_3d.gd")
const WorldAdapter = preload("res://native/battlefield_world_adapter.gd")
const RemasterVisuals = preload("res://native/remaster_visual_slice.gd")
const CatalogPreview = preload("res://native/battlefield_preview.gd")
const Barracks = preload("res://native/barracks.gd")
const UnitTraining = preload("res://native/unit_training.gd")
const LivePortrait = preload("res://native/barracks_portrait.gd")
const UIStyle = preload("res://native/sengoku_ui.gd")
const BattlefieldHUD = preload("res://native/battlefield_hud.gd")
const LearningSession = preload("res://native/learning_session.gd")
const LearningField = preload("res://native/learning_field.gd")
const LearningTransition = preload("res://native/learning_transition.gd")
const CombatFeedback = preload("res://native/combat_feedback.gd")
const BattleAudio = preload("res://native/battle_audio.gd")
const BattleNarrator = preload("res://native/battle_narrator.gd")
const BattleAnnouncer = preload("res://native/battle_announcer.gd")
const VoiceDirector = preload("res://native/voice_director.gd")
const GameFonts = preload("res://native/game_fonts.gd")
const VolumeControls = preload("res://native/volume_controls.gd")
const TIER_IDS = ["basic", "beginner", "intermediate", "advanced"]
const TIER_NAMES = ["기초", "초급", "중급", "고급"]
const PORTRAIT_FOCUS = UIStyle.PORTRAIT_FOCUS
var progress = ProgressStore.new()
var game: Node2D
var atmosphere: Node2D
var troops_3d: Control
var remaster_visuals: Node3D
var field_clip: Control
var battle_field_content: Control
var battle_camera: Node
var camera_controls: Panel
var camera_scale_label: Label
var camera_zoom_in: Button
var camera_zoom_out: Button
var camera_reset: Button
var maps: Array = []
var curriculum: Dictionary = {}
var words_by_id: Dictionary = {}
var current_tier: int = 0
var current_index: int = 0
var current_map: Dictionary = {}
var isolated_candidate: bool = false
var current_lesson: Dictionary = {}
var campaign_story: Dictionary = {}
var stories_by_id: Dictionary = {}
var current_story: Dictionary = {}
var learning_words: Array = []
var seen_this_run: Array = []
var learning_index: int = -1
var learning_clock: float = 0
var learning_turn: int = 0
var answers_correct: int = 0
var answers_total: int = 0
var state: Dictionary = {}
var font: Font
var ui: Control
var sidebar: Panel
var field_border: Panel
var hud_bar: Panel
var hint_bar: Panel
var army_panel: Panel
var learning_panel: Panel
var learning_readout_expanded: bool = false
var learning_readout_button: Button
var learning_paper: Control
var map_scroll: ScrollContainer
var map_list: VBoxContainer
var tier_select: OptionButton
var hud_wave: Label
var hud_clock: Label
var hud_gold: Label
var hud_health: Label
var hud_capacity: Label
var deployment_instruction: Label
var deployment_overlay: Node2D
# A held card belongs to this UI until its matching release, including cancellation.
var deployment_drag: Dictionary = {}
var deployment_press_unit_id: String = ""
var deployment_press_position: Vector2
var deployment_pointer: int = -2
var deployment_release_pending: bool = false
var deployment_pressed_suppressed: bool = false
var deployment_touch_mouse_suppressed: bool = false
const DEPLOYMENT_DRAG_THRESHOLD: float = 6.0
var map_title: Label
var map_note: Label
var opponent_label: Label
var hint_line: Label
var study_progress: Label
var active_word: Control
var example_label: Control
var selected_label: Label
var army_tactics: Label
var army_health: ProgressBar
var selected_word: Control
var selected_portrait: Control
var selected_portrait_window: Control
var selected_portrait_identity: String = ""
var recruit_button: Button
var march_route_select: OptionButton
var chosen_march_path: int = -1
var pause_button: Button
var speed_button: Button
var music_button: Button
var voice_button: Button
var toast_label: Label
var toast_clock: float = 0
var modal: Control
var modal_card: Panel
var modal_body: VBoxContainer
var modal_scroll: ScrollContainer
var modal_footer: Control
var modal_footer_height: float = 48
var quiz_word: Dictionary = {}
var quiz_hinted: bool = false
var quiz_resolved: bool = false
var quiz_feedback: Label
var quiz_choices: Array = []
var quiz_ruby: Control
var quiz_announcement_slot: Control
var quiz_hint_button: Button
var quiz_listen_button: Button
var quiz_continue_button: Button
var player: AudioStreamPlayer
var music_by_stage: Dictionary = {}
var current_music: Dictionary = {}
var music_resource_path: String = ""
var lobby_music: Dictionary = {}
var music_context: String = "lobby"
var music_fade_db: float = 0.0
var music_fade: Tween
var japanese_voice: String = ""
var battle_started: bool = false
var battle_finished: bool = false
var last_victory: bool = false
var resume_after_modal: bool = false
var speed: float = 1.0
var battle_minutes: int = 10
var active_battle_minutes: int = 10
var briefing_expected_text: String = ""
var briefing_played_battle_id: String = ""
var battle_mode_buttons: Array = []
var rng = RandomNumberGenerator.new()
var front_end: Control
var stage_browser_button: Button
var battle_study_button: Button
var transition_layer: ColorRect
var scene_transition: Tween
var navigation_resume_battle: bool = false
var modal_context: String = ""
var catalog_study_lesson: Dictionary = {}
var catalog_study_words: Array = []
var catalog_study_title: String = ""
var last_save_error: String = ""
var barracks: Control
var unit_training: Control
var training_return_view: String = "home"
var chosen_unit_id: String = "archer"
var army_scroll: ScrollContainer
var army_grid: GridContainer
var last_campaign_reward: Dictionary = {}
var closing: bool = false
var learning_plans: Dictionary = {}
var stage_learning: Dictionary = {}
var lesson_session = LearningSession.new()
var learning_field: Control
var learning_transition: Control
var quiz_task: Dictionary = {}
var quiz_selected_id: String = ""
var context_task_active: bool = false
var intermission_presented: bool = false
var quiz_grid: GridContainer
var placement_guidance: String = ""
var hovered_unit_id: String = ""
var army_toolbar: Panel
var production_panel: Panel
var production_title: Label
var production_progress: ProgressBar
var production_scroll: ScrollContainer
var production_cards: HBoxContainer
var production_identity: String = ""
var battle_menu_button: Button
var battle_brand: Label
var learning_caption: Label
var inspector_unit_id: int = -1
var inspector_on_left: bool = false
var reported_missions: Dictionary = {}
var quiz_feedback_text: String = ""
var quiz_outcome_correct: bool = false
var gate_active: bool = false
var unlock_gate: RefCounted
var gate_saved: bool = false
var gate_correct_choice: String = ""
var learning_results: Dictionary = {}
var combat_feedback: Node2D
var battle_audio: Node
var battle_narrator: Node
var battle_announcer: Node
var voice_director: Node
var narration_subtitle: Control
var announcement_subtitle: Control
var narration_serial: int = 0
var narration_battle_id: String = ""
var narration_strong_reported: bool = false
var narration_danger_reported: bool = false
var narration_caption_remaining: float = 0.0
var announcement_caption_remaining: float = 0.0
var audio_save_timer: Timer
var catalog_preparation_completed: int = 0
var catalog_preparation_ready: bool = false
var catalog_preparation_error: String = ""
var catalog_preparation_started: bool = false

func _ready() -> void:
	rng.randomize()
	font = GameFonts.body()
	progress.read_save()
	var saved_minutes = progress.data.settings.get("battleMinutes",10)
	if (saved_minutes is int or saved_minutes is float) and saved_minutes in [10,20]:
		battle_minutes = int(saved_minutes)
	active_battle_minutes = battle_minutes
	var map_data = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var map_catalog: Variant = map_data.get("maps",[]) if map_data is Dictionary else map_data
	maps = map_catalog if map_catalog is Array else []
	curriculum = JSON.parse_string(FileAccess.get_file_as_string("res://native/curriculum.json"))
	for tier in TIER_IDS:
		for lesson in curriculum.get(tier, []):
			for word in lesson.get("newWords", []):
				words_by_id[str(word.id)] = word
	var plans_data = JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	learning_plans = plans_data if plans_data is Dictionary else {}
	if FileAccess.file_exists("res://native/campaign_story.json"):
		var story_data = JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
		campaign_story = story_data if story_data is Dictionary else {}
		for entry in campaign_story.get("stages",[]): stories_by_id[str(entry.stageId)] = entry
	lesson_session.configure(progress,curriculum,learning_plans)
	game = Battle.new()
	game.external_combat_feedback = true
	game.external_placement_ghost = true
	field_clip = Control.new()
	field_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_clip.clip_contents = true
	add_child(field_clip)
	game.set_input_clip(field_clip)
	battle_field_content = Control.new()
	battle_field_content.name = "BattlefieldWorld"
	battle_field_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_clip.add_child(battle_field_content)
	battle_field_content.add_child(game)
	deployment_overlay = DeploymentOverlay.new()
	deployment_overlay.battle = game
	game.add_child(deployment_overlay)
	troops_3d = Troops3D.new()
	troops_3d.bind_battle(game)
	battle_field_content.add_child(troops_3d)
	game.three_d_enabled = bool(ProjectSettings.get_setting("application/config/use_3d_units",false))
	troops_3d.visible = game.three_d_enabled
	atmosphere = BattleAtmosphere.new()
	atmosphere.battle = game
	battle_field_content.add_child(atmosphere)
	combat_feedback = CombatFeedback.new()
	combat_feedback.battle = game
	combat_feedback.troop_renderer = troops_3d
	combat_feedback.font = font
	combat_feedback.emplacement_alerted.connect(_on_emplacement_alert)
	battle_field_content.add_child(combat_feedback)
	battle_camera = BattleCamera.new()
	add_child(battle_camera)
	battle_camera.changed.connect(_on_camera_changed)
	game.state_changed.connect(_on_state)
	game.game_event.connect(_on_game_event)
	game.wave_ended.connect(_on_wave_ended)
	game.wave_started.connect(_on_wave_started)
	game.battle_finished.connect(_on_battle_finished)
	_build_ui()
	learning_field = LearningField.new()
	learning_field.font = font
	learning_field.announcement_row_height = 112
	learning_field.z_index = 30
	learning_field.target_chosen.connect(_answer_context)
	learning_field.hint_requested.connect(_quiz_hint)
	learning_field.listen_requested.connect(_listen_quiz)
	learning_field.continue_requested.connect(_continue_battle)
	ui.add_child(learning_field)
	learning_field.report_card.mouse_filter = Control.MOUSE_FILTER_STOP
	learning_transition = LearningTransition.new()
	learning_transition.font = font
	learning_transition.z_index = 100
	learning_transition.phase_changed.connect(_on_learning_phase_changed)
	learning_transition.presented.connect(_on_learning_presented)
	learning_transition.return_finished.connect(_finish_continue_battle)
	ui.add_child(learning_transition)
	_setup_audio()
	front_end = FrontEnd.new()
	front_end.font = font
	front_end.maps = maps
	front_end.progress = progress
	front_end.battle_minutes = battle_minutes
	front_end.learning_plans = learning_plans
	front_end.campaign_story = campaign_story
	front_end.reading_voice_available = _reading_available()
	front_end.narration_available = battle_narrator.is_ready
	front_end.male_voice_available = battle_narrator.is_ready
	front_end.female_voice_available = battle_announcer.is_ready
	front_end.narration_available = front_end.male_voice_available or front_end.female_voice_available
	front_end.voice_available = front_end.reading_voice_available or front_end.narration_available
	front_end.theme = ui.theme
	front_end.z_index=2600
	front_end.stage_chosen.connect(_choose_stage)
	front_end.assessment_requested.connect(_start_gate_from_catalog)
	front_end.battle_minutes_selected.connect(_choose_battle_minutes)
	front_end.music_toggled.connect(_toggle_music)
	front_end.voice_toggled.connect(_toggle_voice)
	front_end.effects_toggled.connect(_toggle_effects)
	front_end.audio_volume_changed.connect(_set_audio_volume)
	front_end.exit_requested.connect(_quit_game)
	front_end.resume_requested.connect(_resume_from_navigation)
	front_end.barracks_requested.connect(_show_barracks)
	front_end.training_requested.connect(_show_unit_training)
	add_child(front_end)
	barracks = Barracks.new()
	barracks.progress = progress
	barracks.font = font
	barracks.theme = ui.theme
	barracks.z_index=2700
	barracks.closed.connect(_return_from_barracks)
	barracks.army_changed.connect(_rebuild_army_cards)
	barracks.training_requested.connect(_show_unit_training)
	add_child(barracks)
	unit_training = UnitTraining.new()
	unit_training.theme = ui.theme
	add_child(unit_training)
	unit_training.configure(progress,maps,font)
	unit_training.z_index = 2800
	unit_training.completed.connect(_on_unit_training_completed)
	unit_training.closed.connect(_return_from_training)
	get_viewport().size_changed.connect(_layout)
	_layout()
	if not maps.is_empty():
		_select_map(0)
	else:
		game.set_input_enabled(false)
		catalog_preparation_ready = true
	_show_home()
	if not maps.is_empty() and DisplayServer.get_name()!="headless":
		front_end.set_catalog_preparation(0,maps.size())
		call_deferred("_prepare_catalog_previews")
	else:
		# A headless verifier has no framebuffer to cache. Source-only UI tests
		# keep their existing navigation contract; GPU QA covers preparation.
		catalog_preparation_ready=true

func _prepare_catalog_previews() -> void:
	if catalog_preparation_started or closing: return
	catalog_preparation_started=true
	if maps.is_empty():
		catalog_preparation_ready = true
		front_end.set_catalog_preparation(0,0)
		return
	var preview: Control=CatalogPreview.new()
	preview.name="CatalogPreparationRenderer"
	preview.frame_budget_usec=NativeBattlefield.PREPARATION_FRAME_BUDGET_USEC
	preview.position=Vector2(-10000,-10000)
	var dimensions: Vector2=get_viewport().get_visible_rect().size
	preview.size=(dimensions-Vector2(452,488)).max(Vector2(2,2))
	add_child(preview)
	for stage in maps:
		if closing:
			preview.free()
			return
		preview.configure(stage)
		var prepared: bool=await preview.prepare()
		if closing:
			preview.free()
			return
		if not prepared:
			catalog_preparation_error="전장 준비에 실패했습니다: "+str(stage.get("id",""))
			front_end.set_catalog_preparation(catalog_preparation_completed,maps.size(),catalog_preparation_error)
			preview.free()
			return
		catalog_preparation_completed+=1
		front_end.set_catalog_preparation(catalog_preparation_completed,maps.size())
		await get_tree().process_frame
	catalog_preparation_ready=catalog_preparation_completed==maps.size()
	preview.free()

func _theme() -> Theme:
	var result = Theme.new()
	result.default_font = font
	result.default_font_size = 22
	result.set_color("font_color", "Label", Color(UIStyle.TEXT))
	result.set_color("font_color", "Button", Color(UIStyle.TEXT))
	result.set_color("font_hover_color", "Button", Color("f2ead6"))
	result.set_color("font_pressed_color", "Button", Color("f2ead6"))
	result.set_color("font_disabled_color", "Button", Color("748492"))
	for state_name in ["normal","hover","pressed","disabled","focus"]:
		result.set_stylebox(state_name,"Button",UIStyle.textured_button(state_name))
	for kind in ["OptionButton", "LineEdit"]:
		result.set_stylebox("normal", kind, UIStyle.frame())
		result.set_color("font_color", kind, Color(UIStyle.TEXT))
	result.set_stylebox("panel", "PopupMenu", UIStyle.textured_panel())
	result.set_color("font_color", "PopupMenu", Color(UIStyle.TEXT))
	result.set_stylebox("panel","TooltipPanel",UIStyle.textured_panel())
	result.set_color("font_color","TooltipLabel",Color(UIStyle.TEXT))
	result.set_font_size("font_size","TooltipLabel",20)
	return result

func _style(background: String, border: String, _radius: int = 0) -> StyleBoxFlat:
	return UIStyle.frame(background,border)

func _panel(parent: Node, color: String = "15202af5", border: String = "354553") -> Panel:
	var panel = Panel.new()
	var opacity: float = Color(color).a
	panel.add_theme_stylebox_override("panel",UIStyle.textured_panel("lacquer",Color(1,1,1,opacity)) if opacity>.4 else _style(color,border))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel

func _append_authored_reading(context: Array, source: Variant) -> void:
	if not source is Dictionary: return
	context.append(source)
	for part in source.get("parts",[]):
		if part is Dictionary and not str(part.get("reading","")).is_empty():
			context.append({"jp":str(part.get("text","")),"reading":str(part.reading)})
	for key in ["example","transferExample"]:
		if source.get(key) is Dictionary: _append_authored_reading(context,source[key])

func _display_reading_context() -> Array:
	var lesson: Dictionary=current_lesson if catalog_study_lesson.is_empty() else catalog_study_lesson
	var context: Array=[]
	for word in lesson.get("newWords",[]): _append_authored_reading(context,word)
	for word in (learning_words if catalog_study_lesson.is_empty() else catalog_study_words): _append_authored_reading(context,word)
	for expression in lesson.get("expressions",[]): _append_authored_reading(context,expression)
	for step in lesson.get("grammarSteps",[]):
		_append_authored_reading(context,step.get("pattern",{}))
		_append_authored_reading(context,step.get("example",{}))
		var assessment: Dictionary=step.get("assessment",{})
		_append_authored_reading(context,assessment.get("item",{}))
		for choice in assessment.get("choices",[]): _append_authored_reading(context,choice)
	_append_authored_reading(context,current_map.get("trait",{}))
	_append_authored_reading(context,current_story.get("opponent",{}))
	for key in ["item","questionItem","revealItem"]: _append_authored_reading(context,quiz_task.get(key,{}))
	for choice in quiz_task.get("choices",[]): _append_authored_reading(context,choice.get("item",{}))
	_append_authored_reading(context,quiz_word)
	return context

func _label(parent: Node, text: String, text_size: int = 16, color: String = "e1e6e9") -> Label:
	var label = UIStyle.TooltipLabel.new()
	if RubyReadings.contains_kanji(text): label.ruby_context_words=_display_reading_context()
	label.text = text
	label.add_theme_font_override("font",GameFonts.heading() if text_size>=26 else GameFonts.body())
	label.add_theme_font_size_override("font_size", maxi(20,text_size))
	label.add_theme_color_override("font_color", Color(color))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button = UIStyle.TooltipButton.new()
	if RubyReadings.contains_kanji(text): button.ruby_context_words=_display_reading_context()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(func():
		if battle_audio != null:
			battle_audio.consume_event({"action":"ui_click","side":"system"})
		action.call()
	)
	parent.add_child(button)
	return button

func _compact_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size",20)
	for variant in ["normal","hover","pressed","disabled","focus"]:
		var style: StyleBox = UIStyle.textured_button(variant)
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		style.content_margin_left = 10
		style.content_margin_right = 10
		button.add_theme_stylebox_override(variant,style)

func _place(control: Control, x: float, y: float, width: float, height: float) -> void:
	control.position = Vector2(x,y)
	control.size = Vector2(width,height)

func _build_ui() -> void:
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.z_index=2500
	ui.theme = _theme()
	add_child(ui)
	battle_brand = _label(ui, "言葉の戦場", 29, "dbc28d")
	battle_brand.hide()
	battle_menu_button = _button(ui,"메뉴",_show_pause_menu)
	battle_menu_button.tooltip_text = "작전 메뉴 · 음악 · 도감 · 전장 선택 (Esc)"
	stage_browser_button = _button(ui,"전장 선택",_show_catalog)
	battle_study_button = _button(ui,"학습 도감",_show_study)
	map_title = _label(ui, "", 24, "e1e6e9")
	map_title.clip_text=true
	opponent_label = _label(ui,"",20,"e8a2a6")
	opponent_label.name = "HistoricalOpponent"
	opponent_label.clip_text = true
	map_note = _label(ui, "", 13, "a9b4a5")
	map_note.clip_text=true
	sidebar = _panel(ui)
	_label(sidebar, "원정 지도", 18, "d6bd86").position = Vector2(16,14)
	tier_select = OptionButton.new()
	for name in TIER_NAMES:
		tier_select.add_item(name)
	tier_select.item_selected.connect(_select_tier)
	sidebar.add_child(tier_select)
	_place(tier_select,14,53,190,39)
	map_scroll = ScrollContainer.new()
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(map_scroll)
	map_list = VBoxContainer.new()
	map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_list.add_theme_constant_override("separation", 7)
	map_scroll.add_child(map_list)
	study_progress = _label(sidebar, "", 13, "a9b4a5")
	study_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var study = _button(sidebar,"학습 도감",_show_study)
	study.name = "StudyButton"
	field_border = _panel(ui,"00000000","354553")
	hud_bar = _panel(ui,"101822f5","354553")
	hud_bar.z_index=-1
	camera_controls = _panel(ui,"101822dd","9c855b")
	camera_controls.name = "BattlefieldCameraControls"
	camera_controls.tooltip_text = "넓은 전장 · 마우스 휠로 확대, 가운데 버튼을 누른 채 이동"
	camera_scale_label = _label(camera_controls,"1.0×",20,"e8d5ab")
	camera_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	camera_zoom_out = _button(camera_controls,"−",func(): battle_camera.set_zoom(battle_camera.zoom-.1))
	camera_zoom_in = _button(camera_controls,"+",func(): battle_camera.set_zoom(battle_camera.zoom+.1))
	camera_reset = _button(camera_controls,"원위치",func(): battle_camera.reset())
	for camera_button in [camera_zoom_out,camera_zoom_in,camera_reset]:
		_compact_button(camera_button)
	camera_controls.hide()
	hint_bar = _panel(ui,"101822d0","00000000")
	hud_wave = _label(ui,"",20,"b7c3cc")
	hud_clock = _label(ui,"",20,"c8b993")
	hud_clock.name = "BattleClock"
	hud_clock.tooltip_text = "1× 전투 시간 기준 · 학습과 일시 정지는 제외 · 2×에서는 실제 시간이 짧아집니다."
	hud_gold = _label(ui,"",22,"d2bd89")
	hud_health = _label(ui,"",20,"b7c3cc")
	hud_capacity = _label(ui,"",20,"b7c3cc")
	hud_capacity.name = "BattleCapacity"
	hud_health.clip_text=true
	hint_line = _label(ui,"",20,"d1dce4")
	hint_line.clip_text=true
	pause_button = _button(ui,"Ⅱ",_toggle_pause)
	pause_button.tooltip_text = "일시 정지 / 계속 (Space)"
	speed_button = _button(ui,"1×",_cycle_speed)
	speed_button.tooltip_text = "전투 속도 · 1× / 2×"
	army_panel = _panel(ui)
	army_toolbar = _panel(ui,"101b26f5","354553")
	deployment_instruction = _label(army_toolbar,"카드를 끌어 배치",20,"c8b993")
	deployment_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	production_panel = _panel(ui,"101b26ee","354553")
	production_panel.name = "ProductionQueue"
	production_panel.z_index = 50
	production_title = _label(production_panel,"",20,"dfcda3")
	production_progress = ProgressBar.new()
	production_progress.show_percentage = false
	production_panel.add_child(production_progress)
	production_progress.hide()
	production_scroll = ScrollContainer.new()
	production_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	production_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	production_panel.add_child(production_scroll)
	production_cards = HBoxContainer.new()
	production_cards.add_theme_constant_override("separation",6)
	production_scroll.add_child(production_cards)
	var production_note = _label(production_panel,"출진형: 기지 집결 후 자동 전진",20,"9eb4c4")
	production_note.name = "ProductionNote"
	production_note.hide()
	production_panel.hide()
	selected_portrait_window = _panel(army_panel,"101923dd","2c3b47")
	selected_portrait_window.name = "SelectedPortraitWindow"
	selected_portrait_window.clip_contents = true
	selected_portrait_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selected_portrait = LivePortrait.new()
	selected_portrait.name = "SelectedAuthoredPortrait"
	selected_portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	selected_portrait_window.add_child(selected_portrait)
	selected_word=RubyText.new()
	selected_word.font=GameFonts.japanese()
	selected_word.ink=Color(UIStyle.TEXT)
	selected_word.reading_ink=Color(UIStyle.MUTED)
	selected_word.meaning_ink=Color("c8b993")
	army_panel.add_child(selected_word)
	selected_label = _label(army_panel,"",20,"b7c3cc")
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected_label.add_theme_constant_override("line_spacing",-4)
	army_tactics = _label(army_panel,"",20,"aebfcc")
	army_tactics.name = "SelectedTacticalStatus"
	army_tactics.add_theme_font_size_override("font_size",20)
	army_tactics.add_theme_constant_override("line_spacing",-4)
	army_tactics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	army_tactics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	army_health = ProgressBar.new()
	army_health.name = "SelectedTroopHealth"
	army_health.show_percentage = false
	army_health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var health_background = StyleBoxFlat.new()
	health_background.bg_color = Color(Battle.HEALTHBAR_BACKGROUND_COLOR)
	var health_fill = StyleBoxFlat.new()
	health_fill.bg_color = Color(Battle.HEALTHBAR_FRIENDLY_COLOR)
	army_health.add_theme_stylebox_override("background",health_background)
	army_health.add_theme_stylebox_override("fill",health_fill)
	army_panel.add_child(army_health)
	recruit_button = _button(army_toolbar,"배치",_recruit)
	recruit_button.add_theme_font_size_override("font_size",22)
	march_route_select = OptionButton.new()
	march_route_select.name = "MarchRouteSelect"
	march_route_select.add_theme_font_size_override("font_size",20)
	march_route_select.item_selected.connect(func(index: int): chosen_march_path = -1 if index==0 else march_route_select.get_item_id(index))
	army_toolbar.add_child(march_route_select)
	army_scroll = ScrollContainer.new()
	army_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	army_toolbar.add_child(army_scroll)
	army_grid = GridContainer.new()
	army_grid.columns = 8
	army_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	army_grid.add_theme_constant_override("h_separation",6)
	army_grid.add_theme_constant_override("v_separation",7)
	army_scroll.add_child(army_grid)
	chosen_unit_id = str(progress.data.army.selected)
	_rebuild_army_cards()
	learning_panel = _panel(ui,"00000000","00000000")
	learning_panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	learning_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	learning_paper=UIStyle.ornament(learning_panel,Rect2(0,0,1392,130),"paper")
	learning_paper.hide()
	learning_caption = _label(learning_panel,"",20,"64513b")
	learning_caption.name = "GrammarCaption"
	learning_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	learning_caption.add_theme_color_override("font_color",Color("fff3c7"))
	learning_caption.add_theme_color_override("font_outline_color",Color("101410"))
	learning_caption.add_theme_constant_override("outline_size",3)
	active_word = RubyText.new()
	active_word.font = GameFonts.japanese()
	active_word.min_reading_size = 22
	active_word.group_spacing = 8.0
	active_word.merge_adjacent_readings = false
	active_word.show_reading_guides = false
	active_word.ink=Color("fff9ec")
	active_word.reading_ink=Color("fff9ec")
	active_word.meaning_ink=Color("fff9ec")
	active_word.reading_group_palette[0]=Color("ffe6a3")
	active_word.reading_group_palette[1]=Color("9fe7ff")
	active_word.outline_size=4
	active_word.outline_ink=Color(0.04,0.05,0.04,0.95)
	learning_panel.add_child(active_word)
	example_label = RubyText.new()
	example_label.font = GameFonts.japanese()
	example_label.min_reading_size = 22
	example_label.group_spacing = 8.0
	example_label.merge_adjacent_readings = false
	example_label.show_reading_guides = false
	example_label.ink=Color("fff9ec")
	example_label.reading_ink=Color("fff9ec")
	example_label.meaning_ink=Color("fff9ec")
	example_label.reading_group_palette[0]=Color("ffe6a3")
	example_label.reading_group_palette[1]=Color("9fe7ff")
	example_label.outline_size=4
	example_label.outline_ink=Color(0.04,0.05,0.04,0.95)
	learning_panel.add_child(example_label)
	var listen = _button(learning_panel,"듣기",_speak_current)
	listen.name = "ListenButton"
	var next_word = _button(learning_panel,"다음 단어  ›",_advance_word)
	next_word.name = "NextWordButton"
	learning_readout_button = _button(army_toolbar,"학습 펼치기",func():
		learning_readout_expanded = not learning_readout_expanded
		_layout())
	learning_readout_button.name = "LearningReadoutToggle"
	learning_readout_button.tooltip_text = "현재 단어의 예문과 문법 표시를 펼칩니다. 학습 시간과 문제 진행은 그대로 유지됩니다."
	music_button = _button(ui,"음악 켜짐",_toggle_music)
	voice_button = _button(ui,"음성",_toggle_voice)
	for compact in [battle_menu_button,pause_button,speed_button,listen,next_word]:
		_compact_button(compact)
	toast_label = _label(ui,"",15,"f4dd9b")
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	narration_subtitle = RubyText.new()
	narration_subtitle.name = "BattleNarrationSubtitle"
	narration_subtitle.font = GameFonts.japanese()
	narration_subtitle.min_reading_size = 22
	narration_subtitle.group_spacing = 8.0
	narration_subtitle.merge_adjacent_readings = false
	narration_subtitle.show_reading_guides = false
	narration_subtitle.ink = Color("fff9ec")
	narration_subtitle.reading_ink = Color("fff9ec")
	narration_subtitle.meaning_ink = Color("fff9ec")
	narration_subtitle.reading_group_palette[0]=Color("ffe6a3")
	narration_subtitle.reading_group_palette[1]=Color("9fe7ff")
	narration_subtitle.meaning_size = 20
	narration_subtitle.wrap_japanese = true
	narration_subtitle.outline_size = 4
	narration_subtitle.outline_ink = Color(0.025,0.035,0.04,.95)
	narration_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	narration_subtitle.z_index = 90
	ui.add_child(narration_subtitle)
	narration_subtitle.hide()
	announcement_subtitle = RubyText.new()
	announcement_subtitle.name = "BattleAnnouncementSubtitle"
	announcement_subtitle.font = GameFonts.japanese()
	announcement_subtitle.min_reading_size = 22
	announcement_subtitle.group_spacing = 8.0
	announcement_subtitle.merge_adjacent_readings = false
	announcement_subtitle.show_reading_guides = false
	announcement_subtitle.ink = Color("fff9ec")
	announcement_subtitle.reading_ink = Color("fff9ec")
	announcement_subtitle.meaning_ink = Color("fff9ec")
	announcement_subtitle.reading_group_palette[0]=Color("ffe6a3")
	announcement_subtitle.reading_group_palette[1]=Color("9fe7ff")
	announcement_subtitle.meaning_size = 20
	announcement_subtitle.wrap_japanese = true
	announcement_subtitle.outline_size = 4
	announcement_subtitle.outline_ink = Color(0.025,0.035,0.04,.95)
	announcement_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announcement_subtitle.z_index = 110
	ui.add_child(announcement_subtitle)
	announcement_subtitle.hide()
	_rebuild_map_list()
	_apply_battlefield_materials()
	for input_surface in [army_toolbar,army_panel,production_panel,learning_panel,hint_bar,camera_controls]:
		input_surface.mouse_filter = Control.MOUSE_FILTER_STOP

func _apply_battlefield_materials() -> void:
	for pair in [[hud_bar,"hud"],[field_border,"field"],[army_toolbar,"dock"],[army_panel,"selection"],[production_panel,"queue"],[hint_bar,"hint"],[camera_controls,"hint"],[selected_portrait_window,"portrait"],[learning_panel,"hint"]]:
		BattlefieldHUD.apply_panel(pair[0],pair[1])
	for value_label in [hud_clock,hud_gold]: BattlefieldHUD.apply_label(value_label,"value")
	for value_label in [hud_wave,hud_health,hud_capacity]: BattlefieldHUD.apply_label(value_label)
	BattlefieldHUD.apply_label(map_title,"title")
	for control in [battle_menu_button,pause_button,speed_button,camera_zoom_in,camera_zoom_out,camera_reset,learning_readout_button,learning_panel.get_node("ListenButton"),learning_panel.get_node("NextWordButton")]:
		BattlefieldHUD.apply_button(control)
	BattlefieldHUD.apply_progress(army_health,"health")

func _layout() -> void:
	if ui == null:
		return
	var viewport = get_viewport().get_visible_rect().size
	var width = viewport.x
	var height = viewport.y
	var geometry: Dictionary = BattlefieldHUD.layout(viewport)
	var inspector_width: float = geometry.inspectorWidth
	var field: Rect2 = geometry.field
	var dock: Rect2 = geometry.roster
	sidebar.hide()
	stage_browser_button.hide()
	battle_study_button.hide()
	music_button.hide()
	voice_button.hide()
	map_note.hide()
	_place(map_title,24,8,width-548,44)
	_place(hud_capacity,width-502,8,245,44)
	_place(opponent_label,24,60,width-808,44)
	_place(hud_clock,width-758,60,198,44)
	_place(hud_wave,width-547,60,130,44)
	_place(hud_health,width-405,60,168,44)
	_place(hud_gold,width-225,60,198,44)
	_place(pause_button,width-245,8,56,46)
	_place(speed_button,width-179,8,58,46)
	_place(battle_menu_button,width-111,8,88,46)
	for hud_label in [map_title,opponent_label,hud_clock,hud_wave,hud_health,hud_gold,hud_capacity]:
		hud_label.clip_text = true
		hud_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hud_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place(field_border,field.position.x,field.position.y,field.size.x,field.size.y)
	_place(field_clip,field.position.x,field.position.y,field.size.x,field.size.y)
	battle_camera.configure(field_clip,battle_field_content,current_map)
	_place(camera_controls,field.end.x-282,field.position.y+12,268,42)
	_place(camera_scale_label,8,6,56,30)
	_place(camera_zoom_out,68,4,40,34)
	_place(camera_zoom_in,114,4,40,34)
	_place(camera_reset,162,4,98,34)
	_sync_battle_camera()
	if learning_field != null:
		if context_task_active:
			_place(learning_field,0,0,width,height)
		else:
			_place(learning_field,field.position.x,field.position.y,field.size.x,field.size.y)
	game.position = -field.position
	atmosphere.position = -field.position
	troops_3d.position = Vector2.ZERO
	troops_3d.set_field_size(field.size)
	if learning_field != null:
		learning_field.refresh_world_presentation()
	_place(hud_bar,0,0,width,108)
	hud_bar.show()
	active_word.size.x = 230
	example_label.size.x = width-496
	active_word._sync_minimum_height()
	example_label._sync_minimum_height()
	var reading_height: float = maxf(92,maxf(active_word.custom_minimum_size.y,example_label.custom_minimum_size.y))
	learning_caption.size.x = width-270
	var tip_height: float = maxf(40,learning_caption.get_minimum_size().y)
	var caption_height: float = reading_height+tip_height+24
	var caption_y: float = dock.position.y-caption_height-8
	_place(hint_bar,field.position.x+274,field.position.y+8,field.size.x-572,49)
	game.set_field_rect(field)
	if battle_audio != null:
		battle_audio.set_field_rect(field)
	_place(hint_line,field.position.x+286,field.position.y+17,field.size.x-596,30)
	selected_word.size.x = inspector_width-122
	selected_word._sync_minimum_height()
	var selected_height: float = selected_word.custom_minimum_size.y
	var stats_y: float = selected_height+12
	var tactics_y: float = maxf(138,stats_y+54)
	army_tactics.size.x = inspector_width-28
	var tactics_height: float = maxf(54,army_tactics.get_minimum_size().y)
	var panel_height: float = tactics_y+tactics_height+20
	# The authored approach enters at the upper-right. Keep the complete
	# inspector above the dock, clear of that entrance and its direction label.
	var panel_y: float = maxf(field.position.y+8,field.end.y-panel_height-8)
	_place(army_panel,width-inspector_width-24,panel_y,inspector_width,panel_height)
	_place(army_toolbar,dock.position.x,dock.position.y,dock.size.x,dock.size.y)
	_layout_production_queue()
	army_scroll.show()
	recruit_button.hide()
	_place(selected_portrait_window,12,12,90,114)
	_layout_selected_portrait()
	_place(selected_word,110,4,inspector_width-122,selected_height)
	_place(selected_label,110,stats_y,inspector_width-122,48)
	var control_x: float = dock.size.x-geometry.controlsWidth-8
	_place(army_scroll,8,8,control_x-16,dock.size.y-16)
	var roster_card_width: float = geometry.rosterCardWidth
	for card in army_grid.get_children():
		card.custom_minimum_size = Vector2(roster_card_width,geometry.rosterCardHeight)
		for child in card.get_children():
			if child is Label:
				child.size.x = roster_card_width-8 if child.name=="DeploymentKindBadge" else roster_card_width-48
				if child.name=="DeploymentKindBadge": child.position.y = geometry.rosterCardHeight-33
			elif child.name=="SelectedDeploymentRole":
				child.position.y = geometry.rosterCardHeight-4
				child.size.x = roster_card_width
			elif child is TextureRect: child.size.y = geometry.rosterCardHeight-10
	_place(army_tactics,14,tactics_y,inspector_width-28,tactics_height)
	_place(army_health,14,tactics_y+tactics_height+2,inspector_width-28,2)
	_place(recruit_button,width-212,10,164,60)
	_place(deployment_instruction,control_x,4,geometry.controlsWidth,58)
	_place(learning_readout_button,control_x,dock.size.y-52,geometry.controlsWidth,44)
	learning_readout_button.text = "학습 접기" if learning_readout_expanded else "학습 펼치기"
	var marching_selected: bool = str(game.placement_contract(chosen_unit_id).get("deploymentKind","placed"))=="marching"
	march_route_select.visible = marching_selected and game.paths.size()>1
	if march_route_select.visible:
		_place(march_route_select,control_x,3,geometry.controlsWidth,28)
		_place(recruit_button,width-212,34,164,42)
		_place(deployment_instruction,control_x,34,geometry.controlsWidth,48)
	_place(learning_panel,16,caption_y,width-32,caption_height)
	_place(learning_paper,0,0,width-32,caption_height)
	learning_paper.queue_redraw()
	_place(active_word,16,12,230,reading_height)
	_place(example_label,258,12,width-500,reading_height)
	_place(learning_caption,16,reading_height+12,width-274,tip_height)
	var caption_buttons_y: float = (caption_height-100)*0.5
	_place(learning_panel.get_node("ListenButton"),width-212,caption_buttons_y,164,46)
	_place(learning_panel.get_node("NextWordButton"),width-212,caption_buttons_y+54,164,46)
	example_label.visible = learning_readout_expanded
	learning_caption.visible = learning_readout_expanded
	learning_panel.get_node("ListenButton").visible = learning_readout_expanded
	learning_panel.get_node("NextWordButton").visible = learning_readout_expanded
	if not learning_readout_expanded:
		_place(learning_panel,field.position.x+8,field.position.y+8,254,reading_height+16)
		_place(active_word,12,8,230,reading_height)
	_place(toast_label,field.position.x+90,field.position.y+10,field.size.x-450,30)
	_update_army_visibility()
	if modal != null:
		modal.size = viewport
		if modal_context=="quiz":
			var card_width: float = minf(1184,width-96)
			var card_height: float = height-64
			_place(modal_card,(width-card_width)/2,32,card_width,card_height)
			# Keep room for a vertical scrollbar when a long reading wraps.
			var content_width: float = card_width-16
			modal_body.custom_minimum_size.x = content_width
			var footer_height: float = maxf(112,modal_footer.get_combined_minimum_size().y) if modal_footer!=null else 112
			_place(modal_scroll,0,0,card_width,card_height-footer_height-24)
			if modal_footer!=null:
				_place(modal_footer,0,card_height-footer_height,card_width,footer_height)
			if quiz_grid!=null:
				for button in quiz_choices:
					var dimensions: Vector2 = Vector2((content_width-20*(quiz_grid.columns-1))/quiz_grid.columns,clampf(height-510,230,340))
					button.custom_minimum_size = dimensions
					var choice_text: Control = button.get_node_or_null("ChoiceRuby")
					if choice_text!=null:
						choice_text.size.x = dimensions.x-36
						choice_text._sync_minimum_height()
						_place(choice_text,18,maxf(54,(dimensions.y-choice_text.custom_minimum_size.y)*.5),dimensions.x-36,choice_text.custom_minimum_size.y)
		else:
			var card_width = minf(740,width-60)
			var card_height = minf(650,height-80)
			_place(modal_card,(width-card_width)/2,(height-card_height)/2,card_width,card_height)
			_place(modal_scroll,28,26,card_width-56,card_height-52)
			if modal_footer!=null:
				modal_footer.size.x = card_width-56
				var footer_height: float = maxf(modal_footer_height,modal_footer.get_combined_minimum_size().y)
				_place(modal_scroll,28,26,card_width-56,card_height-76-footer_height)
				_place(modal_footer,28,card_height-23-footer_height,card_width-56,footer_height)
			modal_body.custom_minimum_size.x = card_width-76
	_set_intermission_presentation(_learning_covers_battle(),_learning_screen_active())
	_layout_narration_subtitle()
	_layout_announcement_subtitle()
	_sync_announcement_reading()
	_layout_production_queue()

func _layout_production_queue() -> void:
	if production_panel==null or army_toolbar==null: return
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	var bar_width: float = minf(520.0,viewport.x-64.0)
	var bar_height: float = 98.0
	_place(production_panel,viewport.x-bar_width-24,army_toolbar.position.y-bar_height-8.0,bar_width,bar_height)
	_place(production_title,12,3,bar_width-24,27)
	_place(production_scroll,10,29,bar_width-20,68)

func _layout_narration_subtitle() -> void:
	if narration_subtitle==null or narration_subtitle.word.is_empty():
		return
	var field: Rect2 = game.field_rect
	var caption_width: float = minf(620,field.size.x*.48-24)
	var caption_position: Vector2 = Vector2(field.end.x-caption_width-16,field.position.y+18)
	if modal_context=="result" and modal_card!=null:
		caption_width = minf(520,modal_card.position.x-field.position.x-32)
		caption_position = Vector2(field.position.x+16,maxf(field.position.y+18,modal_card.position.y+12))
	narration_subtitle.size.x = maxf(180,caption_width)
	narration_subtitle.position = caption_position
	narration_subtitle._sync_minimum_height()
	narration_subtitle.size.y = narration_subtitle.custom_minimum_size.y

func _layout_announcement_subtitle() -> void:
	if announcement_subtitle==null or announcement_subtitle.word.is_empty():
		return
	var reading_area: Rect2 = Rect2(learning_panel.global_position+active_word.position,Vector2(example_label.position.x+example_label.size.x-active_word.position.x,learning_panel.size.y))
	if context_task_active:
		if is_instance_valid(learning_field.get("announcement_anchor")):
			reading_area = learning_field.announcement_anchor.get_global_rect()
	elif modal_context=="quiz" and is_instance_valid(quiz_announcement_slot):
		reading_area = quiz_announcement_slot.get_global_rect()
	announcement_subtitle.size.x = reading_area.size.x
	announcement_subtitle._sync_minimum_height()
	var caption_height: float = announcement_subtitle.custom_minimum_size.y
	announcement_subtitle.position = reading_area.position+Vector2(0,maxf(0,(reading_area.size.y-caption_height)*.5))
	announcement_subtitle.size.y = caption_height

func _sync_announcement_reading() -> void:
	if announcement_subtitle==null:
		return
	var announcing: bool = announcement_subtitle.visible
	active_word.visible = not announcing
	example_label.visible = not announcing and learning_readout_expanded
	learning_caption.visible = not announcing and learning_readout_expanded
	if is_instance_valid(quiz_ruby):
		quiz_ruby.modulate.a = 1
	if learning_field!=null and learning_field.report_text!=null:
		learning_field.report_text.modulate.a = 1
		learning_field.report_heading.modulate.a = 1

func _learning_screen_active() -> bool:
	return context_task_active or (modal!=null and modal_context=="quiz")

func _field_report_visible() -> bool:
	return learning_field != null and learning_field.report_card != null and learning_field.report_card.is_visible_in_tree()

func _learning_covers_battle() -> bool:
	return _learning_screen_active() and (learning_transition == null or learning_transition.phase == "idle" or learning_transition.covers_battle())

func _set_intermission_presentation(active: bool, force_restore: bool = false) -> void:
	if not active and not intermission_presented and not force_restore:
		return
	intermission_presented = active
	troops_3d.set_external_viewport_consumer(active and context_task_active and ui.is_visible_in_tree() and learning_field.is_visible_in_tree() and troops_3d.uses_world_geometry())
	for control in [field_clip,hud_bar,map_title,opponent_label,hud_wave,hud_clock,hud_health,hud_gold,hud_capacity,pause_button,speed_button,battle_menu_button,army_toolbar,learning_panel]:
		control.visible = not active
	if active:
		army_panel.hide()
		production_panel.hide()
		hint_bar.hide()
		hint_line.hide()
		toast_label.hide()
	else:
		production_panel.visible=battle_started and not battle_finished and not state.get("recruitmentQueue",[]).is_empty()
	if announcement_subtitle!=null:
		_layout_announcement_subtitle()
		_sync_announcement_reading()

func _cancel_learning_transition() -> void:
	if learning_transition != null:
		learning_transition.cancel()

func _on_learning_phase_changed(_phase: String) -> void:
	if not _learning_screen_active():
		return
	_cancel_deployment_drag()
	_set_intermission_presentation(_learning_covers_battle(),true)
	_set_learning_input(learning_transition.accepts_actions())
	game.set_input_enabled(false)

func _set_learning_input(enabled: bool) -> void:
	if context_task_active:
		learning_field.set_interaction_enabled(enabled)
	elif modal!=null and modal_context=="quiz":
		for button in quiz_choices:
			if is_instance_valid(button):
				button.disabled = not enabled or quiz_resolved
		if is_instance_valid(quiz_hint_button):
			quiz_hint_button.disabled = not enabled or quiz_hinted or quiz_resolved
		if is_instance_valid(quiz_listen_button):
			quiz_listen_button.disabled = not enabled or not _reading_available() or (gate_active and not quiz_resolved)
		if is_instance_valid(quiz_continue_button):
			quiz_continue_button.disabled = not enabled

func _on_learning_presented() -> void:
	if not _learning_screen_active():
		return
	if quiz_resolved:
		(learning_field.continue_button if context_task_active else quiz_continue_button).grab_focus()
	elif context_task_active and not learning_field.target_buttons.is_empty():
		learning_field.target_buttons[0].grab_focus()
	elif not quiz_choices.is_empty():
		quiz_choices[0].grab_focus()
	if not quiz_resolved:
		_announce("answer_select",str(quiz_task.get("id",""))+":ready")
	if not quiz_resolved and bool(progress.data.settings.get("voice",true)) and (context_task_active or str(quiz_task.get("kind",""))=="listening"):
		_listen_quiz(true)

func _rebuild_map_list() -> void:
	for child in map_list.get_children():
		child.queue_free()
	var available = _tier_maps()
	for i in range(available.size()):
		var config: Dictionary = available[i]
		var cleared = progress.data.maps.has(str(config.id))
		var text = "%02d  %s%s" % [int(config.get("stageNumber",current_tier*10+i+1)),str(config.title).split(" · ")[0],"  ✓" if cleared else ""]
		var button = _button(map_list,text,_select_map.bind(i))
		button.disabled = not progress.map_unlocked(str(config.id))
		if button.disabled: button.text += "  잠김"
		button.custom_minimum_size = Vector2(183,45)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.add_theme_font_size_override("font_size",13)
		button.tooltip_text = progress.map_lock_reason(str(config.id)) if button.disabled else "%s\n%s" % [str(config.title),str(config.get("description",""))]
		if i == current_index:
			button.add_theme_stylebox_override("normal",_style("35432e","bba268",8))
	study_progress.text = "완료한 지도  %d / 40\n시간을 두고 확인한 단어  %d / 900" % [progress.data.maps.size(),progress.mastered_count()]

func _tier_maps() -> Array:
	var result: Array = []
	for config in maps:
		if config.tier == TIER_IDS[current_tier]:
			result.append(config)
	return result

func _next_registered_stage() -> Dictionary:
	# Historical progress can include stages that have no playable map yet.
	var next_number: int = int(current_map.get("stageNumber",0))+1
	for tier in range(TIER_IDS.size()):
		var available: Array = maps.filter(func(stage): return str(stage.get("tier",""))==TIER_IDS[tier])
		for index in range(available.size()):
			if int(available[index].get("stageNumber",0)) == next_number:
				return {"tier":tier,"index":index,"stage":available[index]}
	return {}

func _rebuild_army_cards() -> void:
	if army_grid == null:
		return
	hovered_unit_id = ""
	for child in army_grid.get_children():
		army_grid.remove_child(child)
		child.queue_free()
	if not chosen_unit_id in progress.unlocked_units():
		chosen_unit_id = "archer"
	for definition in progress.unit_catalog:
		var id: String = str(definition.id)
		var unlocked: bool = id in progress.unlocked_units()
		var evolution: Dictionary = progress.army_evolution(id)
		var deployment: Dictionary = _deployment_display(id)
		var card = UIStyle.TooltipButton.new()
		card.ruby_context_words=[evolution]
		card.name = "DeployCard_%s" % id
		card.custom_minimum_size = Vector2(125,88)
		card.disabled=not unlocked
		BattlefieldHUD.apply_roster_card(card,id==chosen_unit_id,not unlocked)
		card.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		card.tooltip_text = "%s · %s · Lv.%d\n%s · %s" % [str(evolution.jp),str(evolution.name),progress.army_level(id),str(deployment.location),str(deployment.action)]
		card.set_meta("placement_mode",deployment.mode)
		card.set_meta("placement_role",deployment.placementRole)
		card.pressed.connect(_on_deployment_card_pressed.bind(id))
		card.mouse_entered.connect(_on_deploy_card_hover.bind(id,true))
		card.mouse_exited.connect(_on_deploy_card_hover.bind(id,false))
		army_grid.add_child(card)
		if id==chosen_unit_id:
			var selection_edge := ColorRect.new()
			selection_edge.name = "SelectedDeploymentRole"
			selection_edge.color = deployment.color
			selection_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(selection_edge)
			_place(selection_edge,0,84,125,4)
		var portrait = TextureRect.new()
		portrait.name = "UnitPortrait_%s" % id
		portrait.texture = _authored_bust_texture(id,int(evolution.stage))
		portrait.set_meta("unit_id",id)
		portrait.set_meta("source_kind","authored-idle-sheet")
		portrait.set_meta("source_path",portrait.texture.atlas.resource_path if portrait.texture!=null else "")
		portrait.set_meta("visual_evolution",false)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			portrait.modulate=Color("686960")
		card.add_child(portrait)
		_place(portrait,0,0,42,82)
		var compact_name: String = str({"naginata":"장도병","commander":"기마"}.get(id,definition.name))
		var unit_name = _label(card,compact_name,20,"e1e6e9" if unlocked else "748492")
		unit_name.name = "UnitNameLabel"
		unit_name.clip_text=true
		unit_name.add_theme_font_size_override("font_size",20)
		_place(unit_name,44,4,77,28)
		var price = _label(card,str(progress.army_recruit_cost(id)) if unlocked else "잠김",20,"c8b993" if unlocked else "748492")
		price.name = "RecruitPrice_"+id
		_place(price,44,30,77,28)
		var role_badge = _label(card,str(deployment.kind),16,"15202a")
		role_badge.name = "DeploymentKindBadge"
		role_badge.add_theme_color_override("font_color",deployment.color)
		role_badge.add_theme_constant_override("outline_size",3)
		role_badge.add_theme_color_override("font_outline_color",Color("101822"))
		role_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_place(role_badge,4,56,117,30)
		if not unlocked:
			card.tooltip_text="전장 %d개 완료 시 해금\n%s · %s" % [int(definition.unlockClears),str(deployment.location),str(deployment.action)]
	if not state.is_empty():
		_on_state(state)
	if learning_panel != null:
		_layout()

func _authored_bust_texture(id: String, evolution: int) -> AtlasTexture:
	var first: AtlasTexture = LivePortrait.first_frame_texture(id,evolution)
	return UIStyle.bust_texture(first,id)

func _refresh_selected_portrait(id: String, evolution: int) -> void:
	var identity: String = "%s:%d" % [id,evolution]
	if identity==selected_portrait_identity: return
	selected_portrait_identity = identity
	selected_portrait.configure(id,evolution,true)
	_layout_selected_portrait()

func _layout_selected_portrait() -> void:
	if selected_portrait==null or selected_portrait_window==null or not selected_portrait.is_node_ready(): return
	var details: Dictionary = selected_portrait.diagnostics()
	if not bool(details.get("ready",false)): return
	var body: Rect2 = details.visibleBounds
	var cell: Vector2 = details.cellSize
	var authored: Rect2 = UIStyle.portrait_focus(str(details.unitId))
	var focus: Rect2 = Rect2(authored.position*cell/Vector2(256,256),authored.size*cell/Vector2(256,256))
	var anchors: Array = details.frameAnchors
	if not anchors.is_empty():
		focus.position += Vector2(details.baseline)-Vector2(anchors[0])
	var zoom: float = minf(selected_portrait_window.size.x/focus.size.x,selected_portrait_window.size.y/focus.size.y)
	# The existing helper fits its full body at .90/.86. Enlarge that fixed
	# canvas, then clip a stable bust window; do not move individual frames.
	selected_portrait.size = body.size*zoom/Vector2(.90,.86)
	details = selected_portrait.diagnostics()
	var draw_rect: Rect2 = details.drawRect
	var focus_center: Vector2 = draw_rect.position+(focus.get_center()-Vector2(details.canvasOrigin))*zoom
	selected_portrait.position = selected_portrait_window.size*.5-focus_center

func _choose_unit(id: String) -> void:
	if context_task_active or modal_context=="quiz":
		return
	if id in progress.unlocked_units():
		if not progress.select_army_unit(id):
			_toast(progress.save_error)
			return
		chosen_unit_id = id
		if battle_audio != null:
			battle_audio.consume_event({"action":"ui_select","side":"system"})
		if _can_prepare_placement():
			game.cancel_recruit()
			game.begin_placement(id,chosen_march_path)
		_rebuild_army_cards()

func _deployment_display(unit_id: String) -> Dictionary:
	var contract: Dictionary = game.placement_contract(unit_id)
	var mode: String = str(contract.placementMode)
	var location: String = "청록 적 경로 전선"
	var action: String = "기마 돌격" if str(contract.combatRole)=="cavalry" else "근접 저지"
	if mode=="fixed_emplacement":
		location = "황금 고정 진지"
		action = "제자리 사격"
	elif mode=="frontline_shooter":
		action = "짧은 거리 사격"
	var marching: bool = str(contract.get("deploymentKind","placed"))=="marching"
	var kind: String = str(contract.get("deploymentKind","placed"))
	var kind_name: String = "배치형"
	var color: Color = Color("ffda87")
	if marching:
		location = "아군 기지 출발"
		action = "교전 후 계속 전진"
		kind_name = "전진형"
		color = Color("73e5d2")
	elif kind=="ambush":
		location = "보라색 임무 출발 지점"
		action = "적 타워형 공격자 암살 · 임무 종료 후 소모"
		kind_name = "소모형"
		color = Color("b997ff")
	elif kind=="support":
		location = "청록 전열 지원 지점"
		action = "부상 아군 치료 · 진언 지원"
		kind_name = "지원형"
		color = Color("98cba4")
	elif kind=="guard":
		location = "청록 성벽·사격 진지 호위 지점"
		action = "침입 적 저지 · 조용해지면 복귀"
		kind_name = "호위형"
		color = Color("73e5d2")
	return {"mode":mode,"placementRole":contract.placementRole,"role":contract.roleKo,"hint":contract.placementHintKo,"location":location,"action":action,"kind":kind_name,"marching":marching,"color":color}

func _on_deploy_card_hover(unit_id: String, active: bool) -> void:
	if active:
		if not _can_prepare_placement():
			return
		hovered_unit_id = unit_id
	elif hovered_unit_id==unit_id:
		hovered_unit_id = ""
	_update_placement_feedback()

func _can_prepare_placement() -> bool:
	return battle_started and not battle_finished and not closing and modal == null and not context_task_active and not front_end.visible and not barracks.visible and not unit_training.visible and game.input_enabled and not game.between_waves and (learning_transition == null or not learning_transition.is_busy())

func _deployment_card_at(pointer: Vector2) -> String:
	if army_grid == null or not army_toolbar.is_visible_in_tree(): return ""
	for card in army_grid.get_children():
		if card is Button and card.is_visible_in_tree() and card.get_global_rect().has_point(pointer):
			return str(card.name).trim_prefix("DeployCard_")
	return ""

func _deployment_surface_point(pointer: Vector2) -> Dictionary:
	if not _can_prepare_placement() or not pointer.is_finite() or not game.screen_point_in_field(pointer): return {}
	for surface in [hud_bar,army_toolbar,army_panel,production_panel,learning_panel,hint_bar,camera_controls]:
		if surface != null and surface.is_visible_in_tree() and surface.get_global_rect().has_point(pointer): return {}
	for caption in [narration_subtitle,announcement_subtitle]:
		if caption != null and caption.is_visible_in_tree() and caption.get_global_rect().has_point(pointer): return {}
	if learning_field != null and learning_field.report_card.is_visible_in_tree() and learning_field.report_card.get_global_rect().has_point(pointer): return {}
	var point: Vector2 = game.screen_to_field_point(pointer)
	if not point.is_finite() or point.x<0 or point.x>1 or point.y<0 or point.y>1: return {}
	return {"position":point}

func _deployment_path_id() -> String:
	if chosen_march_path<0 or chosen_march_path>=game.paths.size(): return ""
	return str(game.paths[chosen_march_path].get("id",chosen_march_path))

func _on_deployment_card_pressed(unit_id: String) -> void:
	# Pointer gestures are consumed before Control receives them. This signal
	# remains available to an explicit keyboard activation on the focused card.
	if deployment_pressed_suppressed or deployment_release_pending: return
	if _can_prepare_placement(): _choose_unit(unit_id)

func _begin_deployment_press(unit_id: String, pointer: Vector2, pointer_id: int) -> void:
	deployment_press_unit_id = unit_id
	deployment_press_position = pointer
	deployment_pointer = pointer_id
	deployment_release_pending = true
	deployment_pressed_suppressed = true
	deployment_touch_mouse_suppressed = pointer_id>=0
	game.ui_deployment_active = true
	battle_camera.set_input_enabled(false)

func _begin_deployment_drag(unit_id: String, pointer: Vector2, touch_index: int = -1) -> void:
	if not _can_prepare_placement() or not unit_id in progress.unlocked_units(): return
	if not deployment_release_pending:
		_begin_deployment_press(unit_id,pointer,touch_index)
	deployment_press_unit_id = ""
	deployment_drag = {"unitId":unit_id,"pointer":pointer,"preview":{}}
	# Retire an older free click preview once this gesture becomes a drag.
	# Accepted jobs and their refunds belong to the production queue.
	if bool(game.pending.get("preview",false)) and int(game.pending.get("paid",0))==0:
		game.cancel_recruit()
	_update_deployment_presentation()
	_update_deployment_drag(pointer)

func _update_deployment_drag(pointer: Vector2) -> void:
	if deployment_drag.is_empty(): return
	if not _can_prepare_placement():
		_cancel_deployment_drag()
		return
	deployment_drag.pointer = pointer
	var surface: Dictionary = _deployment_surface_point(pointer)
	var point: Vector2 = game.screen_to_field_point(pointer) if pointer.is_finite() else Vector2(-1,-1)
	var preview: Dictionary = game.deployment_preview(str(deployment_drag.unitId),point,_deployment_path_id())
	if surface.is_empty():
		preview.valid = false
		preview.ok = false
		preview.visible = false
		preview.reason = "전장 안의 배치 지점에 놓으십시오."
	deployment_drag.preview = preview
	deployment_overlay.present(preview)
	troops_3d.ui_deployment_preview = preview
	var guidance: String = str(preview.get("reason",""))
	if guidance.is_empty(): guidance = "놓으면 소집 · Esc 취소"
	deployment_instruction.text = guidance
	deployment_instruction.tooltip_text = "%s ×%d · 보급 %d\n%s" % [str(preview.get("name",deployment_drag.unitId)),int(preview.get("quantity",1)),int(preview.get("cost",0)),guidance]

func _finish_deployment_drag(pointer: Vector2) -> void:
	if deployment_drag.is_empty(): return
	var unit_id: String = str(deployment_drag.unitId)
	var surface: Dictionary = _deployment_surface_point(pointer)
	var result: Dictionary = {}
	if not surface.is_empty():
		# Commit uses the current surface, path, balance, unlock and reservations.
		result = game.submit_deployment(unit_id,surface.position,_deployment_path_id())
	_cancel_deployment_drag()
	if not result.is_empty() and not bool(result.get("ok",false)):
		_toast(str(result.get("message",result.get("reason","배치할 수 없습니다."))))

func _cancel_deployment_drag() -> void:
	var owned_gesture: bool = deployment_release_pending
	deployment_drag.clear()
	deployment_press_unit_id = ""
	if owned_gesture and is_instance_valid(game) and bool(game.pending.get("preview",false)) and int(game.pending.get("paid",0))==0:
		game.cancel_recruit()
	if is_instance_valid(deployment_overlay): deployment_overlay.present({})
	if is_instance_valid(troops_3d):
		troops_3d.ui_deployment_preview = {}
		troops_3d.sync_placement_preview({})
	if is_instance_valid(game): game.ui_deployment_active = deployment_release_pending
	_update_deployment_presentation()

func _release_deployment_pointer() -> void:
	deployment_release_pending = false
	deployment_pointer = -2
	if is_instance_valid(game): game.ui_deployment_active = false
	_sync_battle_camera()

func _update_deployment_presentation() -> void:
	if learning_panel == null: return
	var dragging: bool = not deployment_drag.is_empty()
	if dragging:
		learning_panel.hide()
		army_panel.hide()
		hint_bar.hide()
		hint_line.hide()
	else:
		learning_panel.visible = not _learning_covers_battle() and not _field_report_visible()
		_update_army_visibility()
		_update_placement_feedback()
		if deployment_instruction != null:
			deployment_instruction.text = "카드를 끌어 배치"
			deployment_instruction.tooltip_text = "짧게 클릭: 기존 병종 선택 / 출진 · R: 선택 병종 소집 · Esc / 우클릭: 취소"

func _handle_deployment_input(event: InputEvent) -> bool:
	# Only a captured card touch owns its synthetic mouse copy. Ordinary GUI
	# taps must still reach home, menu and learning controls.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device==-1 and deployment_touch_mouse_suppressed:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			deployment_touch_mouse_suppressed = false
		return true
	if event is InputEventKey:
		if deployment_release_pending and event.pressed and event.keycode in [KEY_ESCAPE,KEY_R]:
			if event.keycode==KEY_ESCAPE: _cancel_deployment_drag()
			return true
		if event.pressed and not event.echo and event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE] and not deployment_release_pending:
			deployment_pressed_suppressed = false
		return false
	var pointer: Vector2
	var pointer_id: int = -1
	var is_press: bool = false
	var is_release: bool = false
	var is_motion: bool = false
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT and deployment_release_pending:
			if event.pressed: _cancel_deployment_drag()
			return true
		if event.button_index!=MOUSE_BUTTON_LEFT: return false
		pointer = event.position
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventMouseMotion:
		pointer = event.position
		is_motion = true
	elif event is InputEventScreenTouch:
		pointer = event.position
		pointer_id = event.index
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventScreenDrag:
		pointer = event.position
		pointer_id = event.index
		is_motion = true
	else: return false
	if is_press:
		if deployment_release_pending and (not deployment_drag.is_empty() or not deployment_press_unit_id.is_empty()): return true
		if deployment_release_pending: _release_deployment_pointer()
		deployment_touch_mouse_suppressed = false
		var unit_id: String = _deployment_card_at(pointer)
		if unit_id.is_empty() or not _can_prepare_placement(): return false
		# A locked card's gesture is consumed, so its release cannot reach a
		# previous legacy placement waiting underneath the UI.
		_begin_deployment_press(unit_id,pointer,pointer_id)
		if not unit_id in progress.unlocked_units(): deployment_press_unit_id = ""
		return true
	if not deployment_release_pending: return false
	if pointer_id!=deployment_pointer: return true
	if is_motion:
		if not deployment_press_unit_id.is_empty() and pointer.distance_to(deployment_press_position)>=DEPLOYMENT_DRAG_THRESHOLD:
			_begin_deployment_drag(deployment_press_unit_id,pointer,pointer_id)
		elif not deployment_drag.is_empty(): _update_deployment_drag(pointer)
		return true
	if is_release:
		var clicked_unit: String = deployment_press_unit_id
		var deliberate_click: bool = not clicked_unit.is_empty() and deployment_drag.is_empty() and _can_prepare_placement() and _deployment_card_at(pointer)==clicked_unit and pointer.distance_to(deployment_press_position)<DEPLOYMENT_DRAG_THRESHOLD
		if not deployment_drag.is_empty(): _finish_deployment_drag(pointer)
		else: _cancel_deployment_drag()
		_release_deployment_pointer()
		if deliberate_click: _choose_unit(clicked_unit)
		return true
	return false

func _show_unit_training(focused_unit: String = "") -> void:
	if maps.is_empty():
		_toast("병종 연습에 사용할 전장을 재설계하고 있습니다.")
		return
	training_return_view = "barracks" if barracks.visible else "home"
	_stop_narration()
	_cancel_learning_transition()
	_pause_for_navigation()
	_close_modal(false)
	game.set_input_enabled(false)
	front_end.hide()
	barracks.hide()
	ui.hide()
	field_clip.hide()
	unit_training.configure(progress,maps,font)
	unit_training.open_menu(focused_unit)
	_set_lobby_music()

func _on_unit_training_completed(unit_id: String) -> void:
	var result: Dictionary = progress.record_unit_training(unit_id)
	if not bool(result.get("ok",false)):
		unit_training.error_ko = str(result.get("message","연무 기록을 저장할 수 없습니다."))
		unit_training._refresh_ui()

func _return_from_training() -> void:
	if training_return_view=="barracks":
		barracks.open(not battle_started or battle_finished,not maps.is_empty())
	else:
		front_end.battle_active = battle_started and not battle_finished
		front_end.show_home()

func _show_barracks() -> void:
	_stop_narration()
	_cancel_learning_transition()
	_pause_for_navigation()
	front_end.hide()
	ui.hide()
	field_clip.hide()
	game.set_input_enabled(false)
	barracks.open(not battle_started or battle_finished,not maps.is_empty())
	_set_lobby_music()

func _return_from_barracks() -> void:
	_rebuild_army_cards()
	front_end.show_home()

func _select_tier(index: int) -> void:
	var tier_maps: Array = maps.filter(func(stage): return str(stage.tier)==TIER_IDS[clampi(index,0,3)])
	if tier_maps.is_empty() or not progress.map_unlocked(str(tier_maps[0].id)):
		_show_catalog()
		front_end.show_catalog(index)
		return
	current_tier = index
	current_index = 0
	_select_map(0)

func _select_map(index: int) -> void:
	var candidates: Array = _tier_maps()
	if index<0 or index>=candidates.size(): return
	if not progress.map_unlocked(str(candidates[index].id)):
		_toast(progress.map_lock_reason(str(candidates[index].id)))
		return
	isolated_candidate = false
	_cancel_deployment_drag()
	gate_active = false
	_cancel_learning_transition()
	navigation_resume_battle = false
	if barracks != null:
		barracks.hide()
	if front_end != null:
		front_end.hide()
	ui.show()
	field_clip.show()
	current_index = index
	var available = _tier_maps()
	if available.is_empty():
		return
	current_map = available[index].duplicate(true)
	current_story = stories_by_id.get(str(current_map.id),{})
	if not current_story.is_empty(): current_map["story"] = current_story.duplicate(true)
	_reset_narration_battle()
	var lessons: Array = curriculum.get(TIER_IDS[current_tier],[])
	current_lesson = lessons[index] if index < lessons.size() else {}
	stage_learning = learning_plans.get("stages",{}).get(str(current_map.id),{})
	lesson_session.begin_lesson(current_lesson,current_map)
	learning_words = lesson_session.words.duplicate()
	quiz_task.clear()
	quiz_selected_id = ""
	context_task_active = false
	reported_missions.clear()
	learning_results.clear()
	if learning_field != null:
		learning_field.clear()
	seen_this_run.clear()
	learning_index = -1
	learning_clock = 0
	learning_turn = 0
	chosen_march_path = -1
	answers_correct = 0
	answers_total = 0
	battle_started = false
	battle_finished = false
	active_battle_minutes = battle_minutes
	last_victory = false
	last_campaign_reward.clear()
	speed = 1.0
	speed_button.text = "1×"
	_close_modal(false)
	game.configure_roster(progress.unit_catalog,progress.unlocked_units(),progress.data.army.levels)
	combat_feedback.reset()
	if battle_audio != null:
		battle_audio.stop_all()
	game.load_map(current_map,battle_minutes)
	if battle_audio!=null: battle_audio.set_presentation_mirrored(game.presentation_mirrored)
	_configure_march_routes()
	atmosphere.set_stage(current_map)
	if not _set_battlefield_stage(current_map):
		game.close_battle()
		_show_home()
		_toast("새 전장의 지형 데이터를 확인할 수 없습니다.")
		return
	_mount_remaster_visuals(current_map)
	game.three_d_actor_scale = troops_3d.actor_base_scale()
	game.set_speed(speed)
	_set_music_context(false)
	map_title.text = "%02d  ·  %s" % [int(current_map.get("stageNumber",current_tier*10+index+1)),str(current_map.title)]
	if not current_story.is_empty(): map_title.text = "%02d · %d %s" % [int(current_map.stageNumber),int(current_story.year),str(current_story.battleKo)]
	opponent_label.text = "적장 · "+str(current_story.get("opponent",{}).get("nameKo","")) if not current_story.is_empty() else ""
	opponent_label.set("ruby_context_words",[current_story.get("opponent",{})])
	opponent_label.tooltip_text = str(current_story.get("opponent",{}).get("nameJP",""))+" · "+str(current_story.get("opponent",{}).get("reading",""))
	map_note.text = "%s · 신규 %d · 맞춤 복습 %d" % [TIER_NAMES[current_tier],current_lesson.get("newWords",[]).size(),maxi(0,learning_words.size()-current_lesson.get("newWords",[]).size())]
	map_note.tooltip_text = str(stage_learning.get("goalKo",""))
	_advance_word()
	_rebuild_map_list()
	_rebuild_army_cards()
	_show_briefing()
	_animate_stage_arrival()

func _set_battlefield_stage(stage: Dictionary) -> bool:
	# The authored extent is independent of camera and viewport size.
	if stage.get("worldGeometry") is Dictionary and not stage.worldGeometry.is_empty():
		var provider: Node3D=WorldAdapter.new()
		provider.configure(stage)
		if not bool(provider.diagnostics().ready):
			provider.free()
			return false
		_clear_remaster_visuals()
		troops_3d.set_stage(stage)
		troops_3d.set_terrain_provider(provider)
		return true
	_clear_remaster_visuals()
	if is_instance_valid(troops_3d.battlefield) and troops_3d.battlefield is WorldAdapter:
		troops_3d.set_terrain_provider(NativeBattlefield.new())
	troops_3d.set_stage(stage)
	return true

func _clear_remaster_visuals() -> void:
	if is_instance_valid(remaster_visuals):
		if remaster_visuals.get_parent() != null:
			remaster_visuals.get_parent().remove_child(remaster_visuals)
		remaster_visuals.queue_free()
	remaster_visuals = null

func _mount_remaster_visuals(stage: Dictionary) -> void:
	# Candidate QA owns its own presentation; normal stage selection mounts once.
	if not stage.get("worldGeometry") is Dictionary or not stage.get("visualComposition") is Dictionary or stage.visualComposition.is_empty():
		return
	remaster_visuals = RemasterVisuals.new()
	remaster_visuals.name = "RemasterVisuals"
	troops_3d.world.add_child(remaster_visuals)
	remaster_visuals.configure(stage,troops_3d.battlefield)
	# Troops initializes native lights while installing its provider.
	remaster_visuals.apply_lighting(troops_3d)

func configure_candidate(stage: Dictionary) -> Dictionary:
	# Material review uses real HUD/gameplay in an isolated account only.
	var profile_path: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var qa_root: String=ProjectSettings.globalize_path("res://tests/profiles/").replace("\\","/").to_lower().trim_suffix("/")+"/"
	if not profile_path.begins_with(qa_root): return {"ok":false,"reason":"Candidate requires an isolated tests/profiles account"}
	if not bool(stage.get("candidateOnly",stage.get("qaOnly",false))) or not stage.get("paths") is Array or stage.paths.is_empty() or not stage.get("objectives") is Array or stage.objectives.is_empty() or not stage.get("worldGeometry") is Dictionary or stage.worldGeometry.is_empty(): return {"ok":false,"reason":"Labeled candidate requires new ground, routes and objectives"}
	if not _set_battlefield_stage(stage): return {"ok":false,"reason":"Candidate world geometry is invalid"}
	_cancel_deployment_drag()
	_cancel_learning_transition()
	_close_modal(false)
	isolated_candidate=true
	current_map=stage.duplicate(true)
	current_story=current_map.get("story",{})
	current_lesson=curriculum.get("basic",[])[0] if not curriculum.get("basic",[]).is_empty() else {}
	stage_learning={}
	lesson_session.begin_lesson(current_lesson,current_map)
	learning_words=lesson_session.words.duplicate()
	seen_this_run.clear(); learning_index=-1; learning_clock=0; learning_turn=0
	answers_correct=0; answers_total=0; chosen_march_path=-1
	battle_started=false; battle_finished=false; last_victory=false
	active_battle_minutes=battle_minutes
	last_campaign_reward.clear()
	game.configure_roster(progress.unit_catalog,progress.unlocked_units(),progress.data.army.levels)
	game.load_map(current_map,battle_minutes)
	troops_3d.bind_battle(game)
	_configure_march_routes()
	atmosphere.set_stage(current_map)
	front_end.hide(); barracks.hide(); unit_training.hide()
	ui.show(); field_clip.show()
	map_title.text="CANDIDATE · 새 전장 검토"
	map_note.text="격리 검증 · 캠페인 전장 아님"
	_rebuild_army_cards()
	_advance_word()
	_layout()
	return {"ok":true,"catalogRegistered":false,"campaignRewards":false,"world":troops_3d.battlefield.diagnostics()}

func _candidate_display_allowed() -> bool:
	if not isolated_candidate or current_map.is_empty(): return false
	var profile_path: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var qa_root: String=ProjectSettings.globalize_path("res://tests/profiles/").replace("\\","/").to_lower().trim_suffix("/")+"/"
	return profile_path.begins_with(qa_root)

func _pause_for_navigation() -> void:
	_cancel_deployment_drag()
	if not battle_started or battle_finished:
		navigation_resume_battle = false
		return
	if modal_context == "pause":
		navigation_resume_battle = resume_after_modal
	elif not front_end.visible and not barracks.visible and not unit_training.visible:
		navigation_resume_battle = not bool(state.get("paused",false))
	if not bool(state.get("paused",false)):
		game.pause_battle()

func _show_home() -> void:
	gate_active = false
	_stop_narration()
	_cancel_learning_transition()
	if barracks != null:
		barracks.hide()
	_pause_for_navigation()
	_close_modal(false)
	game.set_input_enabled(false)
	ui.hide()
	field_clip.hide()
	troops_3d.set_external_viewport_consumer(false)
	front_end.battle_active = battle_started and not battle_finished
	front_end.show_home()
	_set_lobby_music()

func _show_catalog() -> void:
	gate_active = false
	_stop_narration()
	_cancel_learning_transition()
	_pause_for_navigation()
	_close_modal(false)
	game.set_input_enabled(false)
	ui.hide()
	field_clip.hide()
	troops_3d.set_external_viewport_consumer(false)
	front_end.battle_active = battle_started and not battle_finished
	front_end.show_catalog(current_tier)
	_set_lobby_music()

func _resume_from_navigation() -> void:
	if maps.is_empty() or current_map.is_empty():
		_show_home()
		return
	front_end.hide()
	ui.show()
	field_clip.show()
	game.set_input_enabled(true)
	if navigation_resume_battle and not battle_finished:
		game.pause_battle()
	navigation_resume_battle = false
	_set_music_context(battle_started and not battle_finished)
	if bool(state.get("betweenWaves",false)):
		_show_quiz()

func _choose_stage(tier: int, index: int, study: bool = false) -> void:
	var available_stages: Array = maps.filter(func(stage): return str(stage.tier)==TIER_IDS[clampi(tier,0,3)])
	if index<0 or index>=available_stages.size(): return
	if not progress.map_unlocked(str(available_stages[index].id)):
		_toast(progress.map_lock_reason(str(available_stages[index].id)))
		return
	if study:
		catalog_study_lesson = curriculum[TIER_IDS[tier]][index].duplicate(true)
		catalog_study_words = catalog_study_lesson.get("newWords",[]).duplicate()
		for id in catalog_study_lesson.get("reviewIds",[]):
			if words_by_id.has(str(id)):
				catalog_study_words.append(words_by_id[str(id)])
		var available = maps.filter(func(stage): return str(stage.tier)==TIER_IDS[tier])
		catalog_study_title = str(available[index].title)
		front_end.hide()
		ui.show()
		field_clip.hide()
		_show_study()
		return
	catalog_study_lesson.clear()
	catalog_study_words.clear()
	catalog_study_title = ""
	current_tier = tier
	tier_select.select(tier)
	_select_map(index)

func _animate_stage_arrival() -> void:
	if transition_layer == null:
		transition_layer = ColorRect.new()
		transition_layer.color = Color("0b1612")
		transition_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		transition_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		transition_layer.z_index=3000
		add_child(transition_layer)
	move_child(transition_layer,get_child_count()-1)
	transition_layer.show()
	transition_layer.modulate.a = 1.0
	if scene_transition != null and scene_transition.is_running():
		scene_transition.kill()
	scene_transition = create_tween()
	scene_transition.tween_property(transition_layer,"modulate:a",0.0,0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	scene_transition.tween_callback(transition_layer.hide)

func _show_briefing() -> void:
	if current_map.is_empty() or (maps.is_empty() and not _candidate_display_allowed()): return
	_open_modal()
	modal_context = "briefing"
	modal_body.add_theme_constant_override("separation",10)
	_modal_label("出陣  ·  출진 준비",28,"e2c78c")
	_modal_label(str(current_map.title),23)
	if not current_story.is_empty():
		_modal_label("%d년 · %s · %s" % [int(current_story.year),str(current_story.battleKo),str(current_story.get("phaseKo",""))],25,"e5d09f").name = "StoryBattleTitle"
		_modal_label(str(current_story.get("chapterKo","")),20,"d9c79b").name = "StoryChapter"
		_modal_label(str(current_story.get("introKo","")),20,"c8d4dd").name = "StoryIntroduction"
		_modal_label("역사 · "+str(current_story.get("historySummaryKo","")),20,"d9c79b").name = "StoryHistoricalSummary"
		var geo: Dictionary=front_end._geography(str(current_map.id))
		if not str(geo.get("renderingBasisKo","")).is_empty():
			_modal_label("맵 제작 근거 · "+str(geo.renderingBasisKo),20,"c5cfbf").name="StoryMapBasis"
		var opponent: Dictionary = current_story.get("opponent",{})
		var opponent_name = RubyText.new()
		opponent_name.name="StoryOpponent"
		opponent_name.font=GameFonts.japanese()
		opponent_name.set_word({"jp":opponent.get("nameJP",""),"reading":opponent.get("reading",""),"ko":"상대 장수 · "+str(opponent.get("nameKo",""))},26,true)
		modal_body.add_child(opponent_name)
		_modal_label("이번 임무 · "+str(current_story.get("playerGoalKo","전선을 지키십시오.")),20,"e8a2a6")
	_build_battle_mode_selector()
	var stage_rule: Dictionary = current_map.get("trait",{})
	if not stage_rule.is_empty():
		var operation = RubyText.new()
		operation.font = GameFonts.japanese()
		operation.set_word({"jp":stage_rule.nameJP,"reading":stage_rule.reading,"ko":stage_rule.nameKO},24)
		modal_body.add_child(operation)
	_modal_label(str(stage_rule.get("descriptionKO",current_map.get("description",""))),16,"bac8b9")
	_modal_label("이번 전장에서 익힐 것\n"+str(stage_learning.get("goalKo","상황 속 일본어를 이해합니다.")),20,"d9c79b")
	var tactics: Dictionary = current_map.get("tactics",{})
	if not tactics.is_empty():
		_modal_label(str(tactics.get("nameKo","전장 배치"))+"\n"+str(tactics.get("descriptionKo","")),20,"d7c399")
	_modal_label("배치형 · 궁병은 황금 진지, 조총병은 청록 전선\n전진형 · 창병·사무라이·기마병은 기지에서 출진\n호위형 · 장도병은 성벽·사격 진지 주변 방어\n지원형 · 승병은 부상 아군 치료·진언 지원\n소모형 · 닌자는 적 타워형 공격자 암살 후 임무 종료\n생산을 시작하면 보급금을 지불합니다. 각 주문은 병렬로 준비됩니다.",20,UIStyle.MUTED)
	if game.emplacement_protection_active():
		_modal_label("초반에는 적이 진지를 공격하지 않습니다. 장도병을 해금한 뒤에는 호위 병력으로 진지를 지키십시오.",20,"d9c79b")
	_modal_label("문장 속 빈칸 한 곳을 채우면 보급을 받습니다.\n한자 위 히라가나와 한국어 도움을 보며 시작하십시오.",20,"b7c3cc")
	_add_grammar_steps(modal_body,current_lesson)
	var words: Array = current_lesson.get("newWords",[])
	_modal_label("이번 전장의 새 단어 %d개 · 전투 중 차례로 표시" % words.size(),22,"d9c79b")
	var preview = GridContainer.new()
	preview.columns = 4
	preview.add_theme_constant_override("separation",12)
	modal_body.add_child(preview)
	for i in range(words.size()):
		var ruby = RubyText.new()
		ruby.font = GameFonts.japanese()
		ruby.wrap_japanese = true
		ruby.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ruby.set_word(words[i],28)
		preview.add_child(ruby)
	_modal_label("우클릭 / Esc 배치 취소 · R 배치 / 출진\nSpace 정지 · 병력 강화는 병영에서 진행",20,"9cabb8")
	_modal_label("音楽  %s — %s" % [str(current_music.get("title","")),str(current_music.get("author",""))],20,"ab9f83")
	modal_footer=HBoxContainer.new()
	var actions = modal_footer
	actions.add_theme_constant_override("separation",12)
	modal_card.add_child(actions)
	var button = _button(actions,"출진",_begin_battle)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 48
	button.add_theme_stylebox_override("normal",UIStyle.textured_button("normal",true))
	_button(actions,"전장 선택",_show_catalog).custom_minimum_size = Vector2(205,48)
	_layout()

func _build_battle_mode_selector() -> void:
	_modal_label("전투 시간 · 출진 전에 선택",20,"d9c79b")
	var choices = HBoxContainer.new()
	choices.name = "BattleModeSelector"
	choices.add_theme_constant_override("separation",12)
	modal_body.add_child(choices)
	battle_mode_buttons.clear()
	for minutes in [10,20]:
		var option = _button(choices,"%d분" % minutes,_choose_battle_minutes.bind(minutes))
		option.name = "BattleMinutes%d" % minutes
		option.set_meta("battle_minutes",minutes)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.custom_minimum_size.y = 42
		option.add_theme_stylebox_override("normal",UIStyle.selected() if minutes==battle_minutes else UIStyle.button("normal"))
		battle_mode_buttons.append(option)
	_modal_label("선택한 시간이 끝날 때까지 거점을 지키십시오.\n학습·일시 정지 제외 · 2×에서는 실제 시간이 짧아집니다.",20,"9cabb8")

func _choose_battle_minutes(minutes: int) -> void:
	if minutes not in [10,20] or (battle_started and not battle_finished):
		return
	battle_minutes = minutes
	progress.data.settings["battleMinutes"] = minutes
	progress.write_save()
	if front_end!=null:
		front_end.battle_minutes = minutes
		if front_end.visible:
			front_end._rebuild()
	for option in battle_mode_buttons:
		if is_instance_valid(option):
			option.add_theme_stylebox_override("normal",UIStyle.selected() if int(option.get_meta("battle_minutes"))==minutes else UIStyle.button("normal"))

func _battle_clock_text(seconds: float) -> String:
	var total: int = maxi(0,int(floor(seconds+.000001)))
	return "%02d:%02d" % [total/60,total%60]

func _begin_battle() -> void:
	if maps.is_empty() or current_map.is_empty():
		_show_home()
		return
	if not progress.map_unlocked(str(current_map.get("id",""))):
		_toast(progress.map_lock_reason(str(current_map.get("id",""))))
		return
	var first_departure: bool = not battle_started
	if first_departure:
		active_battle_minutes = battle_minutes
		if int(game.snapshot().get("battleMinutes",0))!=active_battle_minutes:
			game.load_map(current_map,active_battle_minutes)
		narration_serial += 1
		narration_battle_id = "%s:%d" % [str(current_map.get("id","")),narration_serial]
	battle_started = true
	_close_modal(false)
	if learning_index>=0 and learning_index<learning_words.size():
		_record_displayed_word(learning_words[learning_index])
	_set_music_context(true)
	if first_departure and not _play_mission_briefing():
		_narrate("battle_start","start")
	game.start_battle()
	toast_clock=0.0
	toast_label.hide()

func _process(delta: float) -> void:
	if not deployment_press_unit_id.is_empty() or not deployment_drag.is_empty():
		if not _can_prepare_placement():
			_cancel_deployment_drag()
		elif not deployment_drag.is_empty():
			_update_deployment_drag(deployment_drag.pointer)
	if learning_panel != null:
		learning_panel.visible = deployment_drag.is_empty() and not _learning_covers_battle() and not _field_report_visible()
	_sync_battle_camera()
	_update_placement_feedback()
	_update_voice_mix()
	_update_caption_time(delta)
	if learning_field!=null:
		learning_field.flow_paused = bool(state.get("paused",false)) or (announcement_subtitle!=null and announcement_subtitle.visible)
	if toast_label != null and learning_field != null:
		toast_label.visible = (not learning_field.report_card.visible and not context_task_active) or not progress.save_error.is_empty()
	if progress.save_error != last_save_error:
		last_save_error = progress.save_error
		if not last_save_error.is_empty():
			_toast(last_save_error + " 진행을 유지하고 다시 저장을 시도하십시오.")
		if front_end != null and front_end.visible:
			front_end._rebuild()
	if toast_clock > 0:
		toast_clock -= delta
		if toast_clock <= 0:
			toast_label.text = ""
	if battle_started and not battle_finished and modal == null and not context_task_active and not front_end.visible and not unit_training.visible and not bool(state.get("paused",false)) and not bool(state.get("betweenWaves",false)):
		if active_word.is_visible_in_tree():
			if learning_index>=0 and learning_index<learning_words.size(): _record_displayed_word(learning_words[learning_index])
			learning_clock += delta
		if learning_clock >= _word_dwell_seconds():
			_advance_word()

func _sync_battle_camera() -> void:
	if battle_camera==null or camera_controls==null: return
	var showing_battle: bool = ui!=null and ui.is_visible_in_tree() and field_clip.is_visible_in_tree() and not _learning_screen_active()
	var accepting_input: bool = showing_battle and battle_started and not battle_finished and modal==null and not bool(state.get("paused",false)) and not deployment_release_pending
	if battle_camera.input_enabled!=accepting_input:
		battle_camera.set_input_enabled(accepting_input)
	camera_controls.visible = showing_battle and battle_camera.enabled and modal==null
	camera_zoom_in.disabled = not accepting_input or battle_camera.zoom>=BattleCamera.MAX_ZOOM-.0001
	camera_zoom_out.disabled = not accepting_input or battle_camera.zoom<=BattleCamera.MIN_ZOOM+.0001
	camera_reset.disabled = not accepting_input or (is_equal_approx(battle_camera.zoom,1.0) and battle_camera.pan.is_zero_approx())

func _on_camera_changed(camera_state: Dictionary) -> void:
	if camera_scale_label!=null:
		camera_scale_label.text = "%.1f×" % float(camera_state.get("zoom",1.0))
	_sync_battle_camera()

func _advance_word() -> void:
	if learning_words.is_empty():
		return
	learning_index = (learning_index + 1) % learning_words.size()
	learning_turn += 1
	learning_clock = 0.0
	var word: Dictionary = learning_words[learning_index]
	active_word.set_word(word,36)
	var example: Dictionary = word.get("example",{})
	if (learning_turn-1)/learning_words.size()%2==1 and word.get("transferExample") is Dictionary:
		example = word.transferExample
	example_label.set_word(example,24)
	var step: Dictionary = _current_grammar_step(example)
	learning_caption.set("ruby_context_words",_display_reading_context())
	learning_caption.text = "어휘 %02d / %d · %s" % [learning_index+1,learning_words.size(),str(step.get("explanationKo","후리가나로 소리를 읽고, 한국어 뜻과 짧은 예문을 연결하십시오."))]
	learning_caption.call("refresh_ruby")
	_layout()
	if battle_started and active_word.visible and learning_panel.visible:
		_record_displayed_word(word)
	if battle_started and modal == null and bool(progress.data.settings.get("voice",true)):
		_speak(str(word.jp),true)

func _word_dwell_seconds() -> float:
	var reading: String = str(example_label.word.get("reading",example_label.word.get("jp","")))
	return clampf(10.0+reading.length()*.22,12.0,20.0)

func _current_grammar_step(example: Dictionary = {}) -> Dictionary:
	var steps: Array = current_lesson.get("grammarSteps",[])
	if steps.is_empty(): return {}
	for index in range(steps.size()-1,-1,-1):
		if str(steps[index].get("id","")) in example.get("grammarIds",[]): return steps[index]
	return steps[mini(steps.size()-1,maxi(0,learning_index)*steps.size()/maxi(1,learning_words.size()))]

func _add_grammar_steps(parent: Node, lesson: Dictionary) -> void:
	for step in lesson.get("grammarSteps",[]):
		var card = VBoxContainer.new()
		card.name = "GrammarStep_%s" % str(step.id)
		card.add_theme_constant_override("separation",5)
		parent.add_child(card)
		var title = _label(card,str(step.get("titleKo","기초 문법")),22,"e5d09f")
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var explanation = _label(card,str(step.get("explanationKo","")),20,"c8d4dd")
		explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var example = RubyText.new()
		example.font = GameFonts.japanese()
		example.wrap_japanese = true
		example.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		example.set_word(step.get("example",step.get("pattern",{})),26,true)
		card.add_child(example)

func _configure_march_routes() -> void:
	if march_route_select==null: return
	march_route_select.clear()
	march_route_select.add_item("전선 · 자동",-1)
	for index in range(game.paths.size()):
		march_route_select.add_item("%d번 전선" % (index+1),index)
	march_route_select.select(0)
	chosen_march_path = -1
	march_route_select.tooltip_text = "자동은 적의 수·본진까지의 거리와 아군·생산 중인 병력을 고려합니다. 전선을 고르면 연결된 본진에서 출발하여 해당 길을 지킵니다. 출진 후에는 다른 전선으로 옮겨 다니지 않습니다."
	_layout()

func _caption_dwell_seconds(caption: Dictionary, minimum: float) -> float:
	var reading: String = str(caption.get("reading",caption.get("jp","")))
	return clampf(3.0+reading.length()*.24+str(caption.get("ko","")).length()*.08,minimum,16.0)

func _update_caption_time(delta: float) -> void:
	if bool(state.get("paused",false)): return
	narration_caption_remaining = maxf(0.0,narration_caption_remaining-delta)
	announcement_caption_remaining = maxf(0.0,announcement_caption_remaining-delta)
	var mission_speaking: bool = not briefing_expected_text.is_empty() and voice_director!=null and voice_director.is_tts_active()
	if narration_subtitle!=null and narration_subtitle.visible and narration_caption_remaining<=0.0 and not mission_speaking and (battle_narrator==null or not battle_narrator.is_speaking()):
		narration_subtitle.hide()
	if announcement_subtitle!=null and announcement_subtitle.visible and announcement_caption_remaining<=0.0 and (battle_announcer==null or not battle_announcer.is_speaking()):
		announcement_subtitle.hide()
		_sync_announcement_reading()

func _record_displayed_word(word: Dictionary) -> void:
	if not seen_this_run.has(str(word.id)):
		seen_this_run.append(str(word.id))
		progress.mark_exposure(str(word.id),"meaning",str(current_map.get("id","")))

func _on_state(value: Dictionary) -> void:
	state = value
	if combat_feedback != null:
		combat_feedback.paused = bool(value.get("paused",false))
	if battle_audio != null:
		battle_audio.set_paused(bool(value.get("paused",false)) or bool(value.get("betweenWaves",false)) or bool(value.get("finished",false)))
	if learning_field != null:
		learning_field.flow_paused = bool(value.get("paused",false)) or (announcement_subtitle!=null and announcement_subtitle.visible)
	if not bool(progress.data.settings.get("voice",true)) and ((battle_narrator!=null and battle_narrator.enabled) or (battle_announcer!=null and battle_announcer.enabled)):
		_stop_narration()
	for voice in [battle_narrator,battle_announcer]:
		if voice==null: continue
		var voice_enabled: bool = bool(progress.data.settings.get("voice",true))
		if voice.enabled!=voice_enabled:
			voice.set_enabled(voice_enabled)
		var explicitly_paused: bool = bool(value.get("paused",false))
		if voice.paused!=explicitly_paused:
			voice.set_paused(explicitly_paused)
	if hud_wave == null:
		return
	var show_battle_ui: bool = not _learning_covers_battle()
	army_toolbar.visible = show_battle_ui
	_refresh_production_queue(value,show_battle_ui)
	learning_panel.visible = show_battle_ui and deployment_drag.is_empty() and not _field_report_visible()
	var wave = int(value.get("wave",0))
	hud_clock.text = "%d분 · %s / %s" % [active_battle_minutes,_battle_clock_text(float(value.get("battleElapsedSeconds",value.get("elapsed",0)))),_battle_clock_text(float(value.get("battleTargetSeconds",active_battle_minutes*60)))]
	hud_wave.text = "%02d / %02d  ·  적 %d" % [wave,int(value.get("totalWaves",10)),int(value.get("enemyCount",0))]
	hud_wave.tooltip_text = "총 %d개 파상 공격 · 전장에 남은 적 %d · 진입 예정 %d" % [int(value.get("totalWaves",10)),int(value.get("enemyCount",0)),int(value.get("remainingSpawns",0))]
	hud_gold.text = "보급  %d" % int(value.get("gold",0))
	hud_capacity.text = "출전 %d / %d" % [value.get("units",[]).size(),int(value.get("unitLimit",0))]
	hud_capacity.tooltip_text = "실제 출전 병력 / 출전 정원 · 소집 완료 주문은 필요한 정원이 생길 때 출진합니다."
	speed = float(value.get("speed",speed))
	speed_button.text = "%d×" % int(speed)
	var objectives: Array = value.get("objectives",[])
	var health_parts: Array = []
	for objective in objectives:
		health_parts.append("%s %d" % [objective.get("label","거점"),int(objective.get("hp",0))])
	hud_health.text = "거점 %d / %d" % [int(value.get("hp",0)),int(value.get("maxHp",0))]
	hud_health.tooltip_text = "  ·  ".join(health_parts)
	var selected = value.get("selected",value.get("selectedTower",{}))
	var inspected_id: String = str(selected.get("type",chosen_unit_id)) if selected is Dictionary and not selected.is_empty() else chosen_unit_id
	var inspected_evolution: Dictionary = progress.army_evolution(inspected_id)
	var inspected_word: Dictionary = {"jp":inspected_evolution.jp,"reading":inspected_evolution.reading,"ko":inspected_evolution.name}
	if selected_word.word!=inspected_word:
		selected_word.set_word(inspected_word,26)
		_layout()
	_refresh_selected_portrait(inspected_id,int(inspected_evolution.stage))
	if selected is Dictionary and not selected.is_empty():
		if inspected_id=="monk":
			selected_label.text = "병영 Lv.%d\n치료 %.1f · %.1f초" % [int(selected.get("campaignLevel",1)),float(selected.get("healAmount",0)),float(selected.get("healInterval",1))]
		elif inspected_id=="commander" and "commander_charge" in selected.get("skillIds",[]):
			selected_label.text = "병영 Lv.%d\n돌격 %.0f · 주기 %.1f초" % [int(selected.get("campaignLevel",1)),float(selected.get("chargeDamage",0)),float(selected.get("chargeInterval",0))]
		else:
			selected_label.text = "병영 Lv.%d\n공격 %.0f / 초당 %.1f" % [int(selected.get("campaignLevel",1)),float(selected.get("damage",0)),float(selected.get("dps",0))]
	else:
		var choice: Dictionary = progress.unit_definition(chosen_unit_id)
		var preview_stats: Dictionary = progress.army_stats(str(choice.id))
		selected_label.text = "훈련 Lv.%d   치료 %.1f" % [progress.army_level(chosen_unit_id),float(preview_stats.healAmount)] if chosen_unit_id=="monk" else "훈련 Lv.%d   공격 %.0f" % [progress.army_level(chosen_unit_id),float(preview_stats.damage)]
	var visible_stats: Dictionary = selected if selected is Dictionary and not selected.is_empty() else progress.army_stats(inspected_id)
	selected_label.tooltip_text = "최대 체력 %.0f · 피해 감소 %.1f%%" % [float(visible_stats.get("maxHp",visible_stats.get("health",0))),float(visible_stats.get("armor",0))*100.0]
	_update_tactical_status(selected,inspected_id)
	var pending = value.get("pending",value.get("pendingRecruit",{}))
	if pending is Dictionary and not pending.is_empty():
		var deployment: Dictionary = _deployment_display(str(pending.get("type",chosen_unit_id)))
		placement_guidance = "%s · %s · %s · 우클릭 / Esc 취소" % [pending.get("name","병력"),deployment.location,deployment.action]
	else:
		placement_guidance = str(value.get("hint",current_map.get("tactics",{}).get("hintKo","궁병은 황금 고정 진지, 근접·기마·철포는 청록 전선에 배치합니다.")))
	_update_placement_feedback()
	var recruit_cost: int = progress.army_recruit_cost(chosen_unit_id)
	var placing = pending is Dictionary and not pending.is_empty()
	var marching: bool = str(game.placement_contract(chosen_unit_id).get("deploymentKind","placed"))=="marching"
	var chosen_kind: String = str(game.placement_contract(chosen_unit_id).get("deploymentKind","placed"))
	var recruitment: String = {"marching":"출진","ambush":"기습 배치","support":"지원 배치"}.get(chosen_kind,"배치")
	recruit_button.text = "배치 취소" if placing else "%s  %d" % [recruitment,recruit_cost]
	recruit_button.disabled = context_task_active or battle_finished or not battle_started or (not placing and (int(value.get("gold",0)) < recruit_cost or value.get("recruitmentQueue",[]).size()>=int(value.get("recruitmentCapacity",24))))
	pause_button.disabled = context_task_active
	speed_button.disabled = context_task_active
	var chosen_deployment: Dictionary = _deployment_display(chosen_unit_id)
	recruit_button.tooltip_text = ("Esc / 우클릭 배치 취소" if placing else "기지에서 선택 병종 출진 (R)" if marching else "선택 병종 배치 (R)")+"\n"+str(chosen_deployment.hint)
	if not placing:
		recruit_button.tooltip_text += "\n병렬 소집 %.1f초 · 주문을 클릭하면 취소 및 환불" % float(progress.unit_definition(chosen_unit_id).get("recruitSeconds",2))
	if march_route_select!=null: march_route_select.visible = show_battle_ui and marching and game.paths.size()>1
	pause_button.text = "▶" if bool(value.get("paused",false)) else "Ⅱ"
	_update_army_visibility()
	_set_intermission_presentation(_learning_covers_battle(),_learning_screen_active())
	_layout_production_queue()
	_update_deployment_presentation()
	_observe_narration_state(value)

func _refresh_production_queue(value: Dictionary, battle_visible: bool) -> void:
	if production_panel==null: return
	var jobs: Array = value.get("recruitmentQueue",[])
	var was_visible: bool = production_panel.visible
	production_panel.visible = battle_visible and battle_started and not battle_finished and not jobs.is_empty()
	var ids: Array[String] = []
	for job in jobs: ids.append(str(job.id))
	var identity: String = ":".join(ids)
	if identity!=production_identity:
		production_identity = identity
		for child in production_cards.get_children():
			production_cards.remove_child(child)
			child.queue_free()
		for job in jobs:
			var card = _button(production_cards,"",_cancel_production.bind(int(job.id)))
			card.name = "RecruitmentJob_%d" % int(job.id)
			card.set_meta("jobId",int(job.id))
			card.custom_minimum_size = Vector2(190,68)
			_compact_button(card)
			for variant in ["normal","hover","pressed","disabled","focus"]:
				var style: StyleBox = card.get_theme_stylebox(variant).duplicate()
				style.content_margin_left = 47
				style.content_margin_bottom = 14
				card.add_theme_stylebox_override(variant,style)
			var portrait = TextureRect.new()
			portrait.name = "ProductionPortrait"
			portrait.texture = _authored_bust_texture(str(job.type),0)
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(portrait)
			_place(portrait,6,5,36,51)
			var gauge = ProgressBar.new()
			gauge.name = "ProductionGauge"
			gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gauge.show_percentage = false
			var track = StyleBoxFlat.new()
			track.bg_color = Color("18232b")
			track.set_corner_radius_all(2)
			var fill = StyleBoxFlat.new()
			fill.bg_color = Color("d7b86e")
			fill.set_corner_radius_all(2)
			gauge.add_theme_stylebox_override("background",track)
			gauge.add_theme_stylebox_override("fill",fill)
			card.add_child(gauge)
			_place(gauge,48,57,132,7)
	for index in range(jobs.size()):
		var job: Dictionary = jobs[index]
		var card: Button = production_cards.get_child(index)
		card.text = BattlefieldHUD.queue_text(job)
		card.tooltip_text = BattlefieldHUD.queue_tooltip(job)
		card.disabled = context_task_active or battle_finished
		var waiting_capacity: bool = str(job.get("status",""))=="waiting_capacity"
		var status_changed: bool = not card.has_meta("hud_waiting_capacity") or bool(card.get_meta("hud_waiting_capacity"))!=waiting_capacity
		if status_changed: BattlefieldHUD.apply_queue_card(card,waiting_capacity)
		var gauge: ProgressBar = card.get_node("ProductionGauge")
		if status_changed: BattlefieldHUD.apply_progress(gauge,"waiting_capacity" if waiting_capacity else "production")
		gauge.value = 100.0*(1.0-float(job.remainingSeconds)/maxf(.001,float(job.totalSeconds)))
	production_title.text = "병렬 소집 · %d / %d건   ·   주문을 누르면 취소" % [jobs.size(),int(value.get("recruitmentCapacity",24))]
	if was_visible!=production_panel.visible: _layout()
	else: _layout_production_queue()

func _cancel_production(job_id: int) -> void:
	if _can_prepare_placement():
		game.cancel_recruitment(job_id)

func _observe_narration_state(value: Dictionary) -> void:
	if not battle_started or battle_finished or bool(value.get("finished",false)) or bool(value.get("betweenWaves",false)):
		return
	if not narration_strong_reported:
		for enemy in value.get("enemies",[]):
			if str(enemy.get("kind","")) in ["commander","heavy"]:
				narration_strong_reported = true
				_narrate("strong_enemy","strong-enemy")
				break
	if not narration_danger_reported:
		for objective in value.get("objectives",[]):
			var health: float = float(objective.get("hp",0))
			var maximum: float = float(objective.get("maxHp",0))
			if health>0 and maximum>0 and health/maximum<=.30:
				narration_danger_reported = true
				_narrate("danger","danger")
				break

func _update_placement_feedback() -> void:
	if hint_line==null or game==null:
		return
	var feedback: String = placement_guidance
	var feedback_color: Color = Color("d1dce4")
	var can_place: bool = _can_prepare_placement()
	var placing: bool = not game.pending.is_empty()
	if not can_place:
		hovered_unit_id = ""
	if can_place and not hovered_unit_id.is_empty():
		var definition: Dictionary = progress.unit_definition(hovered_unit_id)
		var hovered: Dictionary = _deployment_display(hovered_unit_id)
		feedback = "%s · %s · %s" % [str(definition.name),hovered.location,hovered.action]
		if not hovered_unit_id in progress.unlocked_units():
			feedback += " · 전장 %d개 완료 시 해금" % int(definition.unlockClears)
		feedback_color = hovered.color
	elif can_place and placing:
		feedback_color = _deployment_display(str(game.pending.type)).color
		if game.placement_cursor_visible:
			var preview: Dictionary = game.placement_preview(game.placement_cursor)
			if not bool(preview.get("valid",false)) and not str(preview.get("reason","")).is_empty():
				feedback = str(preview.reason)
				feedback_color = Color("dfb5a4")
	if hint_line.text!=feedback:
		hint_line.text = feedback
	if hint_line.get_theme_color("font_color")!=feedback_color:
		hint_line.add_theme_color_override("font_color",feedback_color)
	hint_bar.visible = can_place and (placing or not hovered_unit_id.is_empty())
	hint_line.visible = hint_bar.visible
	if not deployment_drag.is_empty():
		hint_bar.hide()
		hint_line.hide()

func _update_army_visibility() -> void:
	if army_panel == null:
		return
	var selected = state.get("selected",{})
	var pending = state.get("pending",{})
	var has_selected: bool = selected is Dictionary and not selected.is_empty()
	var placing: bool = pending is Dictionary and not pending.is_empty()
	if has_selected and int(selected.get("id",-1)) != inspector_unit_id:
		inspector_unit_id = int(selected.id)
		# Keep the pilot's objective and lower approach/contact corridor readable.
		inspector_on_left = false
		army_panel.position.x = get_viewport().get_visible_rect().size.x-army_panel.size.x-24
	elif not has_selected:
		inspector_unit_id = -1
	army_panel.visible = deployment_drag.is_empty() and not context_task_active and not _learning_covers_battle() and has_selected and not placing

func _update_tactical_status(selected, unit_id: String) -> void:
	var deployment: Dictionary = _deployment_display(unit_id)
	var fixed_emplacement: bool = str(deployment.mode)=="fixed_emplacement"
	var health_visible: bool = false
	var tactical_text: String = ""
	if selected is Dictionary and not selected.is_empty():
		var stance: String = str(selected.get("stanceKo","사격 대기" if fixed_emplacement else "전선 대기"))
		if is_instance_valid(troops_3d):
			var action: Dictionary = troops_3d.action_presentation.state_for_id(int(selected.get("id",-1)))
			if not action.is_empty(): stance = str(action.actionLabelKo)
		var status: String = "%s · %s" % [deployment.kind,stance]
		army_tactics.tooltip_text = "%s\n%s" % [str(selected.get("postName",deployment.location)),deployment.hint]
		if fixed_emplacement:
			tactical_text = status+"\n황금 고정 진지 · 원거리 지원"
		else:
			var health: float = float(selected.get("hp",0.0))
			var maximum: float = float(selected.get("maxHp",0.0))
			tactical_text = status+"\n체력 %.0f/%.0f · " % [health,maximum]
			if str(deployment.kind)=="지원형":
				tactical_text += "치료 지원"
			elif str(deployment.kind)=="호위형":
				tactical_text += "진지 호위"
			elif str(deployment.mode)=="frontline_shooter":
				tactical_text += "짧은 거리 사격"
			else:
				tactical_text += "저지 %d/%d" % [int(selected.get("blockCount",0)),int(selected.get("blockCapacity",0))]
			army_health.max_value = maxf(1.0,maximum)
			army_health.value = health
			health_visible = maximum>0.0
		if fixed_emplacement:
			var maximum: float = float(selected.get("maxHp",0.0))
			army_health.max_value = maxf(1.0,maximum)
			army_health.value = float(selected.get("hp",0.0))
			health_visible = maximum>0.0
			army_tactics.tooltip_text += "\n체력 %.0f/%.0f · 침입한 적이 진지를 공격할 수 있습니다." % [army_health.value,maximum]
		if unit_id=="naginata" and "naginata_guard_charge" in selected.get("skillIds",[]):
			tactical_text += "\n전의 %.0f / %.0f" % [float(selected.get("mana",0)),float(selected.maxMana)]
		var unlocked_skills: Array[String] = []
		for skill in progress.army_skills(unit_id):
			if bool(skill.unlocked): unlocked_skills.append(str(skill.titleKo))
		if not unlocked_skills.is_empty():
			army_tactics.tooltip_text += "\n해금 능력: "+" · ".join(unlocked_skills)
		if unit_id=="naginata":
			army_tactics.tooltip_text += "\n파란 실선: 이동 경계 · 황금 점선: 적 인식 범위\n방어 구역 밖으로 나가야 하는 적은 추격하지 않습니다."
	else:
		tactical_text = str(deployment.role)+"\n"+str(deployment.location)
		army_tactics.tooltip_text = str(deployment.hint)
	var height_before: float = army_tactics.get_minimum_size().y
	army_tactics.text = tactical_text
	army_health.visible = health_visible
	if not is_equal_approx(height_before,army_tactics.get_minimum_size().y):
		_layout()

func _on_game_event(event: Dictionary) -> void:
	if combat_feedback != null:
		combat_feedback.consume_event(event)
	if battle_audio != null:
		battle_audio.consume_event(event)
	if str(event.get("type","")) == "unit_consumed":
		_toast(Troops3D.TroopActions.consumed_label(str(event.get("consumeReason","mission_ended"))))
	elif event.has("message"):
		_toast(str(event.message))

func _on_emplacement_alert(_event: Dictionary) -> void:
	if not battle_started or battle_finished or closing: return
	_toast("진지가 공격받고 있습니다")
	# Actual hit sounds are emitted by BattleAudio from the same committed event.
	# Existing speech does not describe this danger, so the voice queue stays unchanged.

func _recruit() -> void:
	if deployment_release_pending: return
	if _can_prepare_placement():
		if not game.snapshot().get("pending",{}).is_empty():
			game.cancel_recruit()
		else:
			game.begin_placement(chosen_unit_id,chosen_march_path)

func _toggle_pause() -> void:
	if battle_started and not battle_finished and modal == null and not context_task_active:
		game.pause_battle()

func _cycle_speed() -> void:
	speed = 2.0 if speed == 1.0 else 1.0
	game.set_speed(speed)
	speed_button.text = "%d×" % int(speed)

func _on_wave_ended(_info: Dictionary) -> void:
	if battle_finished:
		return
	_show_quiz()

func _on_wave_started(info: Dictionary) -> void:
	if battle_finished or str(info.get("mapId","")) != str(current_map.get("id","")):
		return
	for mission in stage_learning.get("missions",[]):
		if int(mission.get("wave",0)) != int(info.get("wave",0)):
			continue
		var id: String = str(mission.get("id",""))
		if reported_missions.has(id):
			continue
		reported_missions[id] = true
		progress.mark_exposure(id,"context",id)
		for word_id in mission.get("itemIds",[]):
			if words_by_id.has(str(word_id)) and not seen_this_run.has(str(word_id)):
				seen_this_run.append(str(word_id))
				progress.mark_exposure(str(word_id),"context",id)
		learning_field.show_report(mission,_reading_available())
		_announce("message_received",id+":arrival")
		if bool(progress.data.settings.get("voice",true)):
			_speak(str(mission.get("report",{}).get("jp","")),true)
		break

func _show_quiz() -> void:
	_stop_narration()
	if _learning_screen_active() and learning_transition.phase != "idle":
		return
	if quiz_task.is_empty():
		quiz_task = unlock_gate.current_task() if gate_active else lesson_session.next_task(seen_this_run,int(state.get("wave",0)),_reading_available() and bool(progress.data.settings.get("voice",true)))
		quiz_hinted = false
		quiz_resolved = false
		quiz_feedback_text = ""
		quiz_selected_id = ""
	if quiz_task.is_empty():
		game.continue_wave()
		return
	quiz_word = quiz_task.get("revealItem",quiz_task.get("item",{}))
	if str(quiz_task.get("kind","")) == "context":
		_show_context_task()
		return
	context_task_active = false
	learning_field.suspend_choice()
	_open_modal()
	modal_context = "quiz"
	modal_card.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var shade: ColorRect = modal.get_child(0)
	shade.color = Color(.045,.033,.02,.74)
	# Indexed battlefields remain visible beneath the existing modal shade.
	# A painted background is optional and used only when it actually exists.
	var background_path: String=str(current_map.get("background",""))
	if not background_path.is_empty() and ResourceLoader.exists(background_path,"Texture2D"):
		var picture = TextureRect.new()
		picture.texture = load(background_path)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		modal.add_child(picture)
		modal.move_child(picture,0)
	modal_body.add_theme_constant_override("separation",14)
	quiz_choices.clear()
	var kind: String = str(quiz_task.get("kind","meaning"))
	var header = HBoxContainer.new()
	header.name = "QuizHeader"
	header.custom_minimum_size.y = 112
	header.add_theme_constant_override("separation",20)
	modal_body.add_child(header)
	var purpose = VBoxContainer.new()
	purpose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(purpose)
	var title = _label(purpose,"聞き取り · 듣고 빈칸 완성" if kind=="listening" else "補給任務 · 빈칸 한 곳 채우기",27,UIStyle.BRASS)
	if gate_active:
		var gate_state: Dictionary = unlock_gate.snapshot()
		title.text = "解禁試験 · 해금 시험 %02d / %d" % [int(gate_state.get("index",0))+1,int(gate_state.get("count",0))]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var instruction = _label(purpose,"나머지 문장은 그대로입니다. 밑줄에 들어갈 단어를 선택하십시오.",20,UIStyle.MUTED)
	if gate_active: instruction.text = "이 전장의 단어·문법을 힌트 없이 전부 맞히면 다음 맵이 열립니다."
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var grammar_step: Dictionary = _current_grammar_step(quiz_word)
	if not grammar_step.is_empty() and not gate_active:
		var grammar_note = _label(purpose,str(grammar_step.get("explanationKo","")),20,"e5d09f")
		grammar_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quiz_announcement_slot = Control.new()
	quiz_announcement_slot.name = "QuizAnnouncementSlot"
	quiz_announcement_slot.custom_minimum_size = Vector2(420,112)
	quiz_announcement_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(quiz_announcement_slot)
	quiz_ruby = RubyText.new()
	quiz_ruby.font = GameFonts.japanese()
	quiz_ruby.min_reading_size = 22
	quiz_ruby.group_spacing = 8.0
	quiz_ruby.merge_adjacent_readings = false
	quiz_ruby.show_reading_guides = false
	quiz_ruby.ink=Color(UIStyle.TEXT)
	quiz_ruby.reading_ink=Color("c9d6df")
	quiz_ruby.meaning_ink=Color("c8b993")
	quiz_ruby.wrap_japanese = true
	quiz_ruby.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quiz_ruby.set_word(quiz_task.get("questionItem",quiz_word),36,true)
	var reading_slot = MarginContainer.new()
	reading_slot.name = "QuizReadingSlot"
	reading_slot.custom_minimum_size.y = 112
	reading_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_body.add_child(reading_slot)
	reading_slot.add_child(quiz_ruby)
	var grid = GridContainer.new()
	quiz_grid = grid
	grid.columns = maxi(1,quiz_task.get("choices",[]).size())
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",20)
	grid.add_theme_constant_override("v_separation",10)
	modal_body.add_child(grid)
	for choice in quiz_task.get("choices",[]):
		var button = _button(grid,str(choice.get("label","")),_answer_quiz.bind(str(choice.get("id",""))))
		if choice.get("item") is Dictionary:
			button.text = ""
			var choice_text = RubyText.new()
			choice_text.name = "ChoiceRuby"
			choice_text.min_reading_size = 22
			choice_text.group_spacing = 6.0
			choice_text.merge_adjacent_readings = false
			choice_text.show_reading_guides = false
			choice_text.font = GameFonts.japanese()
			choice_text.wrap_japanese = true
			choice_text.meaning_size = 24
			choice_text.set_word(choice.item,34,not gate_active)
			button.add_child(choice_text)
		button.custom_minimum_size = Vector2(260,300)
		button.add_theme_font_size_override("font_size",28)
		for state_name in ["normal","hover","pressed","disabled","focus"]:
			var style: StyleBox = UIStyle.textured_button(state_name)
			style.content_margin_left=18
			style.content_margin_right=18
			style.content_margin_top=28
			button.add_theme_stylebox_override(state_name,style)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var number: Label = _label(button,str(quiz_choices.size()+1),22,UIStyle.BRASS)
		number.position=Vector2(16,12)
		number.size=Vector2(36,30)
		quiz_choices.append(button)
	modal_footer = VBoxContainer.new()
	modal_footer_height = 112
	modal_card.add_child(modal_footer)
	modal_footer.minimum_size_changed.connect(_layout)
	quiz_feedback = UIStyle.TooltipLabel.new()
	quiz_feedback.set("ruby_context_words",_display_reading_context())
	quiz_feedback.text = "정답이면 전장에 맞는 지원을 무작위로 받습니다. 힌트를 사용하면 지원이 약해집니다."
	if gate_active: quiz_feedback.text = "한 문제라도 틀리면 복습 후 처음부터 다시 응시합니다."
	quiz_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quiz_feedback.add_theme_font_size_override("font_size",20)
	quiz_feedback.add_theme_color_override("font_color",Color("c6b482"))
	quiz_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_footer.add_child(quiz_feedback)
	quiz_feedback.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	modal_footer.add_child(row)
	quiz_hint_button = _button(row,"힌트 · 뜻 보기",_quiz_hint)
	if gate_active:
		quiz_hint_button.text = "복습 · 이번 응시 종료"
		quiz_hint_button.tooltip_text = "정답과 설명을 봅니다. 이번 응시는 통과하지 못하며 처음부터 다시 응시할 수 있습니다."
	quiz_hint_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var listen = _button(row,"일본어 듣기",_listen_quiz)
	quiz_listen_button = listen
	listen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	listen.disabled = not _reading_available()
	if gate_active: listen.disabled = true
	listen.tooltip_text = "이 PC에는 일본어 읽기 음성이 없습니다." if listen.disabled else "일본어를 다시 듣습니다."
	quiz_continue_button = _button(row,"건너뛰고 전투 복귀",_continue_battle)
	quiz_continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quiz_continue_button.custom_minimum_size.y = 42
	if gate_active: quiz_continue_button.text = "시험 나가기"
	if quiz_hinted:
		quiz_ruby.set_word(quiz_word,36,true)
		quiz_hint_button.disabled = true
	if quiz_resolved:
		quiz_ruby.set_word(quiz_word,36,true)
		for button in quiz_choices:
			button.disabled = true
		quiz_hint_button.disabled = true
		quiz_feedback.text = quiz_feedback_text
		quiz_continue_button.text = "전투로 복귀  ›"
		if gate_active: quiz_continue_button.text = "다음 문제  ›"
		_style_quiz_result()
	_layout()
	learning_transition.present(modal,quiz_choices,modal_footer,"解禁試験 · 해금 시험" if gate_active else "補給任務 · 보급 임무",quiz_resolved)

func _show_context_task() -> void:
	_cancel_deployment_drag()
	_close_modal(false)
	modal_context = "context"
	context_task_active = true
	game.set_input_enabled(false)
	learning_field.set_stage_background(str(current_map.get("background","")),current_map)
	if troops_3d.uses_world_geometry():
		learning_field.set_world_presentation(current_map,troops_3d.viewport.get_texture(),_project_learning_anchor,_project_learning_world_focus)
	_layout()
	learning_field.begin_choice(quiz_task.get("mission",{}),_reading_available())
	if quiz_hinted:
		learning_field.show_hint()
	if quiz_resolved:
		learning_field.show_result(quiz_outcome_correct,quiz_feedback_text,quiz_selected_id)
	_on_state(game.snapshot())
	learning_transition.present(learning_field,learning_field.target_buttons,learning_field.action_card,"援軍の要請 · 원군 요청",quiz_resolved)

func _project_learning_anchor(canonical: Vector2) -> Vector2:
	if troops_3d.field_size.x<=0 or troops_3d.field_size.y<=0:
		return Vector2(INF,INF)
	return troops_3d.model_to_field_point(canonical)/troops_3d.field_size

func _project_learning_world_focus(world_point: Vector3) -> Vector2:
	if not world_point.is_finite() or troops_3d.field_size.x<=0 or troops_3d.field_size.y<=0:
		return Vector2(INF,INF)
	return troops_3d.project_world_to_field(world_point)/troops_3d.field_size

func _listen_quiz(automatic: bool = false) -> void:
	if gate_active and not quiz_resolved: return
	if not _learning_screen_active() or not learning_transition.accepts_actions():
		return
	var text: String = str(quiz_task.get("mission",{}).get("report",{}).get("jp","")) if str(quiz_task.get("kind",""))=="context" else str(quiz_word.get("jp",""))
	_speak(text,automatic)

func _quiz_hint() -> void:
	if quiz_resolved or quiz_task.is_empty() or not _learning_screen_active() or not learning_transition.accepts_answers():
		return
	if gate_active:
		_apply_gate_answer(unlock_gate.hint())
		return
	quiz_hinted = true
	lesson_session.set_hinted(str(quiz_task.get("id","")))
	_announce("hint",str(quiz_task.get("id",""))+":hint")
	if context_task_active:
		learning_field.show_hint()
		return
	quiz_ruby.set_word(quiz_word,36,true)
	quiz_feedback.text = "힌트: %s  ·  정답이면 약한 전장 지원" % str(quiz_word.get("ko",""))
	quiz_hint_button.disabled = true

func _answer_quiz(answer_id: String) -> void:
	if quiz_resolved or quiz_task.is_empty() or modal_context!="quiz" or not learning_transition.accepts_answers():
		return
	if gate_active:
		quiz_selected_id = answer_id
		_apply_gate_answer(unlock_gate.answer(answer_id))
		return
	# Existing callers may use the visible answer label; the saved receipt uses its stable ID.
	var selected: String = answer_id
	for choice in quiz_task.get("choices",[]):
		if str(choice.get("label",""))==answer_id:
			selected = str(choice.get("id",""))
	var result: Dictionary = lesson_session.record(quiz_task,selected,quiz_hinted)
	if not bool(result.get("accepted",false)):
		quiz_feedback.text = progress.save_error if not progress.save_error.is_empty() else "이미 처리한 임무입니다. 다음 전투로 진행하십시오."
		return
	quiz_hinted = bool(result.get("hinted",quiz_hinted))
	quiz_selected_id = selected
	quiz_resolved = true
	answers_total += 1
	_track_learning_result(str(quiz_task.get("kind","meaning")),bool(result.get("correct",false)))
	var correct: bool = bool(result.get("correct",false))
	quiz_outcome_correct = correct
	quiz_ruby.set_word(quiz_word,36,true)
	for button in quiz_choices:
		button.disabled = true
	quiz_hint_button.disabled = true
	if correct:
		answers_correct += 1
		var reward: Dictionary=game.grant_learning_reward(quiz_hinted,str(quiz_task.get("id","")),str(quiz_task.get("kind","meaning")))
		quiz_feedback.text = _learning_reward_message(reward)
		quiz_feedback.add_theme_color_override("font_color",Color("bbdba7"))
	else:
		quiz_feedback.text = "뜻은 ‘%s’입니다. 맞춤 복습에 반영했습니다." % str(quiz_word.get("ko",""))
		quiz_feedback.add_theme_color_override("font_color",Color("e0ba9a"))
	quiz_feedback_text = quiz_feedback.text
	quiz_continue_button.text = "전투로 복귀  ›"
	var correct_card: Control = _style_quiz_result()
	learning_transition.reveal_result(correct_card,quiz_feedback)
	_announce("correct" if correct else "incorrect",str(quiz_task.get("id",""))+":answer")
	if bool(progress.data.settings.get("voice",true)):
		_speak(str(quiz_word.jp),true)
	_rebuild_map_list()

func _style_quiz_result() -> Control:
	var correct_card: Control
	for index in range(quiz_choices.size()):
		var button: Button = quiz_choices[index]
		var choice_id: String = str(quiz_task.get("choices",[])[index].get("id",""))
		if choice_id == (gate_correct_choice if gate_active else str(quiz_task.get("answerId",""))):
			button.add_theme_stylebox_override("disabled",UIStyle.frame("253e42","8ebdaf",true))
			correct_card = button
		elif choice_id == quiz_selected_id:
			button.add_theme_stylebox_override("disabled",UIStyle.frame("44282c","bf817b",true))
		else:
			button.modulate = Color(.65,.70,.74,.85)
	return correct_card

func _learning_reward_message(reward: Dictionary) -> String:
	if not bool(reward.get("ok",false)): return "정답입니다. 이번 전투의 지원을 준비할 수 없습니다."
	return "정답 · %s 획득%s\n%s 전투 복귀 후 발동합니다." % [str(reward.nameKo)," · 힌트 지원" if bool(reward.get("hinted",false)) else "",str(reward.effectKo)]

func _answer_context(target_id: String) -> void:
	if not context_task_active or quiz_resolved or quiz_task.is_empty() or not learning_transition.accepts_answers():
		return
	var result: Dictionary = lesson_session.record(quiz_task,target_id,quiz_hinted)
	if not bool(result.get("accepted",false)):
		_toast(progress.save_error if not progress.save_error.is_empty() else "이미 처리한 임무입니다.")
		return
	quiz_hinted = bool(result.get("hinted",quiz_hinted))
	quiz_selected_id = target_id
	quiz_resolved = true
	answers_total += 1
	_track_learning_result("context",bool(result.get("correct",false)))
	var correct: bool = bool(result.get("correct",false))
	quiz_outcome_correct = correct
	var mission: Dictionary = quiz_task.get("mission",{})
	var message: String
	if correct:
		answers_correct += 1
		var location: Dictionary = mission.get("action",{}).get("position",{})
		var support_anchors: Dictionary = game.config.get("historicalBattlefield",{}).get("learningSupportAnchors",{})
		location = support_anchors.get(str(mission.get("id",quiz_task.get("id",""))),location)
		var reward: Dictionary=game.grant_learning_reward(quiz_hinted,str(quiz_task.get("id","")),"context",Vector2(float(location.get("x",0.5)),float(location.get("y",0.5))))
		message = _learning_reward_message(reward)+"\n"+str(mission.get("successKo","보고를 이해했습니다."))
	else:
		var answer_name: String = ""
		for target in mission.get("targets",[]):
			if str(target.get("id",""))==str(mission.get("answerId","")):
				answer_name = str(target.get("label",{}).get("ko",""))
		message = "요청한 위치는 ‘%s’입니다.\n이 표현을 맞춤 복습에 반영했습니다." % answer_name
	learning_field.show_result(correct,message,target_id)
	quiz_feedback_text = message
	var correct_card: Control
	for index in range(learning_field.target_buttons.size()):
		if str(mission.get("targets",[])[index].get("id","")) == str(mission.get("answerId","")):
			correct_card = learning_field.target_buttons[index]
			break
	learning_transition.reveal_result(correct_card,learning_field.feedback)
	_announce("correct" if correct else "incorrect",str(quiz_task.get("id",""))+":answer")
	_rebuild_map_list()

func _track_learning_result(kind: String, correct: bool) -> void:
	var counts: Dictionary = learning_results.get(kind,{"correct":0,"attempts":0})
	counts.attempts = int(counts.attempts)+1
	if correct:
		counts.correct = int(counts.correct)+1
	learning_results[kind] = counts

func _continue_battle(escape_requested: bool = false) -> void:
	if quiz_task.is_empty() or not _learning_screen_active() or learning_transition.phase == "exiting":
		return
	if not escape_requested and not learning_transition.accepts_actions():
		return
	if gate_active:
		_continue_gate(escape_requested)
		return
	_stop_narration()
	learning_transition.begin_return()

func _start_gate_from_catalog(tier: int, index: int) -> void:
	if maps.is_empty(): return
	_choose_stage(tier,index)
	if current_tier!=tier or current_index!=index: return
	_start_gate()

func _start_gate() -> void:
	var id: String = str(current_map.get("id",""))
	if not progress.map_unlocked(id) or not progress.map_cleared(id): return
	var script = load("res://native/learning_gate.gd")
	if script==null: return
	var next_gate: RefCounted = script.new()
	var started: Dictionary = next_gate.start(current_lesson,id)
	if not bool(started.get("ok",false)):
		_toast(str(started.get("errorKo","시험 문항을 준비할 수 없습니다.")))
		return
	_stop_narration()
	_cancel_learning_transition()
	_close_modal(false)
	learning_field.clear()
	unlock_gate = next_gate
	gate_active = true
	gate_saved = false
	gate_correct_choice = ""
	quiz_task.clear()
	narration_serial += 1
	narration_battle_id = "exam:%s:%d" % [id,narration_serial]
	_show_quiz()

func _apply_gate_answer(result: Dictionary) -> void:
	if not bool(result.get("accepted",false)): return
	quiz_resolved = true
	quiz_selected_id = str(result.get("selectedId",quiz_selected_id))
	gate_correct_choice = str(result.get("correctChoiceId",""))
	quiz_word = result.get("revealItem",quiz_word)
	quiz_ruby.set_word(quiz_word,36,true)
	for button in quiz_choices: button.disabled = true
	quiz_hint_button.disabled = true
	quiz_listen_button.disabled = not _reading_available()
	var receipt: Dictionary = unlock_gate.snapshot()
	if bool(receipt.get("passed",false)):
		gate_saved = progress.record_assessment(unlock_gate)
		if not gate_saved:
			quiz_feedback.text = "전 문항 정답입니다. 저장을 다시 시도해야 다음 전장이 열립니다. " + progress.save_error
			quiz_continue_button.text = "저장 다시 시도"
		elif _next_registered_stage().is_empty():
			quiz_feedback.text = "전 문항 정답 · 시험 기록 저장 완료\n다음 전장은 준비 중입니다."
			quiz_continue_button.text = "전장 선택으로 돌아가기"
		else:
			quiz_feedback.text = "전 문항 정답 · 다음 전장 해금 완료"
			quiz_continue_button.text = "다음 전장에 출진  ›"
	elif bool(receipt.get("complete",false)):
		quiz_feedback.text = "이번 응시는 통과하지 못했습니다. 원문과 뜻을 복습한 뒤 다시 응시하십시오."
		quiz_continue_button.text = "처음부터 다시 응시"
	else:
		quiz_feedback.text = "정답 · %d / %d 확인했습니다." % [int(receipt.get("correctCount",0)),int(receipt.get("count",0))]
		quiz_continue_button.text = "다음 문제  ›"
	quiz_feedback.text += "\n"+str(result.get("explanationKo",""))
	quiz_feedback_text = quiz_feedback.text
	learning_transition.reveal_result(_style_quiz_result(),quiz_feedback)
	_announce("correct" if bool(result.get("correct",false)) else "incorrect",str(quiz_task.get("id",""))+":answer")
	_rebuild_map_list()

func _continue_gate(exit_requested: bool) -> void:
	if exit_requested or not quiz_resolved:
		unlock_gate.skip()
		_leave_gate(false)
		return
	var receipt: Dictionary = unlock_gate.snapshot()
	if bool(receipt.get("passed",false)):
		if not gate_saved: gate_saved = progress.record_assessment(unlock_gate)
		if gate_saved: _leave_gate(true)
		else: quiz_feedback.text = "진도 저장에 실패했습니다. 저장 다시 시도를 눌러 주십시오. " + progress.save_error
		return
	if bool(receipt.get("complete",false)): unlock_gate.retry()
	_stop_narration()
	_cancel_learning_transition()
	_close_modal(false)
	quiz_task.clear()
	quiz_resolved = false
	quiz_hinted = false
	gate_correct_choice = ""
	_show_quiz()

func _leave_gate(open_next: bool) -> void:
	var next_stage: Dictionary = _next_registered_stage()
	_stop_narration()
	_cancel_learning_transition()
	_close_modal(false)
	gate_active = false
	quiz_task.clear()
	context_task_active = false
	learning_field.clear()
	if open_next and not next_stage.is_empty():
		_choose_stage(int(next_stage.tier),int(next_stage.index))
	else:
		_show_catalog()
		if open_next and int(current_map.get("stageNumber",1))<40:
			_toast("시험 기록을 저장했습니다. 다음 전장은 준비 중입니다.")

func _finish_continue_battle() -> void:
	if quiz_task.is_empty() or battle_finished:
		return
	progress.write_save()
	if not quiz_task.is_empty() and not quiz_resolved:
		lesson_session.skip_task(quiz_task)
	quiz_task.clear()
	quiz_selected_id = ""
	context_task_active = false
	quiz_resolved = false
	learning_field.clear()
	field_clip.show()
	army_toolbar.show()
	learning_panel.show()
	_layout()
	_close_modal(false)
	game.continue_wave()
	_on_state(game.snapshot())

func _on_battle_finished(result: Dictionary) -> void:
	_cancel_deployment_drag()
	_cancel_learning_transition()
	var already_finished = battle_finished
	if not already_finished:
		_stop_narration()
	battle_finished = true
	var won = last_victory if already_finished else bool(result.get("victory",result.get("won",false)))
	last_victory = won
	if not already_finished and battle_audio != null:
		var audio_result = result.duplicate()
		audio_result["mapId"] = str(current_map.get("id", ""))
		battle_audio.consume_finish(audio_result)
	context_task_active = false
	quiz_task.clear()
	learning_field.clear()
	_set_music_context(false)
	if won and not already_finished and not isolated_candidate:
		last_campaign_reward = progress.complete_map(str(current_map.id),{"seen":seen_this_run.size(),"correct":answers_correct,"attempts":answers_total})
	elif not already_finished and not isolated_candidate:
		progress.write_save()
	_rebuild_map_list()
	_open_modal()
	modal_context = "result"
	_modal_label("勝利  ·  방어 성공" if won else "撤退  ·  거점 함락",30,"e5ca8d")
	_modal_label(str(current_map.title),23)
	if won and not current_story.is_empty():
		_modal_label(str(current_story.get("outroKo","")),22,"d9c79b").name="StoryAftermath"
		if not str(current_story.get("nextStageId","")).is_empty():
			_modal_label(str(current_story.get("bridgeKo","")),20,"b7c3cc").name="StoryNextJourney"
		_modal_label("역사 기록 · "+str(current_story.get("historyOutcomeKo","")),20,"aebfcc")
	if won and int(current_map.get("stageNumber",0))==40 and progress.campaign_unified():
		var ending: Dictionary = campaign_story.get("ending",{})
		_modal_label(str(ending.get("titleKo","天下統一 · 전국 통일")),36,"e5ca8d").name="UnificationEnding"
		_modal_label(str(ending.get("textKo","40개 전장을 지나 전국 통일을 완수했습니다.")),22,"d9c79b")
	var battle_elapsed: float = float(result.get("battleElapsedSeconds",result.get("elapsed",state.get("battleElapsedSeconds",state.get("elapsed",0)))))
	_modal_label("%d분 모드 · 전투 시간 %s / %s" % [active_battle_minutes,_battle_clock_text(battle_elapsed),_battle_clock_text(active_battle_minutes*60)],20,"d9c79b").name = "BattleModeResult"
	_modal_label("이번 전투에서 만난 단어  %d / %d\n보급 임무  %d / %d 정답" % [seen_this_run.size(),learning_words.size(),answers_correct,answers_total],20)
	var categories: Dictionary = {"meaning":"단어 뜻","sentence":"문장 이해","context":"전장 보고","listening":"듣기"}
	var lines: Array[String] = []
	for kind in categories:
		var counts: Dictionary = learning_results.get(kind,{"correct":0,"attempts":0})
		lines.append("%s  %d / %d" % [categories[kind],int(counts.correct),int(counts.attempts)])
	_modal_label("이번 전투의 확인 기록\n"+"  ·  ".join(lines),20,"c1d0b5")
	_modal_label("시간을 두고 뜻과 문장을 확인한 단어  %d / 900" % progress.mastered_count(),20,"d9c79b")
	if won:
		_modal_label("軍資金 · 군자금 +%d / 보유 %d" % [int(last_campaign_reward.get("currency",0)),int(progress.data.army.currency)],21,"e5c778")
		for unit_id in last_campaign_reward.get("unlocked",[]):
			_modal_label("解禁 · %s 해금! 다음 출진부터 소집할 수 있습니다." % str(progress.unit_definition(str(unit_id)).name),17,"b9d4ab")
			var training_button = _button(modal_body,"演武 · %s 훈련 던전" % str(progress.unit_definition(str(unit_id)).name),_show_unit_training.bind(str(unit_id)))
			training_button.custom_minimum_size.y = 44
			training_button.name = "FirstTraining_%s" % str(unit_id)
	_modal_label("오답·힌트를 쓴 표현은 맞춤 복습에 반영됩니다.\n다른 문장과 시간을 두고 확인한 기록을 도감에서 볼 수 있습니다.",20,"acbdac")
	var retry = _button(modal_body,"같은 지도 다시 출진",_retry_battle)
	retry.custom_minimum_size.y = 46
	var next_stage: Dictionary = _next_registered_stage()
	if not _candidate_display_allowed() and int(current_map.get("stageNumber",1))<40 and progress.map_cleared(str(current_map.id)) and not progress.map_assessed(str(current_map.id)):
		var exam_button = _button(modal_body,"다음 지도 해금 시험  ›",_start_gate)
		exam_button.name = "ResultUnlockExam"
		exam_button.custom_minimum_size.y = 46
		_modal_label("새 단어 %d개 + 문법 %d개 · 힌트 없이 전 문항 정답이어야 다음 지도가 열립니다." % [current_lesson.get("newWords",[]).size(),current_lesson.get("grammarSteps",[]).size()],20,"e5d09f")
	elif not _candidate_display_allowed() and not next_stage.is_empty():
		var next = _button(modal_body,"다음 지도  ›",_choose_stage.bind(int(next_stage.tier),int(next_stage.index)))
		next.custom_minimum_size.y = 46
		next.disabled = not progress.map_unlocked(str(next_stage.stage.id))
	if not _candidate_display_allowed() and next_stage.is_empty() and int(current_map.get("stageNumber",1))<40:
		_modal_label("다음 전장은 준비 중입니다. 현재 전장은 다시 출진할 수 있습니다.",20,"acbdac")
	var study = _button(modal_body,"학습 도감 열기",_show_study)
	study.custom_minimum_size.y = 42
	_button(modal_body,"戦場選択 · 다른 전장 선택",_show_catalog).custom_minimum_size.y = 42
	_button(modal_body,"兵営 · 병영에서 영구 훈련",func(): _show_home(); _show_barracks()).custom_minimum_size.y = 42
	_layout_narration_subtitle()
	if not already_finished:
		if battle_narrator != null:
			battle_narrator.set_paused(false)
		if battle_announcer != null:
			battle_announcer.set_paused(false)
		_narrate("victory" if won else "defeat","result")

func _retry_battle() -> void:
	if battle_minutes!=active_battle_minutes:
		_choose_battle_minutes(active_battle_minutes)
	_select_map(current_index)

func _open_modal() -> void:
	_cancel_deployment_drag()
	_close_modal(false)
	game.set_input_enabled(false)
	modal = Control.new()
	modal.z_index = 80
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(modal)
	var shade = ColorRect.new()
	shade.color = Color(0.045,0.033,0.02,0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(shade)
	modal_card = _panel(modal,"14202afb","66737b")
	modal_card.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_scroll = ScrollContainer.new()
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_card.add_child(modal_scroll)
	modal_body = VBoxContainer.new()
	modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_body.add_theme_constant_override("separation",14)
	modal_scroll.add_child(modal_body)
	_layout()

func _modal_label(text: String, text_size: int = 16, color: String = "dddac5") -> Label:
	var label = UIStyle.TooltipLabel.new()
	if RubyReadings.contains_kanji(text): label.ruby_context_words=_display_reading_context()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text=text
	label.add_theme_font_size_override("font_size",maxi(20,text_size))
	label.add_theme_color_override("font_color",Color(color))
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	modal_body.add_child(label)
	return label

func _close_modal(resume: bool = true) -> void:
	if modal_context == "quiz":
		_cancel_learning_transition()
	modal_footer=null
	quiz_grid=null
	modal_footer_height = 48
	if modal != null:
		modal.queue_free()
		modal = null
	if game != null:
		game.set_input_enabled(not context_task_active and (learning_transition == null or not learning_transition.is_busy()))
	if resume and resume_after_modal:
		game.pause_battle()
	resume_after_modal = false
	modal_context = ""
	_set_intermission_presentation(context_task_active)

func _show_study() -> void:
	if maps.is_empty() and not _candidate_display_allowed(): return
	_stop_narration()
	_cancel_learning_transition()
	if not quiz_task.is_empty() and not quiz_resolved:
		quiz_hinted = true
		lesson_session.set_hinted(str(quiz_task.get("id","")))
	if context_task_active:
		context_task_active = false
		learning_field.suspend_choice()
	var was_active = battle_started and not battle_finished and modal == null and not bool(state.get("paused",false))
	if was_active:
		game.pause_battle()
	_open_modal()
	modal_context = "study"
	resume_after_modal = was_active
	_modal_label("言葉の記録  ·  학습 도감",27,"ddc38b")
	var source_lesson: Dictionary = current_lesson if catalog_study_lesson.is_empty() else catalog_study_lesson
	var source_words: Array = learning_words if catalog_study_lesson.is_empty() else catalog_study_words
	var source_plan: Dictionary = {}
	for plan in learning_plans.get("stages",{}).values():
		if str(plan.get("lessonId",""))==str(source_lesson.get("id","")):
			source_plan = plan
			break
	_modal_label((str(current_map.title) if catalog_study_title.is_empty() else catalog_study_title)+"\n상황 표현 · 단어 · 읽기 · 뜻 · 예문",14,"acbdab")
	_modal_label(str(source_plan.get("goalKo","")),20,"d8c595")
	_add_grammar_steps(modal_body,source_lesson)
	_modal_label("뜻 · 문장 · 듣기를 따로 확인합니다.\n시간을 두고 다른 문장에서도 이해한 단어를 기억 확인으로 표시합니다.",20,"bbc7b3")
	var search = LineEdit.new()
	search.placeholder_text = "일본어 · 히라가나 · 한국어 검색"
	search.custom_minimum_size.y = 41
	modal_body.add_child(search)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 260
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_body.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",9)
	scroll.add_child(list)
	var fill = func(query: String):
		for child in list.get_children():
			child.queue_free()
		var expressions: Array = source_lesson.get("expressions",[]).duplicate()
		for mission in source_plan.get("missions",[]):
			expressions.append(mission.get("report",{}))
		for expression in expressions:
			if int(expression.get("minimumGrammarOrder",0))>int(source_lesson.get("grammarOrder",40)): continue
			var phrase_text = "%s %s %s" % [expression.jp,expression.reading,expression.ko]
			if not query.is_empty() and not phrase_text.contains(query):
				continue
			var phrase_row = HBoxContainer.new()
			list.add_child(phrase_row)
			var phrase = RubyText.new()
			phrase.font = GameFonts.japanese()
			phrase.wrap_japanese = true
			phrase.set_word(expression,26)
			phrase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			phrase_row.add_child(phrase)
			var phrase_listen = _button(phrase_row,"듣기",func(): _speak(str(expression.jp)))
			phrase_listen.custom_minimum_size.x = 62
		for word in source_words:
			var haystack = "%s %s %s %s %s" % [word.jp,word.reading,word.ko,str(word.get("example",{}).get("jp","")),str(word.get("transferExample",{}).get("jp",""))]
			if not query.is_empty() and not haystack.contains(query):
				continue
			var entry = VBoxContainer.new()
			entry.add_theme_constant_override("separation",5)
			list.add_child(entry)
			var row = HBoxContainer.new()
			row.add_theme_constant_override("separation",12)
			entry.add_child(row)
			var ruby = RubyText.new()
			ruby.font = GameFonts.japanese()
			ruby.custom_minimum_size.x = 175
			ruby.set_word(word,29)
			row.add_child(ruby)
			var status_label = _label(row,_learning_status_line(str(word.id)),20,"c4cdb8")
			status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var listen = _button(row,"듣기",func(): _speak(str(word.jp)))
			listen.custom_minimum_size.x = 62
			listen.disabled = not _reading_available()
			for key in ["example","transferExample"]:
				var example: Dictionary = word.get(key,{})
				if example.is_empty():
					continue
				var text = RubyText.new()
				text.font = GameFonts.japanese()
				text.wrap_japanese = true
				text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				text.set_word(example,26,true)
				entry.add_child(text)
	search.text_changed.connect(fill)
	fill.call("")
	var close = _button(modal_body,"図鑑選択 · 도감 목록으로" if not catalog_study_lesson.is_empty() else "戦場へ · 전장으로 돌아가기",_return_from_study)
	close.custom_minimum_size.y = 43

func _learning_status_line(word_id: String) -> String:
	var meaning: Dictionary = progress.learning_status(word_id,"meaning")
	var context: Dictionary = progress.learning_status(word_id,"context")
	var listening: Dictionary = progress.learning_status(word_id,"listening")
	return "뜻 %d · 문장 %d · 듣기 %d\n%s / %s" % [int(meaning.get("unhintedCorrect",0)),int(context.get("unhintedCorrect",0)),int(listening.get("unhintedCorrect",0)),str(meaning.get("statusKo","아직 확인 전")),str(context.get("statusKo","문장 확인 전"))]

func _return_from_study() -> void:
	if not catalog_study_lesson.is_empty():
		_close_modal(false)
		catalog_study_lesson.clear()
		catalog_study_words.clear()
		catalog_study_title = ""
		game.set_input_enabled(false)
		ui.hide()
		field_clip.hide()
		front_end.show_catalog(front_end.selected_tier,true)
		return
	var return_to_result = battle_finished
	var return_to_briefing = not battle_started
	var return_to_quiz = bool(state.get("betweenWaves",state.get("waiting",false)))
	_close_modal()
	if return_to_result:
		_on_battle_finished({"victory":bool(state.get("victory",false))})
	elif return_to_briefing:
		_show_briefing()
	elif return_to_quiz:
		_show_quiz()

func _setup_audio() -> void:
	battle_audio = BattleAudio.new()
	battle_audio.set_presentation_mirrored(game.presentation_mirrored)
	add_child(battle_audio)
	battle_audio.setup()
	battle_audio.set_enabled(bool(progress.data.settings.get("effects",true)))
	battle_audio.set_volume(float(progress.data.settings.get("effectsVolume",.8)))
	player = AudioStreamPlayer.new()
	var music_bus: int = AudioServer.get_bus_index("SengokuMusic")
	if music_bus<0:
		AudioServer.add_bus()
		music_bus = AudioServer.bus_count-1
		AudioServer.set_bus_name(music_bus,"SengokuMusic")
	AudioServer.set_bus_send(music_bus,"Master")
	player.bus = "SengokuMusic"
	add_child(player)
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/music.json"))
	for track in library.get("tracks",[]):
		music_by_stage[str(track.stageId)] = track
	var lobby_path: String = "res://assets/music/lobby/manifest.json"
	if FileAccess.file_exists(lobby_path):
		var lobby_library: Variant = JSON.parse_string(FileAccess.get_file_as_string(lobby_path))
		if lobby_library is Dictionary:
			lobby_music = lobby_library
	player.volume_db = -16
	music_button.text = "음악 켜짐" if bool(progress.data.settings.get("music",true)) else "음악 꺼짐"
	var voices = DisplayServer.tts_get_voices_for_language("ja")
	if not voices.is_empty():
		japanese_voice = str(voices[0])
	voice_director = VoiceDirector.new()
	add_child(voice_director)
	voice_director.setup()
	voice_director.speech_started.connect(_on_reading_started)
	voice_director.speech_finished.connect(_on_reading_finished)
	battle_narrator = BattleNarrator.new()
	add_child(battle_narrator)
	battle_narrator.bind_director(voice_director,"male")
	battle_narrator.clip_started.connect(_on_narration_started)
	battle_narrator.clip_finished.connect(_on_narration_finished)
	battle_narrator.setup(bool(progress.data.settings.get("voice",true)))
	battle_announcer = BattleAnnouncer.new()
	add_child(battle_announcer)
	battle_announcer.bind_director(voice_director,"female")
	battle_announcer.clip_started.connect(_on_announcement_started)
	battle_announcer.clip_finished.connect(_on_announcement_finished)
	battle_announcer.setup(bool(progress.data.settings.get("voice",true)))
	_apply_audio_settings()
	voice_button.text = "음성 켜짐" if _voice_available() and bool(progress.data.settings.get("voice",true)) else "음성 꺼짐"
	voice_button.tooltip_text = "남성 전투·여성 안내 성우 음성 · 일본어 학습 읽기" if _reading_available() else "남성 전투·여성 안내 성우 음성 · 이 PC의 학습 읽기 음성은 없습니다."

func _reading_available() -> bool:
	return not japanese_voice.is_empty() or (voice_director!=null and voice_director.learning_available())

func _play_mission_briefing() -> bool:
	var text: String = str(current_story.get("briefingJP",""))
	if text.is_empty() or narration_battle_id==briefing_played_battle_id or voice_director==null:
		return false
	if not bool(progress.data.settings.get("voice",true)) or progress.audio_volume("masterVolume")<=0.0 or progress.audio_volume("voiceVolume")<=0.0:
		return false
	if not voice_director.can_speak(text): return false
	briefing_expected_text = text
	if not voice_director.speak(text,"",true):
		briefing_expected_text = ""
		return false
	briefing_played_battle_id = narration_battle_id
	return true

func _on_reading_started(text: String, _cached: bool) -> void:
	if text!=briefing_expected_text or text.is_empty(): return
	var caption: Dictionary = {"jp":text,"reading":str(current_story.get("briefingReading","")),"parts":current_story.get("briefingParts",[]),"ko":str(current_story.get("briefingKo",""))}
	narration_caption_remaining = _caption_dwell_seconds(caption,10.0)
	narration_subtitle.set_word(caption,26,true)
	_layout_narration_subtitle()
	narration_subtitle.show()
	_apply_voice_mix(true)

func _on_reading_finished(text: String, interrupted: bool) -> void:
	if text!=briefing_expected_text or text.is_empty(): return
	briefing_expected_text = ""
	if interrupted:
		narration_caption_remaining = 0.0
		narration_subtitle.hide()
	else:
		narration_caption_remaining = maxf(narration_caption_remaining,2.0)

func _voice_available() -> bool:
	return _reading_available() or (battle_narrator!=null and battle_narrator.is_ready) or (battle_announcer!=null and battle_announcer.is_ready)

func _apply_audio_settings() -> void:
	var master: float = progress.audio_volume("masterVolume")
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(master,0.00001)))
	AudioServer.set_bus_mute(0,master<=0.0)
	var music: float = progress.audio_volume("musicVolume")
	var music_bus: int = AudioServer.get_bus_index("SengokuMusic")
	if music_bus>0:
		AudioServer.set_bus_volume_db(music_bus,linear_to_db(maxf(music,0.00001)))
		AudioServer.set_bus_mute(music_bus,music<=0.0)
	if battle_audio!=null:
		battle_audio.set_volume(progress.audio_volume("effectsVolume"))
	for voice in [battle_narrator,battle_announcer]:
		if voice!=null:
			voice.set_volume(progress.audio_volume("voiceVolume") if master>0.0 else 0.0)
	# System learning speech is outside Godot's mixer and needs the same gains.
	if voice_director!=null:
		voice_director.set_audio_levels(master,progress.audio_volume("voiceVolume"))
	_update_voice_mix()

func _set_audio_volume(key: String, value: float) -> void:
	if not progress.set_audio_volume(key,value):
		return
	_apply_audio_settings()
	if audio_save_timer==null:
		audio_save_timer = Timer.new()
		audio_save_timer.one_shot = true
		audio_save_timer.timeout.connect(_save_audio_settings)
		add_child(audio_save_timer)
	# Apply each drag immediately, then save only once the hand stops moving.
	audio_save_timer.start(0.3)

func _save_audio_settings() -> void:
	if not progress.write_save():
		_toast(progress.save_error)

func _apply_voice_mix(speaking: bool) -> void:
	if battle_audio!=null:
		battle_audio.set_voice_active(speaking)
	if player!=null:
		var level: float = (-27 if speaking else -20 if music_context == "battle" else -16) + music_fade_db
		if player.volume_db!=level:
			player.volume_db = level

func _update_voice_mix() -> void:
	_apply_voice_mix(voice_director!=null and voice_director.is_voice_active())

func _reset_narration_battle() -> void:
	_stop_narration()
	briefing_played_battle_id = ""
	narration_battle_id = ""
	narration_strong_reported = false
	narration_danger_reported = false
	for voice in [battle_narrator,battle_announcer]:
		if voice==null: continue
		voice.reset_battle()
		voice.set_enabled(bool(progress.data.settings.get("voice",true)))
		voice.set_paused(false)
	if narration_subtitle!=null:
		narration_subtitle.hide()

func _narrate(event_key: String, event_id: String) -> bool:
	if battle_narrator==null or narration_battle_id.is_empty() or closing or not bool(progress.data.settings.get("voice",true)):
		return false
	if front_end.visible or barracks.visible or unit_training.visible or _learning_screen_active():
		return false
	return battle_narrator.enqueue(event_key,{"mapId":str(current_map.get("id","")),"battleId":narration_battle_id,"eventId":narration_battle_id+":"+event_id})

func _on_narration_started(caption: Dictionary) -> void:
	narration_caption_remaining = _caption_dwell_seconds(caption,7.0)
	narration_subtitle.set_word(caption,26,true)
	_layout_narration_subtitle()
	narration_subtitle.show()
	_apply_voice_mix(true)

func _on_narration_finished(caption: Dictionary) -> void:
	if narration_subtitle!=null and (bool(caption.get("interrupted",false)) or narration_caption_remaining<=0.0):
		narration_subtitle.hide()
	_apply_voice_mix(voice_director!=null and voice_director.is_voice_active())

func _announce(event_key: String, event_id: String) -> bool:
	if battle_announcer==null or narration_battle_id.is_empty() or closing or (battle_finished and not gate_active) or not bool(progress.data.settings.get("voice",true)):
		return false
	if front_end.visible or barracks.visible or unit_training.visible:
		return false
	return battle_announcer.enqueue(event_key,{"mapId":str(current_map.get("id","")),"battleId":narration_battle_id,"eventId":narration_battle_id+":"+event_id})

func _on_announcement_started(caption: Dictionary) -> void:
	announcement_caption_remaining = _caption_dwell_seconds(caption,4.5)
	announcement_subtitle.set_word(caption,26,true)
	_layout_announcement_subtitle()
	announcement_subtitle.show()
	_sync_announcement_reading()
	_apply_voice_mix(voice_director!=null and voice_director.is_voice_active())

func _on_announcement_finished(caption: Dictionary) -> void:
	if announcement_subtitle!=null and (bool(caption.get("interrupted",false)) or announcement_caption_remaining<=0.0):
		announcement_subtitle.hide()
		_sync_announcement_reading()
	_apply_voice_mix(voice_director!=null and voice_director.is_voice_active())

func _stop_narration() -> void:
	narration_caption_remaining = 0.0
	announcement_caption_remaining = 0.0
	briefing_expected_text = ""
	if voice_director!=null:
		voice_director.stop()
	if narration_subtitle!=null:
		narration_subtitle.hide()
	if announcement_subtitle!=null:
		announcement_subtitle.hide()
		_sync_announcement_reading()
	_apply_voice_mix(false)

func _set_music_context(in_battle: bool) -> void:
	if player == null or current_map.is_empty():
		return
	music_context = "battle" if in_battle else "stage"
	_play_music_track(music_by_stage.get(str(current_map.id),{}),"이 전장의 음악")

func _set_lobby_music() -> void:
	if player == null:
		return
	music_context = "lobby"
	_play_music_track(lobby_music,"본진의 음악")

func _play_music_track(track: Dictionary, label: String) -> void:
	current_music = track
	var path: String = str(current_music.get("path",""))
	if path.is_empty() or not ResourceLoader.exists(path):
		player.stop()
		push_error("음악을 찾을 수 없습니다: " + label + " " + path)
		return
	music_button.tooltip_text = "%s: %s\n%s · %s\n%s" % [label,str(current_music.title),str(current_music.author),str(current_music.license),str(current_music.source)]
	if music_resource_path == path:
		_update_voice_mix()
		return
	if music_fade != null and music_fade.is_valid():
		music_fade.kill()
	player.stop()
	player.stream = load(path)
	if player.stream is AudioStreamOggVorbis:
		player.stream.loop = true
	if player.stream is AudioStreamMP3:
		player.stream.loop = true
	music_resource_path = path
	music_fade_db = -24.0 if bool(progress.data.settings.get("music",true)) else 0.0
	_update_voice_mix()
	if bool(progress.data.settings.get("music",true)):
		player.play()
		music_fade = create_tween()
		music_fade.tween_property(self,"music_fade_db",0.0,0.35)

func _toggle_music() -> void:
	var enabled = not bool(progress.data.settings.get("music",true))
	progress.data.settings.music = enabled
	progress.write_save()
	if music_fade != null and music_fade.is_valid():
		music_fade.kill()
	music_fade_db = 0.0
	_update_voice_mix()
	if enabled:
		player.play()
	else:
		player.stop()
	music_button.text = "음악 켜짐" if enabled else "음악 꺼짐"

func _toggle_voice() -> void:
	if not _voice_available():
		_toast("일본어 음성을 사용할 수 없습니다. 글자와 읽기는 화면으로 확인하십시오.")
		return
	var enabled = not bool(progress.data.settings.get("voice",true))
	progress.data.settings.voice = enabled
	progress.write_save()
	voice_button.text = "음성 켜짐" if enabled else "음성 꺼짐"
	if not enabled:
		_stop_narration()
	for voice in [battle_narrator,battle_announcer]:
		if voice!=null:
			voice.set_enabled(enabled)

func _toggle_effects() -> void:
	var enabled: bool = not bool(progress.data.settings.get("effects",true))
	progress.data.settings.effects = enabled
	progress.write_save()
	battle_audio.set_enabled(enabled)

func _speak_current() -> void:
	if learning_index >= 0 and learning_index < learning_words.size():
		_speak(str(learning_words[learning_index].jp))

func _speak(text: String, automatic: bool = false) -> void:
	# Mission instructions keep the voice slot; an old automatic word should
	# neither interrupt the commander nor play after its caption has changed.
	if automatic and not briefing_expected_text.is_empty(): return
	if voice_director==null or not _reading_available():
		if not automatic: _toast("일본어 듣기 자료를 사용할 수 없습니다.")
		return
	if not bool(progress.data.settings.get("voice",true)):
		if not automatic: _toast("음성 설정을 켜면 일본어를 들을 수 있습니다.")
		return
	if progress.audio_volume("masterVolume")<=0.0 or progress.audio_volume("voiceVolume")<=0.0:
		if not automatic: _toast("전체·음성 음량을 올리면 일본어를 들을 수 있습니다.")
		return
	if not voice_director.speak(text,japanese_voice,not automatic) and not automatic:
		_toast("이 문장의 듣기 자료를 재생하지 못했습니다.")
	_apply_voice_mix(voice_director.is_voice_active())

func _toast(message: String) -> void:
	toast_label.set("ruby_context_words",_display_reading_context())
	toast_label.text = message
	toast_label.call("refresh_ruby")
	toast_clock = 4.0
	toast_label.visible = learning_field == null or not learning_field.report_card.visible or not progress.save_error.is_empty()
	if not progress.save_error.is_empty():
		toast_label.position = Vector2(game.field_rect.position.x+14,game.field_rect.end.y-144)
		toast_label.size.x = game.field_rect.size.x-200

func _input(event: InputEvent) -> void:
	if _handle_deployment_input(event):
		get_viewport().set_input_as_handled()
		return
	if unit_training!=null and unit_training.visible: return
	if learning_transition != null and learning_transition.is_busy() and ui.visible and not front_end.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_continue_battle(true)
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled()
		return
	if _learning_screen_active() and event is InputEventKey and event.echo and event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_SPACE,KEY_ENTER,KEY_KP_ENTER,KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		return
	if barracks != null and barracks.visible:
		return
	if context_task_active:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if front_end != null and not front_end.visible and modal == null and battle_started and not battle_finished:
			_toggle_pause()
			get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if unit_training!=null and unit_training.visible: return
	if barracks != null and barracks.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			barracks.hide()
			_return_from_barracks()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if context_task_active and not front_end.visible and modal==null:
		if event.keycode==KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_continue_battle()
		elif event.keycode in [KEY_1,KEY_2,KEY_3] and not quiz_resolved:
			get_viewport().set_input_as_handled()
			var index: int = event.keycode-KEY_1
			if index<learning_field.target_buttons.size():
				learning_field.target_buttons[index].pressed.emit()
		return
	if front_end.visible:
		if event.keycode == KEY_ESCAPE and front_end.view != "home":
			if front_end.battle_active:
				_resume_from_navigation()
			else:
				front_end.show_home()
		return
	if modal != null:
		if modal_context=="quiz":
			if event.keycode==KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_continue_battle()
			elif event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4] and not quiz_resolved:
				get_viewport().set_input_as_handled()
				var index: int=event.keycode-KEY_1
				if index<quiz_choices.size():
					quiz_choices[index].pressed.emit()
			return
		if event.keycode == KEY_ESCAPE:
			if modal_context == "study":
				_return_from_study()
			elif modal_context == "pause":
				_close_modal()
			elif modal_context in ["briefing","result"]:
				_show_catalog()
		return
	match event.keycode:
		KEY_ESCAPE:
			if not game.snapshot().get("pending",{}).is_empty():
				game.cancel_recruit()
			elif battle_started and not battle_finished:
				_show_pause_menu()
		KEY_R: _recruit()

func _show_pause_menu() -> void:
	_stop_narration()
	var was_running = not bool(state.get("paused",false))
	if was_running:
		game.pause_battle()
	_open_modal()
	modal_context = "pause"
	resume_after_modal = was_running
	_modal_label("作戦会議 · 작전 메뉴",29,"e1e6e9")
	_modal_label("일시 정지",20,"9cabb8")
	_button(modal_body,"続行 · 전투 계속",func(): _close_modal()).custom_minimum_size.y = 49
	_button(modal_body,"言葉図鑑 · 학습 도감",func(): _close_modal(); _show_study()).custom_minimum_size.y = 49
	_button(modal_body,"戦場選択 · 다른 전장 선택",_show_catalog).custom_minimum_size.y = 49
	_button(modal_body,"本陣へ · 시작 화면",_show_home).custom_minimum_size.y = 49
	var audio = _button(modal_body,"音楽 · 배경음악",_toggle_music)
	audio.toggle_mode = true
	audio.button_pressed = bool(progress.data.settings.get("music",true))
	audio.tooltip_text = music_button.tooltip_text
	audio.custom_minimum_size.y = 42
	var effects_toggle = _button(modal_body,"効果音 · 전투 효과음",_toggle_effects)
	effects_toggle.toggle_mode = true
	effects_toggle.button_pressed = bool(progress.data.settings.get("effects",true))
	effects_toggle.custom_minimum_size.y = 42
	var narration = _button(modal_body,"音声 · 일본어 음성",_toggle_voice)
	narration.toggle_mode = true
	narration.button_pressed = bool(progress.data.settings.get("voice",true))
	narration.custom_minimum_size.y = 42
	var volumes = VolumeControls.new()
	volumes.configure(progress.data.settings)
	volumes.volume_changed.connect(_set_audio_volume)
	modal_body.add_child(volumes)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_cancel_deployment_drag()
		_release_deployment_pointer()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_game()

func _exit_tree() -> void:
	CatalogPreview.release_shared_resources()
	NativeBattlefield.release_shared_resources()

func _quit_game() -> void:
	_cancel_deployment_drag()
	if closing:
		return
	closing = true
	if music_fade != null and music_fade.is_valid():
		music_fade.kill()
	_stop_narration()
	_cancel_learning_transition()
	game.paused = true
	progress.write_save()
	if player != null:
		player.stop()
		player.stream = null
	if battle_audio != null:
		battle_audio.shutdown()
	if battle_narrator != null:
		battle_narrator.shutdown()
	if battle_announcer != null:
		battle_announcer.shutdown()
	if voice_director != null:
		voice_director.shutdown()
	# AudioServer fades stopped playbacks on its mixer before deleting them.
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
