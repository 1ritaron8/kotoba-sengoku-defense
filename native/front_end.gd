extends Control

var learning_plans: Dictionary = {}
var campaign_story: Dictionary = {}
var campaign_geography: Dictionary = {}

func _story(stage_id: String) -> Dictionary:
	for entry in campaign_story.get("stages",[]):
		if str(entry.get("stageId",""))==stage_id: return entry
	return {}

func _geography(stage_id: String) -> Dictionary:
	if campaign_geography.is_empty():
		var data=JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_geography.json"))
		if data is Dictionary: campaign_geography=data
	for entry in campaign_geography.get("stages",[]):
		if str(entry.get("stageId",""))==stage_id: return entry
	return {}

func _historical_date(geo: Dictionary, year: int) -> String:
	var old: Dictionary=geo.get("dateOldCalendar",{})
	var western=geo.get("dateGregorian")
	if western is Dictionary and str(geo.get("dateConversionStatus","")).begins_with("official_"):
		return "%d년 %d월 %d일 · 신력"%[int(western.year),int(western.month),int(western.day)]
	if old.get("month")!=null and old.get("day")!=null:
		return "%d년 · 구력 %d월 %d일"%[year,int(old.month),int(old.day)]
	if old.get("month")!=null: return "%d년 · 구력 %d월 무렵"%[year,int(old.month)]
	return "%d년 · 월일 미확인"%year

signal stage_chosen(tier: int, index: int, study: bool)
signal assessment_requested(tier: int, index: int)
signal battle_minutes_selected(minutes: int)
signal music_toggled
signal voice_toggled
signal effects_toggled
signal audio_volume_changed(key: String, value: float)
signal exit_requested
signal resume_requested
signal barracks_requested
signal training_requested

const RubyText = preload("res://native/ruby_label.gd")
const UIStyle = preload("res://native/sengoku_ui.gd")
const GameFonts = preload("res://native/game_fonts.gd")
const VolumeControls = preload("res://native/volume_controls.gd")
const CampaignAtlas = preload("res://native/campaign_atlas.gd")
const BattlefieldPreview = preload("res://native/battlefield_preview.gd")
const BattlefieldPresentation = preload("res://native/battlefield_presentation.gd")
const TIERS = ["basic","beginner","intermediate","advanced"]
const TIER_NAMES = ["初陣 · 기초", "修練 · 초급", "熟練 · 중급", "決戦 · 고급"]
var maps: Array = []
var font: Font
var progress: RefCounted
var voice_available: bool = false
var reading_voice_available: bool = false
var narration_available: bool = false
var male_voice_available: bool = false
var female_voice_available: bool = false
var battle_active: bool = false
var battle_minutes: int = 10
var view: String = "home"
var selected_tier: int = 0
var study_mode: bool = false
var fade: Tween
var selected_stage: int = 0
var atlas_selected_stage_id: String = ""
var catalog_prepared: int = 0
var catalog_preparation_total: int = 0
var catalog_preparation_error: String = ""

func set_catalog_preparation(completed: int, total: int, error: String = "") -> void:
	catalog_prepared = completed
	catalog_preparation_total = total
	catalog_preparation_error = error
	_sync_catalog_preparation()

func _sync_catalog_preparation() -> void:
	var loading: bool = catalog_prepared<catalog_preparation_total
	for action in ["HomeSortie","HomeDictionary","HomeCampaignMap"]:
		var button: Button = get_node_or_null(action) as Button
		if button!=null: button.disabled=loading
	var status: Label = get_node_or_null("HomeCatalogPreparation") as Label
	if status!=null:
		status.text="전장 준비 중 %02d / %02d · 한 번 준비하면 바로 표시됩니다."%[catalog_prepared,catalog_preparation_total] if loading else ""
		if not catalog_preparation_error.is_empty(): status.text=catalog_preparation_error

func _ready() -> void:
	theme = GameFonts.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().size_changed.connect(_rebuild)

func show_home() -> void:
	view = "home"
	study_mode = false
	visible = true
	_rebuild()

func show_catalog(tier: int = 0, study: bool = false) -> void:
	if catalog_prepared<catalog_preparation_total: return
	selected_tier = tier
	study_mode = study
	view = "catalog"
	visible = true
	_rebuild()

func show_campaign_map(stage_id: String = "") -> void:
	if catalog_prepared<catalog_preparation_total: return
	if not stage_id.is_empty(): atlas_selected_stage_id=stage_id
	view="atlas"
	study_mode=false
	visible=true
	_rebuild()

