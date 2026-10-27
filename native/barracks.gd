extends Control

signal closed
signal army_changed
signal training_requested(unit_id: String)

const RubyText = preload("res://native/ruby_label.gd")
const SengokuUI = preload("res://native/sengoku_ui.gd")
const UIPresentation = preload("res://native/battlefield_hud.gd")
const CommanderPortrait = preload("res://native/commander_portrait.gd")
const UnitPreview = preload("res://native/barracks_portrait.gd")
const GameFonts = preload("res://native/game_fonts.gd")
const UnitGrowth = preload("res://native/unit_growth.gd")
const SKILL_SUMMARIES: Dictionary={
	"archer_fire":"명중한 적에게 잠시 화상을 입힙니다.",
	"archer_barrage":"착탄 지점의 밀집한 적에게 광역 피해.",
	"archer_double_shot":"몇 차례의 사격마다 불화살비를 두 번 연속 발사.",
	"spear_pierce":"찌른 방향 뒤쪽의 적까지 관통합니다.",
	"spear_brace":"다가오는 적을 창으로 받아 짧게 저지합니다.",
	"spear_rear_rank":"앞줄 뒤에서도 긴 창으로 교전합니다.",
	"samurai_parry":"근접 공격 한 번을 받아내고 다음 공격에 반격.",
	"samurai_counter_combo":"받아친 적을 실제로 두 번 연속 벱니다.",
	"samurai_isshin":"성공한 반격을 모아 강한 마무리 베기.",
	"gunner_pierce":"직선 뒤쪽의 적까지 탄환이 관통합니다.",
	"gunner_armor_break":"적 갑옷을 약화해 후속 공격을 돕습니다.",
	"gunner_braced_shot":"몇 차례의 사격마다 총을 받쳐 강한 관통 사격.",
	"monk_talisman":"치료한 아군은 범위 밖에서도 잠시 회복.",
	"monk_ward":"직접 치료한 아군의 다음 피해를 일부 흡수.",
	"monk_victory_prayer":"처치·실제 치료로 기도를 모아 범위 회복.",
	"commander_charge":"실제 기마 돌진으로 앞의 적을 타격합니다.",
	"commander_impact":"격돌로 주변 적의 공격 준비를 짧게 저지.",
	"commander_rally":"돌진 성공 후 주변 전진 병력의 다음 일격 강화.",
	"ninja_timed_charge":"지정한 적에게 폭약을 설치하고 소모됩니다.",
	"ninja_opening_combo":"같은 적을 세 번 벤 뒤 다음 공격에 폭약 설치.",
	"ninja_charge_shrapnel":"실제 폭발 주변의 전진형 적 최대 네 명에 파편 피해."
}
const WARROOM_PATH: String = "res://assets/ui/barracks-warroom.png"
static var _background_cache: Dictionary = {}
var progress: RefCounted
var font: Font
var can_train: bool = true
var can_practice: bool = true
var feedback: String = ""
var skills_scroll: ScrollContainer
var unit_preview: Control
var selected_unit_id: String = ""
var _displayed_unit_id: String = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().size_changed.connect(_rebuild)
	hide()

func open(training_allowed: bool = true, practice_allowed: bool = true) -> void:
	can_train = training_allowed
	can_practice = practice_allowed
	feedback = ""
	var selected_definition: Dictionary = progress.unit_definition(selected_unit_id)
	if selected_definition.is_empty() or not bool(selected_definition.get("active",true)):
		selected_unit_id = str(progress.data.army.get("selected","archer"))
	show()
	_rebuild()

func _active_catalog() -> Array:
	var result: Array = []
	for definition in progress.unit_catalog:
		if bool(definition.get("active",true)):
			result.append(definition)
	return result

