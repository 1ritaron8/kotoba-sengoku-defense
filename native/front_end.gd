extends Control

const BattleDuration = preload("res://native/battle_duration.gd")

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
const UIPresentation = preload("res://native/battlefield_hud.gd")
const GameFonts = preload("res://native/game_fonts.gd")
const VolumeControls = preload("res://native/volume_controls.gd")
const CampaignAtlas = preload("res://native/campaign_atlas.gd")
const BattlefieldPreview = preload("res://native/battlefield_preview.gd")
const BattlefieldPresentation = preload("res://native/battlefield_presentation.gd")
const TIERS = ["basic","beginner","intermediate","advanced"]
const TIER_NAMES = ["初陣\n기초", "修練\n초급", "熟練\n중급", "決戦\n고급"]
var maps: Array = []
var font: Font
var progress: RefCounted
var voice_available: bool = false
var reading_voice_available: bool = false
var narration_available: bool = false
var male_voice_available: bool = false
var female_voice_available: bool = false
var battle_active: bool = false
var battle_minutes: int = BattleDuration.FIXED_MINUTES
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
		if button!=null: button.disabled=loading or maps.is_empty()
	var training: Button = get_node_or_null("HomeTraining") as Button
	if training!=null: training.disabled=maps.is_empty()
	var status: Label = get_node_or_null("HomeCatalogPreparation") as Label
	if status!=null:
		status.text="전장 재설계 중 · 현재 플레이 가능한 전장 0개" if maps.is_empty() else "전장 준비 중 %02d / %02d · 한 번 준비하면 바로 표시됩니다."%[catalog_prepared,catalog_preparation_total] if loading else ""
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

func _label(text: String, rect: Rect2, text_size: int = 18, color: String = UIStyle.TEXT) -> Label:
	var label = UIStyle.TooltipLabel.new()
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
	var base: StyleBoxFlat = UIStyle.frame(UIStyle.SURFACE,UIStyle.LINE)
	if not ink_border:
		base.set_border_width_all(0)
		base.shadow_size = 0
	panel.add_theme_stylebox_override("panel",base)
	add_child(panel)
	UIStyle.texture_layer(panel,material_name,minf(opacity,.18) if material_name=="lacquer" else opacity)
	return panel

func _button(text: String, rect: Rect2, callback: Callable) -> Button:
	var button = UIStyle.TooltipButton.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.clip_text = true
	UIPresentation.apply_button(button)
	button.add_theme_font_override("font",GameFonts.body())
	button.add_theme_font_size_override("font_size",22)
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
	ruby.reading_ink=Color(UIStyle.MUTED)
	ruby.meaning_ink=Color(UIStyle.BRASS)
	ruby.set_word(word,30)
	button.add_child(ruby)
	ruby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content: Rect2=UIStyle.content_rect(button,"normal")
	ruby.offset_left=content.position.x
	ruby.offset_top=content.position.y
	ruby.offset_right=content.end.x-button.size.x
	ruby.offset_bottom=content.end.y-button.size.y
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
	shade.color = Color(0.035,0.047,0.052,darkness)
	if left_veil:
		var shader = Shader.new()
		shader.code = "shader_type canvas_item; void fragment(){ float edge = abs(UV.x-0.5)*2.0; float a = mix(0.12,0.57,smoothstep(0.15,0.85,edge)); COLOR=vec4(0.035,0.047,0.052,a); }"
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
		if child.name=="InterfaceDetailReader": continue
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
	var reader: Node=get_node_or_null("InterfaceDetailReader")
	if reader!=null: move_child(reader,get_child_count()-1)
	if view!="atlas":
		fade = create_tween()
		fade.tween_property(self,"modulate:a",1.0,0.3)