func _box(color: String, border: String, _radius: int = 0) -> StyleBoxFlat:
	return UIStyle.frame(color, border)

func _label(text: String, rect: Rect2, text_size: int = 18, color: String = "e1e6e9") -> Label:
	var label = Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.clip_text = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font",GameFonts.heading() if text_size>=26 else GameFonts.body())
	label.add_theme_font_size_override("font_size",maxi(20,text_size))
	label.add_theme_color_override("font_color",Color(color))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.position = rect.position
	label.size = rect.size
	return label

func _japanese_label(text: String, rect: Rect2, text_size: int, color: String = UIStyle.TEXT) -> Label:
	var label: Label = _label(text,rect,text_size,color)
	label.add_theme_font_override("font",GameFonts.japanese())
	label.size = rect.size
	return label

func _surface(rect: Rect2, material_name: String = "lacquer", opacity: float = .9, ink_border: bool = true) -> Panel:
	var panel: Panel = Panel.new()
	panel.name = "MenuSurface_"+material_name
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base: StyleBoxFlat = UIStyle.frame("241b14e8",UIStyle.LINE)
	if not ink_border:
		base.set_border_width_all(0)
		base.shadow_size = 0
	panel.add_theme_stylebox_override("panel",base)
	add_child(panel)
	UIStyle.texture_layer(panel,material_name,opacity)
	return panel