func _label(parent: Node, text: String, rect: Rect2, text_size: int = 20, colour: String = SengokuUI.TEXT) -> Label:
	var label = SengokuUI.TooltipLabel.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font",GameFonts.heading() if text_size>=26 else GameFonts.body())
	label.add_theme_font_size_override("font_size",maxi(20,text_size))
	label.add_theme_color_override("font_color",Color(colour))
	label.add_theme_color_override("font_shadow_color",Color("09090970"))
	label.add_theme_constant_override("shadow_offset_y",1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = rect.position
	label.size = rect.size
	parent.add_child(label)
	label.text = text
	label.size = rect.size
	return label

func _button(parent: Node, text: String, rect: Rect2, action: Callable) -> Button:
	var button = SengokuUI.TooltipButton.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.clip_text = true
	UIPresentation.apply_button(button)
	button.add_theme_font_override("font",font)
	button.add_theme_font_size_override("font_size",22)
	button.pressed.connect(action)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	return button

func _ruby(parent: Node, name_value: Dictionary, rect: Rect2, text_size: int = 30) -> Control:
	var word = RubyText.new()
	word.font = GameFonts.japanese()
	word.reading_font = GameFonts.reading()
	word.meaning_font = GameFonts.body()
	if text_size>=30:
		word.min_reading_size=22
		word.group_spacing=6.0
	word.colour_reading_groups=true
	word.merge_adjacent_readings=false
	word.show_reading_guides=false
	word.ink = Color(SengokuUI.TEXT)
	word.reading_ink=Color(SengokuUI.MUTED)
	word.meaning_ink=Color(SengokuUI.BRASS)
	word.meaning_size = 22 if text_size>=36 else 20
	word.position = rect.position
	word.size = rect.size
	word.set_word({"jp":name_value.get("jp",""),"reading":name_value.get("reading",""),"ko":name_value.get("name",""),"parts":name_value.get("parts",[])},text_size)
	parent.add_child(word)
	return word

func _panel(parent: Node, rect: Rect2, accent: bool = false, texture_opacity: float = .28) -> Panel:
	var panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel",SengokuUI.frame(SengokuUI.SURFACE,SengokuUI.BRASS if accent else SengokuUI.LINE,accent))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	SengokuUI.texture_layer(panel,"lacquer",minf(texture_opacity,.18))
	return panel

func _flow_label(parent: Node, text: String, text_size: int = 20, colour: String = SengokuUI.TEXT) -> Label:
	var label: Label = _label(parent,text,Rect2(),text_size,colour)
	label.custom_minimum_size.x = 1
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _divider(parent: Node) -> Control:
	var line: Control = SengokuUI.ornament(parent,Rect2(),"divider",SengokuUI.BRASS)
	line.custom_minimum_size = Vector2(1,5)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line

static func _warroom_texture() -> Texture2D:
	var path: String = WARROOM_PATH
	if _background_cache.has(path):
		return _background_cache[path]
	var texture: Texture2D
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image: Image = Image.load_from_file(path)
		if image!=null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	if texture!=null:
		_background_cache[path] = texture
	return texture

func _rebuild() -> void:
	if not visible or not is_inside_tree():
		return
	var active_catalog: Array = _active_catalog()
	var definition: Dictionary = progress.unit_definition(selected_unit_id)
	if definition.is_empty() or not bool(definition.get("active",true)):
		definition = active_catalog[0] if not active_catalog.is_empty() else {}
		selected_unit_id = str(definition.get("id",""))
	skills_scroll=null
	for child in get_children():
		child.hide()
		remove_child(child)
		child.queue_free()
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var background = TextureRect.new()
	background.name = "BarracksWarroom"
	background.texture = _warroom_texture()
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var header: Panel = _panel(self,Rect2(28,18,screen.x-56,118))
	header.name = "BarracksHeader"
	SengokuUI.ornament(header,Rect2(14,14,40,40),"crest",SengokuUI.BRASS)
	var title: Label=_label(header,"兵舎",Rect2(66,10,128,78),30,SengokuUI.TEXT)
	title.name="BarracksTitle"
	title.add_theme_font_override("font",GameFonts.japanese())
	_label(header,"병영",Rect2(210,30,90,28),22,SengokuUI.MUTED).name="BarracksSubtitle"
	_label(header,"병종 %d / %d  ·  전장 %d개 제패" % [progress.unlocked_units().size(),active_catalog.size(),progress.data.maps.size()],Rect2(318,82,430,29),20,SengokuUI.MUTED)
	var wallet = _label(header,"군자금  %d" % int(progress.data.army.currency),Rect2(header.size.x-676,20,210,36),24,SengokuUI.TEXT)
	wallet.name = "BarracksCurrency"
	wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var back = _button(header,"돌아가기",Rect2(header.size.x-174,20,156,52),func(): hide(); closed.emit())
	back.name = "BarracksBack"
	var practice = _button(header,"병종 연습",Rect2(header.size.x-438,20,248,52),func(): training_requested.emit(selected_unit_id))
	practice.name = "BarracksTraining"
	var practice_unlocked: bool = selected_unit_id in progress.unlocked_units()
	practice.disabled = not can_practice or not practice_unlocked
	if not practice_unlocked:
		practice.tooltip_text = "병종을 해금하면 연습할 수 있습니다."
	elif not can_practice:
		practice.text = "새 전장 준비 중"
		practice.tooltip_text = "새 전장이 준비되면 연습할 수 있습니다."
	practice.add_theme_font_size_override("font_size",20)
	if not can_train:
		_label(header,"출진 중 · 영구 강화 대기",Rect2(780,82,header.size.x-798,29),20,SengokuUI.WARNING)
	elif not can_practice:
		_label(header,"새 전장 준비 중",Rect2(780,82,header.size.x-798,29),20,SengokuUI.MUTED).name = "PracticeUnavailableNote"
	var content_y: float = 148
	var roster_y: float = screen.y-156
	var content_height: float = roster_y-content_y-8
	var art_width: float = clampf((screen.x-56)*.31,380,610)
	var detail_width: float = screen.x-56-art_width-26
	var art_x: float = 28+detail_width+26
	if not definition.is_empty():
		_build_commander(definition,Rect2(art_x,content_y,art_width,content_height))
		_build_detail(_panel(self,Rect2(28,content_y,detail_width,content_height),true,.12),definition)
	_displayed_unit_id = selected_unit_id
	var roster: Panel = _panel(self,Rect2(28,roster_y,screen.x-56,132))
	roster.name = "BarracksRoster"
	var roster_margins: MarginContainer=MarginContainer.new()
	roster_margins.name="ArmyRosterMargins"
	roster.add_child(roster_margins)
	roster_margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var roster_style: StyleBox=roster.get_theme_stylebox("panel")
	roster_margins.add_theme_constant_override("margin_left",maxi(8,ceili(roster_style.get_margin(SIDE_LEFT))))
	roster_margins.add_theme_constant_override("margin_right",maxi(8,ceili(roster_style.get_margin(SIDE_RIGHT))))
	roster_margins.add_theme_constant_override("margin_top",8)
	roster_margins.add_theme_constant_override("margin_bottom",8)
	var list = HBoxContainer.new()
	list.name = "ArmyRosterList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",8)
	roster_margins.add_child(list)
	var card_count: int = maxi(1,active_catalog.size())
	var roster_width: float=roster.size.x-roster_margins.get_theme_constant("margin_left")-roster_margins.get_theme_constant("margin_right")
	# Round down before container expansion: fractional minimum widths used to
	# exceed the row by a few pixels and create a horizontal scrollbar.
	var card_width: float = floorf((roster_width-8.0*maxi(0,card_count-1))/float(card_count))
	for entry in active_catalog:
		_build_roster_row(list,entry,card_width)