func _build_home() -> void:
	var size_now: Vector2 = get_viewport().get_visible_rect().size
	_background("res://assets/ui/barracks-warroom.png",0.20,true)
	var menu_x: float = size_now.x-458.0
	var content_width: float = menu_x-146.0
	UIStyle.ornament(self,Rect2(74,54,58,58),"crest")
	var tagline: Label=_japanese_label("戦国・言葉の旅\n전국시대, 언어의 여정",Rect2(150,24,content_width-80,90),20,UIStyle.MUTED)
	tagline.name="HomeTagline"
	tagline.add_theme_font_size_override("font_size",16)
	tagline.call("refresh_ruby")
	tagline.size=Vector2(content_width-80,90)
	_japanese_label("言葉の戦場",Rect2(72,122,content_width,116),46,UIStyle.TEXT).name="HomeTitle"
	_label("말의 전장",Rect2(78,246,content_width,40),28,UIStyle.MUTED).name="HomeSubtitle"
	var protagonist: Dictionary = campaign_story.get("protagonist",{})
	var motif_jp: String = str(protagonist.get("motifJP","戦国絵巻、天下統一への道。"))
	var motif_ko: String = str(protagonist.get("motifKo","전국시대, 천하 통일의 이야기"))
	var motif_width: float = minf(730,content_width-24)
	var jp_points: int = 28
	while GameFonts.japanese().get_string_size(motif_jp,HORIZONTAL_ALIGNMENT_LEFT,-1,jp_points).x>motif_width and jp_points>26:
		jp_points-=1
	var jp_width: float = GameFonts.japanese().get_string_size(motif_jp,HORIZONTAL_ALIGNMENT_LEFT,-1,jp_points).x
	var ko_reference: float = GameFonts.heading().get_string_size(motif_ko,HORIZONTAL_ALIGNMENT_LEFT,-1,30).x
	var ko_points: int = clampi(roundi(30.0*jp_width/maxf(1,ko_reference)),28,40)
	while GameFonts.heading().get_string_size(motif_ko,HORIZONTAL_ALIGNMENT_LEFT,-1,ko_points).x>motif_width and ko_points>24:
		ko_points-=1
	var story_plaque: Panel=_surface(Rect2(68,300,motif_width+28,164),"paper",.18)
	story_plaque.name="HomeStoryPlaque"
	var paper: TextureRect=TextureRect.new()
	paper.texture=UIStyle.material_texture("paper")
	paper.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode=TextureRect.STRETCH_SCALE
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter=Control.MOUSE_FILTER_IGNORE
	story_plaque.add_child(paper)
	_japanese_label(motif_jp,Rect2(82,310,motif_width,82),jp_points,"231b13").name="HomeMotifJP"
	_label(motif_ko,Rect2(82,400,motif_width,54),ko_points,"403323").name="HomeMotifKO"
	var unified: bool=not maps.is_empty() and progress.campaign_unified()
	if unified:
		_label("天下統一 · 천하 통일 완료",Rect2(78,464,content_width,62),26,UIStyle.BRASS)
	UIStyle.ornament(self,Rect2(menu_x,170,376,4),"divider")
	var menu_surface: Panel=_surface(Rect2(menu_x-10,184,396,462),"lacquer",.82)
	menu_surface.name="HomeMenuSurface"
	var items: Array = [
		{"jp":"出陣","ko":"출진","parts":[{"text":"出","reading":"しゅつ"},{"text":"陣","reading":"じん"}]},
		{"jp":"兵舎","ko":"병영","parts":[{"text":"兵","reading":"へい"},{"text":"舎","reading":"しゃ"}]},
		{"jp":"鍛錬","ko":"병종 연습","parts":[{"text":"鍛","reading":"たん"},{"text":"錬","reading":"れん"}]},
		{"jp":"言葉図鑑","ko":"학습 도감","parts":[{"text":"言","reading":"こと"},{"text":"葉","reading":"ば"},{"text":"図","reading":"ず"},{"text":"鑑","reading":"かん"}]}
	]
	var actions: Array = [func(): show_catalog(0,false),func(): barracks_requested.emit(),func(): training_requested.emit(),func(): show_catalog(0,true)]
	for index in range(items.size()):
		var menu: Button = _ruby_button(items[index],Rect2(menu_x,190+index*112,376,110),actions[index])
		menu.name=["HomeSortie","HomeBarracks","HomeTraining","HomeDictionary"][index]
		var ruby: Control = menu.get_node("MenuRuby")
		ruby.offset_left=56
		ruby.offset_right=-16
		ruby.offset_top=7
		ruby.offset_bottom=-7
		ruby.meaning_size=18
		ruby.set_word(items[index],22)
		menu.add_theme_stylebox_override("normal",UIStyle.primary() if index==0 else UIStyle.button("normal"))
		var marker: Label = UIStyle.TooltipLabel.new()
		marker.text=["一","二","三","四"][index]
		marker.position=Vector2(12,16)
		marker.size=Vector2(40,72)
		marker.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		marker.add_theme_font_override("font",GameFonts.japanese())
		marker.add_theme_font_size_override("font_size",26)
		marker.add_theme_color_override("font_color",Color(UIStyle.BRASS))
		marker.mouse_filter=Control.MOUSE_FILTER_IGNORE
		menu.add_child(marker)
	_button("설정",Rect2(menu_x,648,172,47),func(): view="settings"; _rebuild()).name="HomeSettings"
	_button("게임 종료",Rect2(menu_x+192,648,184,47),func(): exit_requested.emit()).name="HomeExit"
	var atlas_y: float=534 if unified else 477
	var atlas_entry: Button=_ruby_button({"jp":"全国地図","reading":"ぜんこくちず","ko":"전국 지도","parts":[{"text":"全国","reading":"ぜんこく"},{"text":"地図","reading":"ちず"}]},Rect2(78,atlas_y,minf(430,content_width),132),func(): show_campaign_map())
	atlas_entry.name="HomeCampaignMap"
	var map_hint: Label=_label("전장 지형과 경로를 새로 설계하고 있습니다.\n완성된 전장을 다시 추가할 예정입니다." if maps.is_empty() else "옛 지명과 오늘날 지역을 따라\n현재 원정의 전투들을 살펴보십시오.",Rect2(78,atlas_y+150,content_width,64),20,UIStyle.TEXT)
	map_hint.name="HomeMapHint"
	map_hint.add_theme_color_override("font_outline_color",Color("171410"))
	map_hint.add_theme_constant_override("outline_size",2)
	_label("",Rect2(78,710,content_width,38),20,UIStyle.MUTED).name="HomeCatalogPreparation"
	if battle_active and not maps.is_empty():
		_button("진행 중인 전장으로",Rect2(menu_x,710,376,47),func(): resume_requested.emit()).name="HomeResume"
	var footer: String = "원정 %02d / 40 · 군자금 %d · 기억 확인 %d / 900" % [progress.data.maps.size(),int(progress.data.army.currency),progress.mastered_count()]
	if maps.is_empty(): footer="전장 재설계 · 이전 기록 %d개 · 군자금 %d · 기억 확인 %d / 900" % [progress.data.maps.size(),int(progress.data.army.currency),progress.mastered_count()]
	if not progress.save_error.is_empty(): footer=progress.save_error
	elif not progress.read_error.is_empty(): footer=progress.read_error
	_label(footer,Rect2(78,size_now.y-43,size_now.x-410,32),20,UIStyle.MUTED).name="HomeProgressFooter"
	var era_label: Label=_japanese_label("戦国時代\n전국시대",Rect2(size_now.x-300,size_now.y-104,236,96),18,UIStyle.MUTED)
	era_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	era_label.add_theme_font_size_override("font_size",18)
	era_label.call("refresh_ruby")
	era_label.size=Vector2(236,era_label.get_combined_minimum_size().y)
	era_label.position.y=size_now.y-12-era_label.size.y
	_sync_catalog_preparation()