func _button(text: String, rect: Rect2, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.clip_text = true
	button.add_theme_font_override("font",GameFonts.body())
	button.add_theme_font_size_override("font_size",22)
	for state_name in ["normal","hover","pressed","disabled","focus"]:
		button.add_theme_stylebox_override(state_name,UIStyle.textured_button(state_name))
	button.pressed.connect(callback)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(button)
	return button

func _ruby_button(word: Dictionary, rect: Rect2, callback: Callable) -> Button:
	var button = _button("",rect,callback)
	button.clip_contents = true
	var ruby = RubyText.new()
	ruby.name = "MenuRuby"
	ruby.font = GameFonts.japanese()
	ruby.reading_font = GameFonts.reading()
	ruby.meaning_font = GameFonts.body()
	ruby.ink=Color(UIStyle.TEXT)
	ruby.reading_ink=Color("d5c8a8")
	ruby.meaning_ink=Color("c8b993")
	ruby.set_word(word,30)
	ruby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ruby.offset_top = 0
	button.add_child(ruby)
	return button

func _background(path: String, darkness: float, left_veil: bool = false) -> void:
	var picture = TextureRect.new()
	if ResourceLoader.exists(path):
		picture.texture = load(path)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	var shade = ColorRect.new()
	shade.color = Color(0.045,0.034,0.022,darkness)
	if left_veil:
		var shader = Shader.new()
		shader.code = "shader_type canvas_item; void fragment(){ float edge = abs(UV.x-0.5)*2.0; float a = mix(0.12,0.57,smoothstep(0.15,0.85,edge)); COLOR=vec4(0.045,0.034,0.022,a); }"
		var material_now = ShaderMaterial.new()
		material_now.shader = shader
		shade.material = material_now
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

func _rebuild() -> void:
	if not visible or not is_inside_tree():
		return
	for child in get_children():
		child.hide()
		remove_child(child)
		child.queue_free()
	if fade != null and fade.is_running():
		fade.kill()
	modulate.a = 1.0 if view=="atlas" else 0.0
	match view:
		"catalog": _build_catalog()
		"settings": _build_settings()
		"atlas": _build_atlas()
		_: _build_home()
	if view!="atlas":
		fade = create_tween()
		fade.tween_property(self,"modulate:a",1.0,0.3)

func _build_home() -> void:
	var size_now: Vector2 = get_viewport().get_visible_rect().size
	_background("res://assets/ui/barracks-warroom.png",0.20,true)
	var menu_x: float = size_now.x-458.0
	var content_width: float = menu_x-146.0
	UIStyle.ornament(self,Rect2(74,54,58,58),"crest")
	_japanese_label("戦国・言葉の旅",Rect2(150,67,content_width-80,38),22,"e0c992").name="HomeTagline"
	_japanese_label("言葉の戦場",Rect2(72,110,content_width,72),52,UIStyle.TEXT).name="HomeTitle"
	_label("말의 전장",Rect2(78,190,content_width,40),28,UIStyle.MUTED).name="HomeSubtitle"
	var protagonist: Dictionary = campaign_story.get("protagonist",{})
	var motif_jp: String = str(protagonist.get("motifJP","戦国絵巻、天下統一への道。"))
	var motif_ko: String = str(protagonist.get("motifKo","전국시대, 천하 통일의 이야기"))
	var motif_width: float = minf(730,content_width-24)
	var jp_points: int = 36
	while GameFonts.japanese().get_string_size(motif_jp,HORIZONTAL_ALIGNMENT_LEFT,-1,jp_points).x>motif_width and jp_points>26:
		jp_points-=1
	var jp_width: float = GameFonts.japanese().get_string_size(motif_jp,HORIZONTAL_ALIGNMENT_LEFT,-1,jp_points).x
	var ko_reference: float = GameFonts.heading().get_string_size(motif_ko,HORIZONTAL_ALIGNMENT_LEFT,-1,30).x
	var ko_points: int = clampi(roundi(30.0*jp_width/maxf(1,ko_reference)),28,40)
	while GameFonts.heading().get_string_size(motif_ko,HORIZONTAL_ALIGNMENT_LEFT,-1,ko_points).x>motif_width and ko_points>24:
		ko_points-=1
	var story_plaque: Panel=_surface(Rect2(68,251,motif_width+28,158),"paper",.18)
	story_plaque.name="HomeStoryPlaque"
	var paper: TextureRect=TextureRect.new()
	paper.texture=UIStyle.material_texture("paper")
	paper.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode=TextureRect.STRETCH_SCALE
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter=Control.MOUSE_FILTER_IGNORE
	story_plaque.add_child(paper)
	_japanese_label(motif_jp,Rect2(82,263,motif_width,60),jp_points,"231b13").name="HomeMotifJP"
	_label(motif_ko,Rect2(82,338,motif_width,54),ko_points,"403323").name="HomeMotifKO"
	if progress.campaign_unified():
		_label("天下統一 · 천하 통일 완료",Rect2(78,419,content_width,45),26,UIStyle.BRASS)
	UIStyle.ornament(self,Rect2(menu_x,170,376,4),"divider")
	var menu_surface: Panel=_surface(Rect2(menu_x-10,184,396,442),"lacquer",.82)
	menu_surface.name="HomeMenuSurface"
	var items: Array = [
		{"jp":"出陣","ko":"출진","parts":[{"text":"出","reading":"しゅつ"},{"text":"陣","reading":"じん"}]},
		{"jp":"兵舎","ko":"병영","parts":[{"text":"兵","reading":"へい"},{"text":"舎","reading":"しゃ"}]},
		{"jp":"鍛錬","ko":"병종 연습","parts":[{"text":"鍛","reading":"たん"},{"text":"錬","reading":"れん"}]},
		{"jp":"言葉図鑑","ko":"학습 도감","parts":[{"text":"言葉","reading":"ことば"},{"text":"図鑑","reading":"ずかん"}]}
	]
	var actions: Array = [func(): show_catalog(0,false),func(): barracks_requested.emit(),func(): training_requested.emit(),func(): show_catalog(0,true)]
	for index in range(items.size()):
		var menu: Button = _ruby_button(items[index],Rect2(menu_x,190+index*108,376,106),actions[index])
		menu.name=["HomeSortie","HomeBarracks","HomeTraining","HomeDictionary"][index]
		var ruby: Control = menu.get_node("MenuRuby")
		ruby.offset_left=56
		ruby.offset_right=-16
		ruby.offset_top=3
		ruby.set_word(items[index],24)
		menu.add_theme_stylebox_override("normal",UIStyle.textured_button("normal",index==0))
		var marker: Label = Label.new()
		marker.text=["一","二","三","四"][index]
		marker.position=Vector2(19,29)
		marker.add_theme_font_override("font",GameFonts.japanese())
		marker.add_theme_font_size_override("font_size",26)
		marker.add_theme_color_override("font_color",Color(UIStyle.BRASS))
		marker.mouse_filter=Control.MOUSE_FILTER_IGNORE
		menu.add_child(marker)
	_button("설정",Rect2(menu_x,634,172,47),func(): view="settings"; _rebuild()).name="HomeSettings"
	_button("게임 종료",Rect2(menu_x+192,634,184,47),func(): exit_requested.emit()).name="HomeExit"
	var atlas_entry: Button=_ruby_button({"jp":"全国地図","reading":"ぜんこくちず","ko":"전국 지도","parts":[{"text":"全国","reading":"ぜんこく"},{"text":"地図","reading":"ちず"}]},Rect2(78,477,minf(430,content_width),110),func(): show_campaign_map())
	atlas_entry.name="HomeCampaignMap"
	var map_hint: Label=_label("옛 지명과 오늘날 지역을 따라\n현재 원정의 전투들을 살펴보십시오.",Rect2(78,605,content_width,84),20,UIStyle.TEXT)
	map_hint.name="HomeMapHint"
	map_hint.add_theme_color_override("font_outline_color",Color("171410"))
	map_hint.add_theme_constant_override("outline_size",2)
	_label("",Rect2(78,710,content_width,38),20,UIStyle.MUTED).name="HomeCatalogPreparation"
	if battle_active:
		_button("진행 중인 전장으로",Rect2(menu_x,696,376,47),func(): resume_requested.emit()).name="HomeResume"
	var footer: String = "원정 %02d / 40 · 군자금 %d · 기억 확인 %d / 900" % [progress.data.maps.size(),int(progress.data.army.currency),progress.mastered_count()]
	if not progress.save_error.is_empty(): footer=progress.save_error
	elif not progress.read_error.is_empty(): footer=progress.read_error
	_label(footer,Rect2(78,size_now.y-43,size_now.x-410,32),20,UIStyle.MUTED).name="HomeProgressFooter"
	_japanese_label("戦国時代",Rect2(size_now.x-300,size_now.y-48,236,38),26,"c8b993").horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_sync_catalog_preparation()

func _build_catalog() -> void:
	var size_now = get_viewport().get_visible_rect().size
	_background("res://assets/ui/barracks-warroom.png",0.52)
	UIStyle.ornament(self,Rect2(38,26,54,54),"crest")
	_japanese_label("言葉図鑑" if study_mode else "戦記　出陣之書",Rect2(110,22,size_now.x-380,53),36,UIStyle.TEXT).name="CatalogTitle"
	_label("전장별 학습 도감" if study_mode else "전장 선택 · 원정 기록",Rect2(111,83,size_now.x-380,33),20,UIStyle.MUTED).name="CatalogSubtitle"
	_button("전장 복귀" if battle_active else "돌아가기",Rect2(size_now.x-232,33,190,45),func():
		if battle_active:
			resume_requested.emit()
		else:
			show_home()
	)
	var atlas_entry: Button=_button("전국 지도",Rect2(size_now.x-232,83,190,44),func():
		var available_now: Array=maps.filter(func(stage): return str(stage.tier)==TIERS[selected_tier])
		show_campaign_map(str(available_now[selected_stage].id) if selected_stage>=0 and selected_stage<available_now.size() else "")
	)
	atlas_entry.name="CatalogCampaignMap"
	atlas_entry.tooltip_text="全国地図 · ぜんこくちず · 실제 전투 위치와 당시 지명"
	for tier in range(4):
		var button = _button(TIER_NAMES[tier],Rect2(42+tier*220,129,206,46),func(): selected_stage=0; show_catalog(tier,study_mode))
		if tier==selected_tier:
			button.add_theme_stylebox_override("normal",UIStyle.textured_button("normal",false,true))
	var available = maps.filter(func(stage): return str(stage.tier)==TIERS[selected_tier])
	selected_stage = clampi(selected_stage,0,available.size()-1)
	_surface(Rect2(32,189,358,size_now.y-237),"paper",.12)
	var scroll = ScrollContainer.new()
	scroll.name = "StageCatalogScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(42,200)
	scroll.size = Vector2(338,size_now.y-258)
	add_child(scroll)
	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation",4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in range(available.size()):
		var stage: Dictionary = available[i]
		var story: Dictionary = _story(str(stage.id))
		var row = _button("%02d   %s" % [int(stage.stageNumber),str(story.get("battleKo",str(stage.title).split(" · ")[0]))],Rect2(0,0,318,55),_select_catalog_stage.bind(i))
		row.name = "Stage_%s" % str(stage.id)
		var unlocked: bool = progress.map_unlocked(str(stage.id))
		if not unlocked:
			row.text += " · 잠김"
			row.add_theme_color_override("font_color",Color("a0927a"))
		row.reparent(list,false)
		row.custom_minimum_size = Vector2(318,70)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size",20)
		row.tooltip_text = progress.map_lock_reason(str(stage.id)) if not unlocked else "완료" if progress.map_cleared(str(stage.id)) else "출진 가능"
		if i==selected_stage:
			row.add_theme_stylebox_override("normal",UIStyle.textured_button("normal",false,true))
	scroll.call_deferred("ensure_control_visible",list.get_child(selected_stage))
	var chosen: Dictionary = available[selected_stage]
	var selected_story: Dictionary = _story(str(chosen.id))
	var preview_rect = Rect2(410,200,size_now.x-452,size_now.y-488)
	var landscape: Control = BattlefieldPreview.new()
	landscape.name="CatalogBattlefieldPreview"
	landscape.configure(chosen)
	landscape.position = preview_rect.position
	landscape.size = preview_rect.size
	landscape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(landscape)
	landscape.image.flip_h=BattlefieldPresentation.mirror_for_stage(chosen)
	var preview_frame=Panel.new()
	preview_frame.position=preview_rect.position
	preview_frame.size=preview_rect.size
	preview_frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
	preview_frame.add_theme_stylebox_override("panel",UIStyle.frame("00000000",UIStyle.BRASS))
	add_child(preview_frame)
	if not study_mode:
		var mode_label = _label("戦支度 · 전투 시간",Rect2(preview_rect.position+Vector2(16,16),Vector2(204,40)),20,"e1e6e9")
		mode_label.name="CatalogBattlePreparations"
		mode_label.add_theme_color_override("font_outline_color",Color("101822"))
		mode_label.add_theme_constant_override("outline_size",2)
		for mode_index in range(2):
			var minutes: int = [10,20][mode_index]
			var mode = _button("%d분" % minutes,Rect2(preview_rect.position+Vector2(228+mode_index*92,16),Vector2(82,40)),func(): battle_minutes_selected.emit(minutes))
			mode.name = "BattleMinutes%d" % minutes
			mode.disabled = battle_active
			mode.tooltip_text = "학습·일시 정지를 뺀 1× 전투 시간 · 2×에서는 실제 시간이 짧아집니다."
			mode.add_theme_font_size_override("font_size",20)
			if minutes==battle_minutes:
				mode.add_theme_stylebox_override("normal",UIStyle.textured_button("normal",false,true))
				mode.add_theme_stylebox_override("disabled",UIStyle.textured_button("normal",false,true))
		var narrative_height: float=minf(174,preview_rect.size.y*.52)
		var narrative_rect: Rect2=Rect2(preview_rect.position.x+12,preview_rect.end.y-narrative_height-12,preview_rect.size.x-24,narrative_height)
		var narrative_panel: Panel=_surface(narrative_rect,"lacquer",.15)
		narrative_panel.name="StageHistoricalNarrativePanel"
		narrative_panel.add_theme_stylebox_override("panel",UIStyle.frame("211910f5",UIStyle.LINE))
		var narrative_scroll: ScrollContainer=ScrollContainer.new()
		narrative_scroll.name="StageHistoricalNarrativeScroll"
		narrative_scroll.position=narrative_rect.position+Vector2(16,12)
		narrative_scroll.size=narrative_rect.size-Vector2(32,24)
		narrative_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		add_child(narrative_scroll)
		var narrative: Label=_label(str(selected_story.get("historyNarrativeKo",selected_story.get("historySummaryKo",""))),Rect2(Vector2.ZERO,Vector2(narrative_scroll.size.x,1)),20,"f3e8d1")
		narrative.name="StageHistoricalNarrative"
		narrative.reparent(narrative_scroll,false)
		narrative.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if int(chosen.stageNumber)<40 and progress.map_unlocked(str(chosen.id)) and progress.map_cleared(str(chosen.id)) and not progress.map_assessed(str(chosen.id)):
			var exam = _button("다음 맵 해금 시험",Rect2(preview_rect.end.x-246,preview_rect.position.y+16,230,42),func(): assessment_requested.emit(selected_tier,selected_stage))
			exam.name = "CatalogUnlockExam"
	_surface(Rect2(400,size_now.y-276,size_now.x-432,225),"lacquer",.25)
	var battle_title: Label=_label("%02d   %s" % [int(chosen.stageNumber),str(selected_story.get("battleKo",str(chosen.title).split(" · ")[0]))],Rect2(418,size_now.y-261,size_now.x-748,44),30,UIStyle.TEXT)
	battle_title.name="StageBattleTitle"
	battle_title.size.y=maxf(44,battle_title.get_minimum_size().y)
	var plan: Dictionary = learning_plans.get("stages",{}).get(str(chosen.id),{})
	var description_text: String=str(plan.get("goalKo","")) if study_mode else str(selected_story.get("historySummaryKo",""))
	if not study_mode:
		var geo: Dictionary=_geography(str(chosen.id))
		var actual_result: String=str(selected_story.get("historyOutcomeKo","")).split(".")[0]+"."
		description_text="때 · %s\n옛 지명 · %s\n오늘날 · %s\n상대 · %s\n결과 · %s"%[_historical_date(geo,int(selected_story.get("year",0))),str(geo.get("oldNameKo","")),str(geo.get("modernNameKo","")),str(selected_story.get("opponent",{}).get("nameKo","")),actual_result]
		description_text+="\n제작 근거 · "+str(geo.get("renderingBasisKo",""))
	var description_scroll: ScrollContainer = ScrollContainer.new()
	description_scroll.name = "StageTacticalDescriptionScroll"
	description_scroll.position=Vector2(418,battle_title.position.y+battle_title.size.y+12)
	description_scroll.size=Vector2(size_now.x-750,size_now.y-69-description_scroll.position.y)
	description_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(description_scroll)
	var description: Label=_label(description_text,Rect2(Vector2.ZERO,Vector2(description_scroll.size.x,142)),20,"efe4cf")
	description.name = "StageTacticalDescription"
	description.reparent(description_scroll,false)
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not study_mode:
		var source_urls: Array=_geography(str(chosen.id)).get("sources",[])
		var sources=LinkButton.new()
		sources.name="MapBasisSources"
		sources.text="맵 제작 참고 자료"
		sources.position=Vector2(size_now.x-306,size_now.y-124)
		sources.size=Vector2(246,34)
		sources.add_theme_font_override("font",GameFonts.body())
		sources.add_theme_font_size_override("font_size",20)
		sources.add_theme_color_override("font_color",Color("dcc594"))
		sources.tooltip_text="\n".join(PackedStringArray(source_urls))
		sources.disabled=source_urls.is_empty()
		if not source_urls.is_empty():
			var source_url: String=str(source_urls[0])
			sources.pressed.connect(func(): OS.shell_open(source_url))
		add_child(sources)
	var start = _ruby_button({"jp":"図鑑" if study_mode else "出陣","reading":"ずかん" if study_mode else "しゅつじん","ko":"이 전장의 도감" if study_mode else "이 전장에 출진"},Rect2(size_now.x-306,size_now.y-256,246,114),func(): stage_chosen.emit(selected_tier,selected_stage,study_mode))
	start.name="CatalogSortie"
	start.disabled = not progress.map_unlocked(str(chosen.id))
	start.tooltip_text = progress.map_lock_reason(str(chosen.id)) if start.disabled else ""
	start.add_theme_stylebox_override("normal",UIStyle.textured_button("normal",true))
	if start.disabled:
		var locked_caption = _label(progress.map_lock_reason(str(chosen.id)),Rect2(preview_rect.position+Vector2(16,70),Vector2(preview_rect.size.x-32,64)),22,"e8c29c")
		locked_caption.name = "MapUnlockRequirement"
		locked_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		locked_caption.add_theme_constant_override("outline_size",2)
		locked_caption.add_theme_color_override("font_outline_color",Color("101822"))
	var warning: String = progress.save_error if not progress.save_error.is_empty() else progress.read_error
	_label(warning if not warning.is_empty() else "원정 %02d / 40 · 기억 확인 %d / 900" % [progress.data.maps.size(),progress.mastered_count()],Rect2(42,size_now.y-48,size_now.x-84,30),20,"e8a68b" if not warning.is_empty() else UIStyle.MUTED).name="CatalogProgressFooter"

func _select_catalog_stage(index: int) -> void:
	selected_stage=index
	_rebuild()

func _atlas_stage_indices(stage_id: String) -> Vector2i:
	for tier in range(TIERS.size()):
		var available: Array=maps.filter(func(stage): return str(stage.tier)==TIERS[tier])
		for index in range(available.size()):
			if str(available[index].id)==stage_id: return Vector2i(tier,index)
	return Vector2i(-1,-1)

func _atlas_select(stage_id: String) -> void:
	atlas_selected_stage_id=stage_id
	var indices: Vector2i=_atlas_stage_indices(stage_id)
	if indices.x>=0:
		selected_tier=indices.x
		selected_stage=indices.y

func _build_atlas() -> void:
	var geography: Dictionary={}
	var path: String="res://native/campaign_geography.json"
	if FileAccess.file_exists(path):
		var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary: geography=parsed
	var atlas: Control=CampaignAtlas.new()
	atlas.name="CampaignAtlas"
	atlas.configure(progress,maps,campaign_story,geography,font)
	atlas.show_stage(atlas_selected_stage_id,battle_active)
	atlas.selection_changed.connect(_atlas_select)
	atlas.stage_requested.connect(func(stage_id):
		var indices: Vector2i=_atlas_stage_indices(stage_id)
		if indices.x<0 or not progress.map_unlocked(stage_id): return
		_atlas_select(stage_id)
		stage_chosen.emit(indices.x,indices.y,false)
	)
	atlas.assessment_requested.connect(func(stage_id):
		var indices: Vector2i=_atlas_stage_indices(stage_id)
		if indices.x>=0: assessment_requested.emit(indices.x,indices.y)
	)
	atlas.home_requested.connect(show_home)
	atlas.catalog_requested.connect(func(): show_catalog(selected_tier,false))
	atlas.resume_requested.connect(func(): resume_requested.emit())
	add_child(atlas)

func _build_settings() -> void:
	var size_now = get_viewport().get_visible_rect().size
	_background("res://assets/ui/barracks-warroom.png",0.48)
	_surface(Rect2(62,204,440,276),"lacquer",.82)
	_surface(Rect2(526,204,minf(800,size_now.x-588),276),"lacquer",.82)
	var volumes: Control = VolumeControls.new()
	volumes.configure(progress.data.settings)
	volumes.position = Vector2(544,226)
	volumes.size = Vector2(minf(764,size_now.x-624),232)
	volumes.volume_changed.connect(func(key,value): audio_volume_changed.emit(key,value))
	add_child(volumes)
	var notes: Panel = Panel.new()
	notes.name = "SettingsPaper"
	notes.position = Vector2(64,502)
	notes.size = Vector2(minf(1264,size_now.x-128),130)
	notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notes.add_theme_stylebox_override("panel",UIStyle.textured_panel("paper",Color("ddceb1")))
	add_child(notes)
	UIStyle.ornament(self,Rect2(80,62,58,58),"crest")
	_japanese_label("設定",Rect2(163,63,650,60),40,UIStyle.TEXT).name="SettingsTitle"
	_label("환경 설정 · 음악과 일본어 음성",Rect2(80,155,800,45),22,UIStyle.MUTED).name="SettingsSubtitle"
	var music_on = bool(progress.data.settings.get("music",true))
	var voice_on = voice_available and bool(progress.data.settings.get("voice",true))
	_button("배경 음악     %s" % ("켜짐" if music_on else "꺼짐"),Rect2(80,224,404,58),func(): music_toggled.emit(); _rebuild())
	_button("일본어 음성     %s" % ("켜짐" if voice_on else "꺼짐"),Rect2(80,314,404,58),func(): voice_toggled.emit(); _rebuild())
	var effects_on: bool = bool(progress.data.settings.get("effects",true))
	_button("효과음     %s" % ("켜짐" if effects_on else "꺼짐"),Rect2(80,404,404,58),func(): effects_toggled.emit(); _rebuild())
	var voice_description: String = "이 PC에는 일본어 읽기 음성이 없습니다. 읽기와 뜻은 화면에 표시됩니다."
	if narration_available:
		var recorded: String = "남성 전투·여성 안내 성우 음성" if male_voice_available and female_voice_available else "남성 전투 성우 음성" if male_voice_available else "여성 안내 성우 음성"
		voice_description = recorded+" · 학습 읽기 사용 가능" if reading_voice_available else recorded+" · 학습 읽기 음성 없음"
	elif reading_voice_available:
		voice_description = "일본어 학습 읽기 음성을 사용할 수 있습니다."
	var voice_note: Label = _label(voice_description+"\n진행 상황과 설정은 자동 저장됩니다.",Rect2(84,518,minf(1224,size_now.x-168),98),20,UIStyle.INK)
	voice_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button("돌아가기",Rect2(80,size_now.y-145,250,53),show_home)