func _restore_skill_reading(expected: ScrollContainer, amount: int) -> void:
	# Wrapped descriptions receive their final height during container layout.
	# Restoring before that pass clamps a valid old position to zero.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(expected) and expected==skills_scroll:
		expected.scroll_vertical = amount

func _build_roster_row(parent: Node, definition: Dictionary, width: float) -> void:
	var id: String = str(definition.id)
	var available: bool = id in progress.unlocked_units()
	var row = _button(parent,"",Rect2(),_select_unit.bind(id))
	row.name = "ArmyCard_%s" % id
	row.custom_minimum_size = Vector2(maxf(1,width),116)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.clip_contents = true
	row.tooltip_text = "%s · 영구 Lv.%d\n%s" % [str(definition.name),progress.army_level(id),str(definition.role)] if available else "전장 %d개 제패 시 해금" % int(definition.unlockClears)
	row.set_meta("unitId",id)
	row.set_meta("unlocked",available)
	row.set_meta("selected",selected_unit_id==id)
	if selected_unit_id==id:
		row.add_theme_stylebox_override("normal",SengokuUI.selected())
		var marker = ColorRect.new()
		marker.color = Color(SengokuUI.BLUE)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(marker)
		marker.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		marker.offset_top = -3
	var title = _ruby(row,definition,Rect2(14,7,maxf(1,width-28),102),24)
	title.name = "ArmyCardName"
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.offset_left=14
	title.offset_right=-14
	title.offset_top=7
	title.offset_bottom=-7
	if not available:
		title.modulate = Color(.58,.56,.52,1)