func _change_catalog_tier(tier: int) -> void:
	selected_stage=0
	show_catalog(tier,study_mode)

func close_detail() -> bool:
	var reader: Node=find_child("InterfaceDetailReader",true,false)
	if reader==null: return false
	reader.call("close")
	return true

func _catalog_detail(chosen: Dictionary, section: int) -> void:
	var id: String=str(chosen.id)
	var sections: Array=UIStyle.stage_detail_sections(chosen,_story(id),_geography(id),learning_plans.get("stages",{}).get(id,{}))
	var reader: Control=UIStyle.open_detail(self,str(_story(id).get("battleKo",chosen.title)),sections)
	reader.set("section_index",section)

func _build_catalog() -> void:
	var viewport_size: Vector2=get_viewport().get_visible_rect().size
	_background("res://assets/ui/barracks-warroom.png",0.52)
	UIStyle.ornament(self,Rect2(38,26,54,54),"crest")
	_japanese_label("言葉図鑑" if study_mode else "戦記　出陣之書",Rect2(110,18,viewport_size.x-380,78),32,UIStyle.TEXT).name="CatalogTitle"
	_label("전장별 학습 도감" if study_mode else "전장 선택 · 원정 기록",Rect2(111,99,viewport_size.x-380,33),20,UIStyle.MUTED).name="CatalogSubtitle"
	_button("전장 복귀" if battle_active else "돌아가기",Rect2(viewport_size.x-232,28,190,48),func():
		if battle_active: resume_requested.emit()
		else: show_home()
	)
	var available: Array=maps.filter(func(stage): return str(stage.tier)==TIERS[selected_tier])
	var atlas_button: Button=_button("전국 지도",Rect2(viewport_size.x-232,84,190,48),func():
		show_campaign_map(str(available[selected_stage].id) if selected_stage>=0 and selected_stage<available.size() else "")
	)
	atlas_button.name="CatalogCampaignMap"
	atlas_button.disabled=maps.is_empty()
	var list_width: float=clampf(viewport_size.x*.28,360,420)
	var right_x: float=52+list_width
	var right_width: float=viewport_size.x-right_x-32
	var tab_width: float=(list_width-12)*.5
	var japanese: Array=["初陣","修練","熟練","決戦"]
	var readings: Array=["ういじん","しゅうれん","じゅくれん","けっせん"]
	var korean: Array=["기초","초급","중급","고급"]
	for tier in range(4):
		var word: Dictionary={"jp":japanese[tier],"reading":readings[tier],"ko":korean[tier]}
		var tab_column: int=tier%2
		var tab_row: int=tier/2
		var tab: Button=_ruby_button(word,Rect2(32+tab_column*(tab_width+12),146+tab_row*124,tab_width,112),_change_catalog_tier.bind(tier))
		tab.name="CatalogTier_%d"%tier
		var tab_text: Control=tab.get_node("MenuRuby")
		tab_text.meaning_size=18
		tab_text.set_word(word,22)
		tab_text.offset_left=14
		tab_text.offset_right=-14
		tab_text.offset_top=7
		tab_text.offset_bottom=-7
		if tier==selected_tier: tab.add_theme_stylebox_override("normal",UIStyle.selected())
	if available.is_empty():
		selected_stage=0
		_label("전장 재설계 중",Rect2(right_x,174,right_width,58),30,UIStyle.BRASS).name="CatalogEmptyTitle"
		_label("현재 플레이 가능한 전장이 없습니다." if maps.is_empty() else "이 등급의 전장을 준비하고 있습니다.",Rect2(right_x,242,right_width,104),22,UIStyle.TEXT).name="CatalogEmptyStatus"
		return
	selected_stage=clampi(selected_stage,0,available.size()-1)
	var content_top: float=146
	var content_bottom: float=viewport_size.y-64
	var content_height: float=content_bottom-content_top
	var list_top: float=398
	var list_height: float=content_bottom-list_top
	var rows_per_page: int=maxi(1,floori((list_height-88)/76))
	var list_bottom: float=content_bottom
	_surface(Rect2(32,list_top,list_width,list_height),"paper",.12).name="StageCatalogPanel"
	var first: int=(selected_stage/rows_per_page)*rows_per_page
	for index in range(first,mini(first+rows_per_page,available.size())):
		var entry: Dictionary=available[index]
		var title: String="%02d · %s"%[int(entry.stageNumber),str(_story(str(entry.id)).get("battleKo",entry.title))]
		var row: Button=_button(title,Rect2(46,list_top+14+(index-first)*76,list_width-28,72),_select_catalog_stage.bind(index))
		row.name="Stage_%s"%str(entry.id)
		row.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size",18)
		row.alignment=HORIZONTAL_ALIGNMENT_LEFT
		row.tooltip_text=progress.map_lock_reason(str(entry.id)) if not progress.map_unlocked(str(entry.id)) else "완료" if progress.map_cleared(str(entry.id)) else "출진 가능"
		if not progress.map_unlocked(str(entry.id)): row.add_theme_color_override("font_color",Color(UIStyle.DISABLED))
		if index==selected_stage: row.add_theme_stylebox_override("normal",UIStyle.selected())
	var previous: Button=_button("이전",Rect2(46,list_bottom-62,80,48),_select_catalog_stage.bind(maxi(0,first-rows_per_page)))
	previous.disabled=first==0
	var next: Button=_button("다음",Rect2(32+list_width-94,list_bottom-62,80,48),_select_catalog_stage.bind(mini(available.size()-1,first+rows_per_page)))
	next.disabled=first+rows_per_page>=available.size()
	_label("%d / %d"%[first/rows_per_page+1,ceili(float(available.size())/rows_per_page)],Rect2(132,list_bottom-54,list_width-200,32),20,UIStyle.MUTED).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var chosen: Dictionary=available[selected_stage]
	var chosen_story: Dictionary=_story(str(chosen.id))
	var geo: Dictionary=_geography(str(chosen.id))
	var image_ratio: float=BattlefieldPreview.aspect_ratio_for_stage(chosen)
	var summary_height: float=190.0 if viewport_size.y<880 else 204.0
	var preview_height_limit: float=maxf(140,content_height-summary_height-16)
	var preview_width: float=minf(right_width,preview_height_limit*image_ratio)
	var preview_rect: Rect2=Rect2(right_x+(right_width-preview_width)*.5,content_top,preview_width,preview_width/image_ratio)
	var landscape: Control=BattlefieldPreview.new()
	landscape.name="CatalogBattlefieldPreview"
	landscape.configure(chosen)
	landscape.position=preview_rect.position
	landscape.size=preview_rect.size
	landscape.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(landscape)
	landscape.image.flip_h=BattlefieldPresentation.mirror_for_stage(chosen)
	var preview_frame: Panel=Panel.new()
	preview_frame.name="CatalogPreviewFrame"
	preview_frame.position=preview_rect.position
	preview_frame.size=preview_rect.size
	preview_frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
	preview_frame.add_theme_stylebox_override("panel",UIStyle.frame("00000000",UIStyle.BRASS))
	add_child(preview_frame)
	if not study_mode:
		var cycle_count: int=int(BattleDuration.preview(chosen,0).get("totalWaves",0))
		var mode_label: Label=_label("적 공격 · 총 %d회" % cycle_count,Rect2(preview_rect.position+Vector2(16,24),Vector2(240,34)),20,UIStyle.TEXT)
		mode_label.name="CatalogBattlePreparations"
		mode_label.add_theme_color_override("font_outline_color",Color("101410"))
		mode_label.add_theme_constant_override("outline_size",3)
		if int(chosen.stageNumber)<40 and progress.map_unlocked(str(chosen.id)) and progress.map_cleared(str(chosen.id)) and not progress.map_assessed(str(chosen.id)):
			_button("다음 맵 해금 시험",Rect2(preview_rect.end.x-248,preview_rect.position.y+16,232,52),func(): assessment_requested.emit(selected_tier,selected_stage)).name="CatalogUnlockExam"
	var summary: Rect2=Rect2(preview_rect.position.x,preview_rect.end.y+16,preview_rect.size.x,summary_height)
	_surface(summary,"lacquer",.25).name="StageSummaryPanel"
	var text_width: float=summary.size.x-276
	var battle_title: Label=_label("%02d · %s"%[int(chosen.stageNumber),str(chosen_story.get("battleKo",chosen.title))],Rect2(summary.position+Vector2(18,12),Vector2(text_width,42)),26,UIStyle.TEXT)
	battle_title.name="StageBattleTitle"
	battle_title.max_lines_visible=1
	battle_title.clip_text=true
	battle_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	battle_title.tooltip_text=str(chosen_story.get("battleKo",chosen.title))
	var stage_status: String="클리어" if progress.map_cleared(str(chosen.id)) else "출진 가능" if progress.map_unlocked(str(chosen.id)) else "잠김"
	var summary_text: String="%d년 · %s"%[int(chosen_story.get("year",0)),stage_status]
	var facts: Label=_label(summary_text,Rect2(summary.position+Vector2(18,64),Vector2(text_width,32)),20,UIStyle.TEXT)
	facts.name="StageSummary"
	facts.tooltip_text="때 · %s\n옛 지명 · %s"%[_historical_date(geo,int(chosen_story.get("year",0))),str(geo.get("oldNameKo","자료 준비 중"))]
	if study_mode: facts.tooltip_text=str(learning_plans.get("stages",{}).get(str(chosen.id),{}).get("goalKo",facts.tooltip_text))
	if not progress.map_unlocked(str(chosen.id)): facts.tooltip_text+="\n"+progress.map_lock_reason(str(chosen.id))
	var detail_labels: Array=["역사 자세히","지명·지형","학습 목표"]
	var detail_sections: Array=[0,1,3]
	var detail_width: float=(text_width-20)/3
	for detail_index in range(3):
		_button(detail_labels[detail_index],Rect2(summary.position.x+18+(detail_width+10)*detail_index,summary.end.y-68,detail_width,52),_catalog_detail.bind(chosen,int(detail_sections[detail_index]))).name=["CatalogDetails","CatalogLocationDetails","CatalogLearningDetails"][detail_index]
	var sortie_word: Dictionary={"jp":"図鑑" if study_mode else "出陣","reading":"ずかん" if study_mode else "しゅつじん","ko":"이 전장의 도감" if study_mode else "이 전장에 출진"}
	var sortie: Button=_ruby_button(sortie_word,Rect2(summary.end.x-240,summary.position.y+(summary.size.y-132)*.5,222,132),func(): stage_chosen.emit(selected_tier,selected_stage,study_mode))
	sortie.name="CatalogSortie"
	var sortie_text: Control=sortie.get_node("MenuRuby")
	sortie_text.meaning_size=20
	sortie_text.set_word(sortie_word,30)
	sortie_text.offset_left=14
	sortie_text.offset_right=-14
	sortie_text.offset_top=7
	sortie_text.offset_bottom=-7
	sortie.disabled=not progress.map_unlocked(str(chosen.id))
	sortie.tooltip_text=progress.map_lock_reason(str(chosen.id)) if sortie.disabled else ""
	sortie.add_theme_stylebox_override("normal",UIStyle.primary())
	var warning: String=progress.save_error if not progress.save_error.is_empty() else progress.read_error
	_label(warning if not warning.is_empty() else "원정 %02d / 40 · 기억 확인 %d / 900"%[progress.data.maps.size(),progress.mastered_count()],Rect2(42,viewport_size.y-42,viewport_size.x-84,30),20,UIStyle.MUTED).name="CatalogProgressFooter"

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
	if maps.is_empty():
		_build_catalog()
		return
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
	_japanese_label("設定",Rect2(163,45,650,98),40,UIStyle.TEXT).name="SettingsTitle"
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
