extends Control

signal closed
signal army_changed
signal training_requested(unit_id: String)

const RubyText = preload("res://native/ruby_label.gd")
const SengokuUI = preload("res://native/sengoku_ui.gd")
const CommanderPortrait = preload("res://native/commander_portrait.gd")
const UnitPreview = preload("res://native/barracks_portrait.gd")
const GameFonts = preload("res://native/game_fonts.gd")
const WARROOM_PATH: String = "res://assets/ui/barracks-warroom.png"
const FALLBACK_BACKGROUND: String = "res://assets/map-castle.png"
static var _background_cache: Dictionary = {}
var progress: RefCounted
var font: Font
var can_train: bool = true
var feedback: String = ""
var scroll: ScrollContainer
var skills_scroll: ScrollContainer
var unit_preview: Control
var selected_unit_id: String = ""
var _displayed_unit_id: String = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().size_changed.connect(_rebuild)
	hide()

func open(training_allowed: bool = true) -> void:
	can_train = training_allowed
	feedback = ""
	if progress.unit_definition(selected_unit_id).is_empty():
		selected_unit_id = str(progress.data.army.get("selected","archer"))
	show()
	_rebuild()

func _label(parent: Node, text: String, rect: Rect2, text_size: int = 20, colour: String = "e1e6e9") -> Label:
	var label = Label.new()
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
	var button = Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.clip_text = true
	button.add_theme_font_override("font",font)
	button.add_theme_font_size_override("font_size",22)
	for state in ["normal","hover","pressed","disabled","focus"]:
		button.add_theme_stylebox_override(state,SengokuUI.textured_button(state))
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
	word.reading_ink=Color("d9cfb8")
	word.meaning_ink=Color("d3bc88")
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
	panel.add_theme_stylebox_override("panel",SengokuUI.frame("191713f5",SengokuUI.BRASS,accent))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	SengokuUI.texture_layer(panel,"lacquer",texture_opacity)
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
	var path: String = WARROOM_PATH if FileAccess.file_exists(WARROOM_PATH) or ResourceLoader.exists(WARROOM_PATH) else FALLBACK_BACKGROUND
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
	var previous_skills_scroll: int = skills_scroll.scroll_vertical if is_instance_valid(skills_scroll) and _displayed_unit_id==selected_unit_id else 0
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
	var header: Panel = _panel(self,Rect2(28,18,screen.x-56,84))
	header.name = "BarracksHeader"
	SengokuUI.ornament(header,Rect2(14,12,40,40),"crest",SengokuUI.BRASS)
	var title: Label=_label(header,"兵舎",Rect2(66,5,140,54),36,SengokuUI.TEXT)
	title.name="BarracksTitle"
	title.add_theme_font_override("font",GameFonts.japanese())
	_label(header,"병영",Rect2(225,19,100,34),22,SengokuUI.MUTED).name="BarracksSubtitle"
	_label(header,"병종 %d / 8  ·  전장 %d개 제패" % [progress.unlocked_units().size(),progress.data.maps.size()],Rect2(16,51,450,29),20,"e2d4bb")
	var wallet = _label(header,"군자금  %d" % int(progress.data.army.currency),Rect2(screen.x-470,9,235,38),26,"d3bc88")
	wallet.name = "BarracksCurrency"
	wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var back = _button(header,"돌아가기",Rect2(screen.x-231,9,158,47),func(): hide(); closed.emit())
	back.name = "BarracksBack"
	var practice = _button(self,"鍛錬 · 훈련 던전",Rect2(screen.x-304,75,232,42),func(): training_requested.emit(selected_unit_id))
	practice.name = "BarracksTraining"
	practice.disabled = not selected_unit_id in progress.unlocked_units()
	practice.add_theme_font_size_override("font_size",20)
	for state_name in ["normal","hover","pressed","disabled","focus"]:
		var compact = SengokuUI.textured_button(state_name)
		compact.content_margin_top = 3
		compact.content_margin_bottom = 3
		practice.add_theme_stylebox_override(state_name,compact)
	if not can_train:
		_label(header,"출진 중 · 영구 강화 대기",Rect2(480,51,screen.x-812,29),20,"e1bd91")
	var content_y: float = 126
	var roster_y: float = screen.y-156
	var content_height: float = roster_y-content_y-14
	var art_width: float = clampf((screen.x-56)*.31,380,610)
	var detail_width: float = screen.x-56-art_width-26
	var art_x: float = 28+detail_width+26
	var definition: Dictionary = progress.unit_definition(selected_unit_id)
	if definition.is_empty() and not progress.unit_catalog.is_empty():
		definition = progress.unit_catalog[0]
		selected_unit_id = str(definition.id)
	if not definition.is_empty():
		_build_commander(definition,Rect2(art_x,content_y,art_width,content_height))
		_build_detail(_panel(self,Rect2(28,content_y,detail_width,content_height),true,.12),definition)
	_displayed_unit_id = selected_unit_id
	var roster: Panel = _panel(self,Rect2(28,roster_y,screen.x-56,132))
	roster.name = "BarracksRoster"
	scroll = ScrollContainer.new()
	scroll.name = "ArmyRosterScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(8,8)
	scroll.size = roster.size-Vector2(16,16)
	roster.add_child(scroll)
	var list = HBoxContainer.new()
	list.name = "ArmyRosterList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",8)
	scroll.add_child(list)
	var card_width: float = (scroll.size.x-56)/8.0
	for entry in progress.unit_catalog:
		_build_roster_row(list,entry,card_width)
	if is_instance_valid(skills_scroll):
		_restore_skill_reading.call_deferred(skills_scroll,previous_skills_scroll)

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
	row.custom_minimum_size = Vector2(maxf(142,width),116)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.clip_contents = true
	row.tooltip_text = "%s · 영구 Lv.%d\n%s" % [str(definition.name),progress.army_level(id),str(definition.role)] if available else "전장 %d개 제패 시 해금" % int(definition.unlockClears)
	row.set_meta("unitId",id)
	row.set_meta("unlocked",available)
	row.set_meta("selected",selected_unit_id==id)
	if selected_unit_id==id:
		row.add_theme_stylebox_override("normal",SengokuUI.textured_button("normal",false,true))
		var marker = ColorRect.new()
		marker.color = Color(SengokuUI.BRASS)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(marker)
		marker.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		marker.offset_top = -3
	var title = _ruby(row,definition,Rect2(4,4,maxf(142,width)-8,108),25)
	title.name = "ArmyCardName"
	if not available:
		title.modulate = Color(.58,.56,.52,1)