func _select_unit(id: String) -> void:
	var definition: Dictionary = progress.unit_definition(id)
	if definition.is_empty() or not bool(definition.get("active",true)):
		return
	selected_unit_id = id
	feedback = ""
	_rebuild()

func _build_commander(definition: Dictionary, rect: Rect2) -> void:
	var id: String = str(definition.id)
	var hero: Dictionary = progress.army_commander(id)
	var name_value: Dictionary = {"jp":hero.get("jp",""),"reading":hero.get("reading",""),"name":hero.get("nameKo","")}
	var plaque = Panel.new()
	plaque.name = "CommanderNamePlaque"
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.position = rect.position+Vector2(4,0)
	plaque.size = Vector2(rect.size.x-8,144)
	plaque.add_theme_stylebox_override("panel",SengokuUI.textured_panel("paper",Color("fff5df")))
	add_child(plaque)
	var title = _ruby(plaque,name_value,SengokuUI.content_rect(plaque),32)
	title.name = "CommanderName"
	title.ink = Color("231f1a")
	title.reading_ink = Color("463923")
	title.meaning_ink = Color("30251b")
	var portrait_palette: Array[Color]=[Color("725022"),Color("285266")]
	title.reading_group_palette=portrait_palette
	title.outline_size = 1
	title.outline_ink = Color("e1c78b88")
	var picture = CommanderPortrait.new()
	picture.name = "SelectedArmyPortrait"
	picture.position = rect.position+Vector2(0,148)
	picture.size = Vector2(rect.size.x,rect.size.y-148)
	picture.configure(id,int(progress.army_evolution(id).stage),id in progress.unlocked_units(),str(hero.get("id","")))
	add_child(picture)