func _select_unit(id: String) -> void:
	if progress.unit_definition(id).is_empty():
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
	plaque.size = Vector2(rect.size.x-8,128)
	plaque.add_theme_stylebox_override("panel",SengokuUI.textured_panel("paper",Color("fff5df")))
	add_child(plaque)
	var title = _ruby(plaque,name_value,Rect2(10,0,plaque.size.x-20,128),32)
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
	picture.position = rect.position+Vector2(0,132)
	picture.size = Vector2(rect.size.x,rect.size.y-132)
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
	var skills: Array = progress.army_skills(id)
	var ninja_basics: bool = id=="ninja" and skills.is_empty()
	var margin = MarginContainer.new()
	margin.name = "CommanderDetailMargins"
	parent.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right"]: margin.add_theme_constant_override("margin_"+side,22)
	for side in ["top","bottom"]: margin.add_theme_constant_override("margin_"+side,12)
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation",5)
	margin.add_child(body)
	var identity = HBoxContainer.new()
	identity.add_theme_constant_override("separation",12)
	body.add_child(identity)
	var name_label = _flow_label(identity,str(evolution.name),28,"eee0be")
	name_label.name = "CommanderUnitName"
	var level_label = _flow_label(identity,"Lv.%d / 10" % level,24,"d3bc88")
	level_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	level_label.custom_minimum_size.x = 124
	level_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_label.name = "CommanderLevel"
	var role_label = _flow_label(body,str(definition.role),22,"d3bc88")
	role_label.name = "CommanderUnitRole"
	role_label.tooltip_text = str(hero.get("displayRoleKo",""))+"\n"+str(hero.get("historyKo",""))+"\n"+str(hero.get("adaptationKo",""))
	var description = _flow_label(body,str(definition.description),20,"eadfc9")
	description.name = "CommanderDescription"
	if not feedback.is_empty():
		var notice = _flow_label(body,feedback,20,"e1bd91")
		notice.name = "BarracksFeedback"
	_divider(body)
	var skill_header = HBoxContainer.new()
	body.add_child(skill_header)
	var skill_title = _flow_label(skill_header,"기습·암살 운용" if ninja_basics else "전투 스킬",22,"eee0be")
	skill_title.name = "CommanderSkillHeading"
	var thresholds = _flow_label(skill_header,"기본 행동" if ninja_basics else "영구 Lv.3 · 5 · 8",20,"b9a887")
	thresholds.name = "CommanderSkillThresholds"
	thresholds.autowrap_mode = TextServer.AUTOWRAP_OFF
	thresholds.size_flags_horizontal = Control.SIZE_SHRINK_END
	thresholds.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var skill_row = HBoxContainer.new()
	skill_row.name = "CommanderSkillDemonstration"
	skill_row.add_theme_constant_override("separation",16)
	skill_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(skill_row)
	skills_scroll = ScrollContainer.new()
	skills_scroll.name = "CommanderSkillsScroll"
	skills_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	skills_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skills_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_scroll.custom_minimum_size.y = 84
	skill_row.add_child(skills_scroll)
	var preview_column = VBoxContainer.new()
	preview_column.name = "UnitDemonstrationColumn"
	preview_column.custom_minimum_size.x = clampf(parent.size.x*.29,210,350)
	preview_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_column.add_theme_constant_override("separation",2)
	skill_row.add_child(preview_column)
	var demonstration_label = _flow_label(preview_column,"演武 · 병종 시연",20,"e8d4a9")
	demonstration_label.name = "UnitDemonstrationTitle"
	demonstration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit_preview = UnitPreview.new()
	unit_preview.name = "SelectedUnitPreview"
	unit_preview.animate_poses = false
	unit_preview.smooth_blending = false
	unit_preview.custom_minimum_size = Vector2(1,84)
	unit_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	unit_preview.configure(id,int(evolution.stage),unlocked)
	preview_column.add_child(unit_preview)
	var skill_list = VBoxContainer.new()
	skill_list.name = "CommanderSkillList"
	skill_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_list.add_theme_constant_override("separation",10)
	skills_scroll.add_child(skill_list)
	for skill in skills:
		var ready: bool = unlocked and bool(skill.unlocked)
		var block = VBoxContainer.new()
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.add_theme_constant_override("separation",2)
		skill_list.add_child(block)
		var heading = _flow_label(block,"Lv.%d · %s%s" % [int(skill.level),str(skill.titleKo),"  해금" if ready else ""],22,"eed39d" if ready else "a69980")
		heading.name = "Skill_"+str(skill.id)
		heading.set_meta("skillId",str(skill.id))
		heading.set_meta("unlocked",ready)
		var detail = _flow_label(block,str(skill.descriptionKo),20,"f2ead9" if ready else "c6b99d")
		detail.name = "SkillDescription_"+str(skill.id)
		detail.tooltip_text = str(skill.descriptionKo)
	if ninja_basics:
		var basics: Array = [
			{"id":"ambush","title":"외곽 매복","description":"보라색 엄폐 지점에 배치합니다. 가까이 온 적을 자동으로 기습합니다."},
			{"id":"raid","title":"진지 습격","description":"닌자를 선택한 뒤 같은 길의 가까운 적 사격 진지를 클릭하십시오. 이동해 공격하는 명령이며, 즉사를 보장하지 않습니다. 물이나 막힌 지형은 건너지 않습니다."},
			{"id":"return","title":"엄폐 복귀","description":"기습이나 진지 습격을 마치면 처음 배치한 엄폐 지점으로 돌아가 대기합니다."}
		]
		for entry in basics:
			var block = VBoxContainer.new()
			block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			block.add_theme_constant_override("separation",2)
			skill_list.add_child(block)
			var heading = _flow_label(block,str(entry.title),22,"e1c58f")
			heading.name = "NinjaBasic_"+str(entry.id)
			var detail = _flow_label(block,str(entry.description),20,"f2ead9")
			detail.name = "NinjaBasicDescription_"+str(entry.id)
	_divider(body)
	var combat_info: String = "공격 %.1f · %.2f초" % [float(stats.damage),float(stats.interval)]
	if id=="monk": combat_info = "치료 %.1f · %.1f초" % [float(stats.healAmount),float(stats.healInterval)]
	var production = _flow_label(body,"%s  ·  군량 %d · 생산 %.1f초" % [combat_info,progress.army_recruit_cost(id),float(definition.get("recruitSeconds",2))],20,"eadfc9")
	production.name = "ProductionAndUnlocks"
	var defense = _flow_label(body,"체력 %.0f  ·  피해 감소 %.1f%%" % [float(stats.health),float(stats.armor)*100.0],20,"eadfc9")
	defense.name = "ArmyDefenseStats"
	if id=="monk":
		production.tooltip_text = "회복 부적 %.1f / 초 · 승전 기도 %.1f 회복\n치료량은 병영의 영구 훈련·진화에 따라 성장합니다." % [float(stats.supportStats.talismanPerSecond),float(stats.supportStats.prayerHealAmount)]
	var meter = HBoxContainer.new()
	meter.add_theme_constant_override("separation",4)
	body.add_child(meter)
	for step in range(10):
		var mark = ColorRect.new()
		mark.custom_minimum_size = Vector2(1,5)
		mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mark.color = Color(SengokuUI.BRASS if step<level else "534831")
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
	elif level>=10:
		next_text = "영구 훈련 완료"
	var next_label = _flow_label(action_row,next_text,20,"d3bc88")
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
	button.custom_minimum_size = Vector2(304,48)
	for state_name in ["normal","hover","pressed","disabled","focus"]:
		button.add_theme_stylebox_override(state_name,SengokuUI.textured_button(state_name,true))
	button.disabled = not unlocked or not can_train or level>=10 or int(progress.data.army.currency)<cost
	if unlocked and level<10:
		button.tooltip_text = "영구 Lv.%d → Lv.%d%s\n체력 %.0f · 피해 감소 %.1f%%" % [level,level+1," · 새 장비로 진화" if int(progress.army_stats(id,level+1).evolution)>int(stats.evolution) else "",float(progress.army_stats(id,level+1).health),float(progress.army_stats(id,level+1).armor)*100.0]

func _train(id: String) -> void:
	if not can_train:
		return
	selected_unit_id = id
	var result: Dictionary = progress.upgrade_army_unit(id)
	feedback = str(result.message)
	if bool(result.get("ok",false)):
		army_changed.emit()
	_rebuild()