func _build_detail(parent: Control, definition: Dictionary) -> void:
	parent.name = "CommanderDetail"
	var id: String = str(definition.id)
	var unlocked: bool = id in progress.unlocked_units()
	var level: int = progress.army_level(id)
	var evolution: Dictionary = progress.army_evolution(id)
	var stats: Dictionary = progress.army_stats(id)
	var hero: Dictionary = progress.army_commander(id)
	var compact: bool=parent.size.y<540
	var detail_points: int=18 if compact else 20
	var skills: Array=[]
	var recruitment_skills: Array=[]
	for skill in progress.army_skills(id):
		if str(skill.id) in ["archer_pair","spear_pair","spear_company"]: recruitment_skills.append(skill)
		else: skills.append(skill)
	var margin: MarginContainer=MarginContainer.new()
	margin.name="CommanderDetailMargins"
	parent.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right"]: margin.add_theme_constant_override("margin_"+side,18)
	for side in ["top","bottom"]: margin.add_theme_constant_override("margin_"+side,10)
	var body: VBoxContainer=VBoxContainer.new()
	body.add_theme_constant_override("separation",2 if compact else 3)
	margin.add_child(body)
	var identity: HBoxContainer=HBoxContainer.new()
	identity.add_theme_constant_override("separation",12)
	body.add_child(identity)
	var name_label: Label=_flow_label(identity,str(evolution.name),24 if compact else 26,SengokuUI.TEXT)
	name_label.name="CommanderUnitName"
	var level_label: Label=_flow_label(identity,"Lv.%d / 10" % level,24,SengokuUI.BLUE)
	level_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	level_label.custom_minimum_size.x=124
	level_label.size_flags_horizontal=Control.SIZE_SHRINK_END
	level_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	level_label.name="CommanderLevel"
	var role_row: HBoxContainer=HBoxContainer.new()
	role_row.add_theme_constant_override("separation",12)
	body.add_child(role_row)
	var role_label: Label=_flow_label(role_row,str(definition.role),detail_points,SengokuUI.MUTED)
	role_label.add_theme_font_size_override("font_size",detail_points)
	role_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	role_label.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	role_label.name="CommanderUnitRole"
	role_label.tooltip_text=str(definition.description)+"\n"+str(hero.get("displayRoleKo",""))+"\n"+str(hero.get("historyKo",""))+"\n"+str(hero.get("adaptationKo",""))
	var description: Label=_flow_label(role_row,str(definition.description),detail_points,SengokuUI.TEXT)
	description.add_theme_font_size_override("font_size",detail_points)
	description.name="CommanderDescription"
	description.autowrap_mode=TextServer.AUTOWRAP_OFF
	description.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	description.clip_text=true
	description.tooltip_text=str(definition.description)
	if not feedback.is_empty():
		description.text=feedback
		description.tooltip_text=feedback
		description.add_theme_color_override("font_color",Color(SengokuUI.WARNING))
	_divider(body)
	var skill_title: Label=_flow_label(body,"전투 스킬",18,SengokuUI.TEXT)
	skill_title.name="CommanderSkillHeading"
	skill_title.add_theme_font_size_override("font_size",18)
	# Keep the original skills / 演武 row; three visible cards replace its scroll.
	var skill_row: HBoxContainer=HBoxContainer.new()
	skill_row.name="CommanderSkillDemonstration"
	skill_row.add_theme_constant_override("separation",12)
	skill_row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(skill_row)
	var skill_list: VBoxContainer=VBoxContainer.new()
	skill_list.name="CommanderSkillList"
	skill_list.add_theme_constant_override("separation",4)
	skill_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	skill_list.size_flags_vertical=Control.SIZE_EXPAND_FILL
	skill_row.add_child(skill_list)
	var preview_column: VBoxContainer=VBoxContainer.new()
	preview_column.name="UnitDemonstrationColumn"
	preview_column.custom_minimum_size.x=clampf(parent.size.x*.20,156,190)
	preview_column.size_flags_vertical=Control.SIZE_EXPAND_FILL
	preview_column.add_theme_constant_override("separation",2)
	skill_row.add_child(preview_column)
	var demonstration_label: Label=_flow_label(preview_column,"演武 · 병종 시연",20,"e8d4a9")
	demonstration_label.name="UnitDemonstrationTitle"
	demonstration_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	unit_preview=UnitPreview.new()
	unit_preview.name="SelectedUnitPreview"
	unit_preview.animate_poses=false
	unit_preview.smooth_blending=false
	unit_preview.custom_minimum_size=Vector2(1,84)
	unit_preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	unit_preview.size_flags_vertical=Control.SIZE_EXPAND_FILL
	unit_preview.configure(id,int(evolution.stage),unlocked)
	if unit_preview.has_method("set_skill_preview_level"): unit_preview.call("set_skill_preview_level",level)
	preview_column.add_child(unit_preview)
	for skill in skills:
		var ready: bool=unlocked and bool(skill.unlocked)
		var card: PanelContainer=PanelContainer.new()
		card.name="SkillCard_"+str(skill.id)
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.size_flags_vertical=Control.SIZE_EXPAND_FILL
		card.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var card_frame: StyleBoxFlat=SengokuUI.frame(SengokuUI.SURFACE,SengokuUI.BRASS if ready else SengokuUI.LINE)
		card_frame.content_margin_top=6
		card_frame.content_margin_bottom=6
		card_frame.content_margin_left=10
		card_frame.content_margin_right=10
		card.add_theme_stylebox_override("panel",card_frame)
		skill_list.add_child(card)
		var block: VBoxContainer=VBoxContainer.new()
		block.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		block.add_theme_constant_override("separation",2)
		card.add_child(block)
		var skill_heading: HBoxContainer=HBoxContainer.new()
		skill_heading.add_theme_constant_override("separation",8)
		block.add_child(skill_heading)
		var badge: Label=_flow_label(skill_heading,str(skill.get("levelLabel","Lv.%d · %s" % [int(skill.level),"해금" if ready else "대기"])),18,SengokuUI.BLUE if ready else SengokuUI.MUTED)
		badge.add_theme_font_size_override("font_size",18)
		badge.name="SkillLevel_"+str(skill.id)
		badge.autowrap_mode=TextServer.AUTOWRAP_OFF
		badge.size_flags_horizontal=Control.SIZE_SHRINK_END
		var heading: Label=_flow_label(skill_heading,str(skill.titleKo),detail_points,SengokuUI.TEXT if ready else SengokuUI.MUTED)
		heading.add_theme_font_size_override("font_size",detail_points)
		skill_heading.move_child(heading,0)
		heading.name="Skill_"+str(skill.id)
		heading.set_meta("skillId",str(skill.id))
		heading.set_meta("skillIds",skill.get("skillIds",[str(skill.id)]))
		heading.set_meta("unlocked",ready)
		var full: String=str(skill.descriptionKo)
		var detail: Label=_flow_label(block,full,detail_points,SengokuUI.TEXT if ready else SengokuUI.MUTED)
		detail.add_theme_font_size_override("font_size",detail_points)
		detail.name="SkillDescription_"+str(skill.id)
		detail.tooltip_text=full
	_divider(body)
	var quantity: int = UnitGrowth.recruit_quantity(id,level,definition)
	var combat_info: String = "1인 공격 %.1f · %.2f초" % [float(stats.damage),float(stats.interval)]
	if id=="monk": combat_info = "1인 치료 %.1f · %.1f초" % [float(stats.healAmount),float(stats.healInterval)]
	var production: Label=_flow_label(body,"%s · 소집 %d명 · 군량 %d · %.1f초" % [combat_info,quantity,progress.army_recruit_cost(id),float(definition.get("recruitSeconds",2))],18,SengokuUI.TEXT)
	production.add_theme_font_size_override("font_size",18)
	production.name="ProductionAndUnlocks"
	if id=="archer" and not recruitment_skills.is_empty():
		var entry: Dictionary=recruitment_skills[0]
		production.text+=" · Lv.%d: 2명 %s" % [int(entry.level),"해금" if bool(entry.unlocked) else "대기"]
		production.tooltip_text=str(entry.descriptionKo)
		# Recruitment uses the same order cost/time; it is not a fourth combat skill.
		production.text+="\n같은 비용·생산 시간으로 궁병 2명 배치 · 병사별 독립 공격·피격"
	elif id=="spear" and not recruitment_skills.is_empty():
		var milestones: Array[String]=[]
		for entry in recruitment_skills:
			milestones.append("Lv.%d: %d명 %s" % [int(entry.level),3 if str(entry.id)=="spear_pair" else 5,"해금" if bool(entry.unlocked) else "대기"])
		production.text+="\n소집 1→3→5명 · "+" / ".join(milestones)
		production.tooltip_text="같은 비용·생산 시간으로 소집하며 각 병사는 독립적으로 공격하고 피해를 받습니다."

	var defense: Label=_flow_label(body,"1인 체력 %.0f · 피해 감소 %.1f%%" % [float(stats.health),float(stats.armor)*100.0],18,SengokuUI.MUTED)
	defense.add_theme_font_size_override("font_size",18)
	defense.name="ArmyDefenseStats"
	if id=="monk":
		production.tooltip_text = "회복 부적 %.1f / 초 · 승전 기도 %.1f 회복\n치료량은 병영의 영구 훈련·진화에 따라 성장합니다." % [float(stats.supportStats.talismanPerSecond),float(stats.supportStats.prayerHealAmount)]
	var meter = HBoxContainer.new()
	meter.add_theme_constant_override("separation",4)
	body.add_child(meter)
	for step in range(10):
		var mark = ColorRect.new()
		mark.custom_minimum_size = Vector2(1,5)
		mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mark.color = Color(SengokuUI.BRASS if step<level else SengokuUI.LINE)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meter.add_child(mark)
	var action_row = HBoxContainer.new()
	action_row.name = "CommanderUpgradeActions"
	action_row.add_theme_constant_override("separation",12)
	body.add_child(action_row)
	var next_text: String = "장비 진화 Lv.4 · 8"
	if unlocked and level<10:
		var next: Dictionary = progress.army_stats(id,level+1)
		next_text = "다음 공격 %.1f" % float(next.damage) if id!="monk" else "다음 치료 %.1f" % float(next.healAmount)
		for skill in progress.army_skills(id,level+1):
			if int(skill.level)==level+1: next_text = "다음 · "+str(skill.titleKo)+" 해금"
		var next_quantity: int = UnitGrowth.recruit_quantity(id,level+1,definition)
		if next_quantity!=quantity: next_text = "다음 소집 %d명 · 1인 공격 %.1f" % [next_quantity,float(next.damage)]
	elif level>=10:
		next_text = "영구 훈련 완료"
	var next_label = _flow_label(action_row,next_text,20,SengokuUI.BLUE)
	next_label.name = "CommanderNextUpgrade"
	next_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cost: int = progress.army_upgrade_cost(id)
	var train_text: String = "영구 강화 · 군자금 %d" % cost
	if not unlocked:
		train_text = "전장 %d개 제패 시 해금" % int(definition.unlockClears)
	elif level>=10:
		train_text = "최대 훈련 Lv.10"
	var button = _button(action_row,train_text,Rect2(),_train.bind(id))
	button.name = "Train_%s" % id
	button.custom_minimum_size = Vector2(280,48)
	button.add_theme_stylebox_override("normal",SengokuUI.textured_button("normal",true))
	button.disabled = not unlocked or not can_train or level>=10 or int(progress.data.army.currency)<cost
	if unlocked and level<10:
		button.tooltip_text = "영구 Lv.%d → Lv.%d%s\n소집 1회 %d명 · 1인 체력 %.0f · 피해 감소 %.1f%%" % [level,level+1," · 새 장비로 진화" if int(progress.army_stats(id,level+1).evolution)>int(stats.evolution) else "",UnitGrowth.recruit_quantity(id,level+1,definition),float(progress.army_stats(id,level+1).health),float(progress.army_stats(id,level+1).armor)*100.0]

func _train(id: String) -> void:
	if not can_train:
		return
	selected_unit_id = id
	var result: Dictionary = progress.upgrade_army_unit(id)
	feedback = str(result.message)
	if bool(result.get("ok",false)):
		army_changed.emit()
	_rebuild()
