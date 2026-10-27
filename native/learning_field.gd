extends Control

signal target_chosen(target_id: String)
signal hint_requested
signal listen_requested
signal continue_requested

const RubyText = preload("res://native/ruby_label.gd")
const UIStyle = preload("res://native/sengoku_ui.gd")
const GameFonts = preload("res://native/game_fonts.gd")
const Cloze = preload("res://native/learning_cloze.gd")
const Presentation = preload("res://native/battlefield_presentation.gd")
const Battlefield = preload("res://native/battlefield_3d.gd")
const RenderedArt = preload("res://native/rendered_battlefield_helpers.gd")
const BattlefieldMaterials = preload("res://native/battlefield_materials.gd")
static var _presentation_stages: Dictionary = {}
static var _picture_cache: Dictionary = {}
const MOUNTAIN_REFERENCE: String="res://assets/painted-battlefield/mountain-reference.png"
var font: Font
var mission: Dictionary = {}
var choosing: bool = false
var resolved: bool = false
var hinted: bool = false
var report_clock: float = 0.0
var report_card: Panel
var report_frame: StyleBox
var question_sheet: Panel
var report_text: Control
var report_heading: Control
var action_card: Panel
var action_frame: StyleBox
var feedback: Label
var hint_button: Button
var listen_button: Button
var continue_button: Button
var target_buttons: Array = []
var target_anchors: Array = []
var correct_target: String = ""
var flow_paused: bool = false
var stage_texture: Texture2D
var world_texture: Texture2D
var world_projection: Callable
var world_focus_projection: Callable
var stage_id: String = ""
var presentation_mirrored: bool = false
var _background_stage: Dictionary = {}
var stage_art: Dictionary = {}
var _stage_art_signature: String = ""
var task_caption: Label
var interaction_enabled: bool = true
var choice_voice_available: bool = false
var announcement_row_height: float = 0.0
var announcement_anchor: Control
var question_item: Dictionary = {}
var reveal_item: Dictionary = {}
var live_battle: bool = false
var live_battle_bounds: Rect2
var live_panel_rect: Rect2
var live_panel: Panel
var _live_layout_overflow: bool = false

func _ready() -> void:
	theme = GameFonts.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(_arrange)
	live_panel=Panel.new()
	live_panel.name="LiveBattleLearningPanel"
	live_panel.mouse_filter=Control.MOUSE_FILTER_STOP
	var local_frame: StyleBoxFlat=UIStyle.frame("1e2527f5",UIStyle.BRASS)
	local_frame.shadow_size=0
	live_panel.add_theme_stylebox_override("panel",local_frame)
	add_child(live_panel)
	live_panel.hide()
	report_card = _panel(false)
	report_frame = report_card.get_theme_stylebox("panel")
	report_heading = RubyText.new()
	report_heading.name = "TranslatedReportHeading"
	report_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	report_heading.wrap_japanese = true
	report_heading.colour_reading_groups = true
	report_heading.ink = Color(UIStyle.BRASS)
	report_heading.reading_ink = Color(UIStyle.BRASS)
	report_heading.meaning_ink = Color(UIStyle.TEXT)
	report_heading.meaning_size = 17
	report_heading.set_word({"jp":"伝令","reading":"でんれい","ko":"전령 보고"},20,true)
	report_card.add_child(report_heading)
	task_caption = _label(report_card,"요청의 뜻에 맞는 일본어를 선택하십시오.",20,Color(UIStyle.MUTED))
	task_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task_caption.hide()
	announcement_anchor = Control.new()
	announcement_anchor.name = "ContextAnnouncementSlot"
	announcement_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	report_card.add_child(announcement_anchor)
	question_sheet = Panel.new()
	question_sheet.name = "ContextQuestionPaper"
	question_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	question_sheet.add_theme_stylebox_override("panel",UIStyle.textured_panel("paper"))
	report_card.add_child(question_sheet)
	report_text = RubyText.new()
	report_text.font = GameFonts.japanese()
	report_text.reading_font = GameFonts.reading()
	report_text.meaning_font = GameFonts.body()
	report_text.min_reading_size=22
	report_text.group_spacing=8.0
	report_text.merge_adjacent_readings=false
	report_text.show_reading_guides=false
	report_text.ink=Color(UIStyle.TEXT)
	report_text.reading_ink=Color("d9cfb8")
	report_text.meaning_ink=Color("d3bc88")
	report_text.wrap_japanese = true
	report_card.add_child(report_text)
	action_card = _panel()
	action_frame = action_card.get_theme_stylebox("panel")
	feedback = _label(action_card,"",20,Color(UIStyle.TEXT))
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_button = _button(action_card,"힌트 · 원문 보기",func(): hint_requested.emit())
	listen_button = _button(action_card,"보고 듣기",func(): listen_requested.emit())
	continue_button = _button(action_card,"임무 건너뛰기",func(): continue_requested.emit())
	clear()
	set_live_battle_mode(live_battle)

func set_live_battle_mode(enabled: bool) -> void:
	live_battle=enabled
	if report_card==null or action_card==null: return
	mouse_filter=Control.MOUSE_FILTER_IGNORE if live_battle or not choosing else Control.MOUSE_FILTER_STOP
	report_heading.meaning_size=13 if live_battle else 17
	report_heading.min_reading_size=11 if live_battle else 16
	report_text.group_spacing=3.0 if live_battle else 8.0
	if not live_battle:
		report_text.meaning_size=20
		report_text.min_reading_size=22
		for button in target_buttons:
			var choice_word: Control=button.get_node("DestinationWord")
			choice_word.meaning_size=20
			choice_word.min_reading_size=16
			choice_word.group_spacing=0.0
			button.get_node("DestinationAction").add_theme_font_size_override("font_size",18)
			button.get_node("ChoiceNumber").add_theme_font_size_override("font_size",22)
	task_caption.add_theme_font_size_override("font_size",14 if live_battle else 20)
	feedback.add_theme_font_size_override("font_size",14 if live_battle else 20)
	for button in [hint_button,listen_button,continue_button]:
		button.add_theme_font_size_override("font_size",15 if live_battle else 20)
		for state_name in ["normal","hover","pressed","disabled","focus"]:
			var style: StyleBox = UIStyle.textured_button(state_name)
			if live_battle:
				style=UIStyle.button(state_name)
				style.content_margin_left=6
				style.content_margin_right=6
				style.content_margin_top=4
				style.content_margin_bottom=4
			button.add_theme_stylebox_override(state_name,style)
	hint_button.text="힌트" if live_battle else "힌트 · 원문 보기"
	listen_button.text="듣기" if live_battle else "보고 듣기"
	# The compact footer shares the local panel background; restore the old
	# footer surface when returning to the separate full-screen study flow.
	action_card.add_theme_stylebox_override("panel",StyleBoxEmpty.new() if live_battle else action_frame)
	for child in action_card.get_children():
		if str(child.name).begins_with("MaterialSurface_"): child.visible=not live_battle
	_arrange()
	queue_redraw()

func set_live_battle_bounds(bounds: Rect2) -> void:
	if live_battle_bounds==bounds: return
	live_battle_bounds=bounds
	if is_node_ready(): _arrange()

func contains_live_point(local_point: Vector2) -> bool:
	return live_battle and choosing and is_visible_in_tree() and live_panel_rect.has_point(local_point)

func set_stage_background(path: String, stage: Dictionary = {}) -> void:
	world_texture = null
	world_projection = Callable()
	world_focus_projection = Callable()
	_background_stage = stage
	if _background_stage.is_empty() and not path.is_empty():
		for candidate in _stage_definitions().values():
			if str(candidate.get("background","")) == path:
				_background_stage = candidate
				break
	_sync_presentation(mission)
	queue_redraw()

func set_world_presentation(stage: Dictionary, texture: Texture2D, projection: Callable, focus_projection: Callable = Callable()) -> void:
	_background_stage = stage
	world_texture = texture
	world_projection = projection
	world_focus_projection = focus_projection
	_sync_presentation(mission)

func refresh_world_presentation() -> void:
	if world_projection.is_valid():
		_sync_presentation(mission)

func _target_view_point(canonical: Vector2) -> Vector2:
	if world_projection.is_valid():
		var projected: Vector2 = world_projection.call(canonical)
		return projected
	return view_point(canonical)

static func _stage_definitions() -> Dictionary:
	if _presentation_stages.is_empty():
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
		if decoded is Array:
			for stage in decoded:
				if stage is Dictionary:
					_presentation_stages[str(stage.get("id",""))] = stage
	return _presentation_stages

func _sync_presentation(value: Dictionary) -> void:
	var stages: Dictionary = _stage_definitions()
	var selected: Dictionary = _background_stage
	var mission_id: String = str(value.get("id",""))
	var explicit_id: String = str(value.get("mapId",value.get("stageId","")))
	if bool(_background_stage.get("paintedPresentation",false)):
		selected=_background_stage
	elif stages.has(explicit_id):
		selected = stages[explicit_id]
	else:
		for candidate_id in stages:
			if mission_id.begins_with(str(candidate_id)+"-context-"):
				selected = stages[candidate_id]
				break
	stage_id = str(selected.get("id",""))
	presentation_mirrored = Presentation.mirror_for_stage(selected)
	_sync_stage_art(selected)
	# Choices remain ordered by the authored target IDs. Only their scenery and
	# display anchors follow the battlefield; answer/support coordinates do not.
	for index in range(target_buttons.size()):
		var image: TextureRect = target_buttons[index].get_node_or_null("DestinationImage")
		if image != null:
			image.flip_h = presentation_mirrored
			if image.visible and index < value.get("targets",[]).size():
				image.texture = _target_crop(Presentation.point(value.targets[index].get("position",{})),str(value.targets[index].get("id","")))
		if index < value.get("targets",[]).size():
			target_anchors[index] = _target_view_point(Presentation.point(value.targets[index].get("position",{})))
	queue_redraw()

func _sync_stage_art(stage: Dictionary) -> void:
	if bool(stage.get("paintedPresentation",false)):
		var path: String=str(stage.get("paintedBackground",stage.get("background","")))
		stage_texture=_picture(path)
		stage_art={"mode":"painted","stageId":str(stage.get("id","")),"artPath":path,"coordinateSpace":"canonical_normalized_map"}
		_stage_art_signature=path
		return
	if stage.get("worldGeometry") is Dictionary and not stage.worldGeometry.is_empty():
		# The current authored floor and scenery are rendered by the real camera.
		stage_texture = world_texture
		stage_art = {"mode":"authored-world","stageId":str(stage.get("id","")),"liveViewport":world_texture!=null}
		_stage_art_signature = ""
		return
	# The deployed map omits legacy photo resources. Resolve exactly the same
	# manifest-backed artwork as the physical battlefield, including its hash
	# and source-geometry checks; never substitute an unrelated/raw preview.
	var manifest_signature: String = str(FileAccess.get_modified_time(RenderedArt.MANIFEST_PATH))+":"+str(FileAccess.get_file_as_string(RenderedArt.MANIFEST_PATH).sha256_text())
	var signature: String = JSON.stringify(stage).sha256_text()+":"+manifest_signature
	if signature == _stage_art_signature: return
	_stage_art_signature = signature
	stage_texture = null
	stage_art = {}
	if stage.is_empty(): return
	var source_geometry = Battlefield.new()
	var physical_fingerprint: String = JSON.stringify(source_geometry._physical_contract(stage)).sha256_text()
	source_geometry.free()
	stage_art = RenderedArt.resolve(stage,physical_fingerprint)
	stage_art["physicalGeometryFingerprint"] = physical_fingerprint
	var path: String = str(stage_art.get("artPath",""))
	if str(stage_art.get("mode","")) == "rendered" and bool(stage_art.get("sourceDataVerified",false)):
		stage_texture = BattlefieldMaterials.rendered_art_texture(path,str(stage_art.get("artSha256","")))

static func _picture(path: String) -> Texture2D:
	if _picture_cache.has(path): return _picture_cache[path]
	var result: Texture2D
	if ResourceLoader.exists(path,"Texture2D"): result=load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var source: Image=Image.load_from_file(path)
		if source!=null and not source.is_empty(): result=ImageTexture.create_from_image(source)
	if result!=null: _picture_cache[path]=result
	return result

func _target_crop(canonical: Vector2, target_id: String = "") -> Texture2D:
	for target in mission.get("targets",[]):
		if str(target.get("id",""))!=target_id: continue
		if bool(target.get("displayOnlyTerrain",false)):
			var reference_path: String=str(target.get("displayImagePath",""))
			if reference_path.is_empty() and str(target.get("terrainKind",""))=="mountain": reference_path=MOUNTAIN_REFERENCE
			return _picture(reference_path)
	if stage_texture == null: return null
	var source_size: Vector2 = stage_texture.get_size()
	if source_size.x<=0 or source_size.y<=0: return null
	var crop_size: Vector2 = source_size*Vector2(.34,.42)
	if bool(_background_stage.get("paintedPresentation",false)):
		crop_size=source_size*Vector2(.18,.31)
	var texture_anchor: Vector2 = canonical
	if world_projection.is_valid():
		# Authored landmarks need a local view; a wide crop can show the same
		# nearby camp for both the woodland and the stream-bank choices.
		crop_size = source_size*Vector2(.18,.24)
		# Camera projection is already mirrored for display; the texture is raw.
		texture_anchor = Presentation.to_model(_target_view_point(canonical),presentation_mirrored)
		# The crop may focus on an authored canopy or bank above/beyond the
		# ground marker. It never changes picking, answers or support origins.
		var cue: Dictionary = _background_stage.get("visualComposition",{}).get("contextAnchors",{}).get(target_id,{})
		var focus: Variant = cue.get("displayFocusWorld",[])
		if world_focus_projection.is_valid() and focus is Array and focus.size()==3:
			var focus_point := Vector3(float(focus[0]),float(focus[1]),float(focus[2]))
			if focus_point.is_finite():
				var projected: Vector2 = world_focus_projection.call(focus_point)
				if projected.is_finite(): texture_anchor = Presentation.to_model(projected,presentation_mirrored)
		var scale_value: Variant = cue.get("displayCropSizeNormalized",[])
		if scale_value is Array and scale_value.size()==2:
			var crop_scale := Vector2(float(scale_value[0]),float(scale_value[1]))
			if crop_scale.is_finite() and crop_scale.x>0 and crop_scale.y>0 and crop_scale.x<=1 and crop_scale.y<=1:
				crop_size = source_size*crop_scale
	if not texture_anchor.is_finite(): return null
	var center: Vector2 = texture_anchor*source_size
	var crop = AtlasTexture.new()
	crop.atlas = stage_texture
	crop.region = Rect2(Vector2(clampf(center.x-crop_size.x*.5,0,source_size.x-crop_size.x),clampf(center.y-crop_size.y*.5,0,source_size.y-crop_size.y)),crop_size)
	return crop

func view_point(canonical: Vector2) -> Vector2:
	return Presentation.to_view(canonical,presentation_mirrored)

func model_point(displayed: Vector2) -> Vector2:
	return Presentation.to_model(displayed,presentation_mirrored)

func background_draw_rect() -> Rect2:
	return Rect2(Vector2(size.x,0),Vector2(-size.x,size.y)) if presentation_mirrored else Rect2(Vector2.ZERO,size)

func _panel(textured: bool = true) -> Panel:
	var node = Panel.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("panel",UIStyle.frame(UIStyle.SURFACE,UIStyle.LINE))
	add_child(node)
	if textured: UIStyle.texture_layer(node,"lacquer",.70)
	return node

func _label(parent: Control, value: String, point_size: int, color: Color) -> Label:
	var node = UIStyle.TooltipLabel.new()
	node.text = value
	node.add_theme_font_override("font",GameFonts.body())
	node.add_theme_font_size_override("font_size",point_size)
	node.add_theme_color_override("font_color",color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _button(parent: Control, value: String, callback: Callable) -> Button:
	var node = UIStyle.TooltipButton.new()
	node.text = value
	node.add_theme_font_override("font",GameFonts.body())
	node.add_theme_font_size_override("font_size",20)
	for state_name in ["normal","hover","pressed","disabled","focus"]:
		node.add_theme_stylebox_override(state_name,UIStyle.textured_button(state_name))
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

func clear() -> void:
	mission.clear()
	choosing = false
	resolved = false
	hinted = false
	interaction_enabled = true
	report_clock = 0
	correct_target = ""
	question_item = {}
	reveal_item = {}
	_remove_targets()
	if report_card != null:
		report_card.hide()
		question_sheet.hide()
		action_card.hide()
		feedback.text=""
		feedback.tooltip_text=""
	if live_panel!=null: live_panel.hide()
	live_panel_rect=Rect2()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _remove_targets() -> void:
	for button in target_buttons:
		remove_child(button)
		button.queue_free()
	target_buttons.clear()
	target_anchors.clear()

func show_report(value: Dictionary, voice_available: bool) -> void:
	mission = value.duplicate(true)
	_sync_presentation(mission)
	question_item = {}
	reveal_item = mission.get("report",{}).duplicate(true)
	choosing = false
	resolved = false
	hinted = false
	report_clock = clampf(float(str(mission.get("report",{}).get("reading","")).length())/4.0+4.0,18.0,32.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	report_heading.set_word({"jp":"伝令","reading":"でんれい","ko":"전령 보고"},20,true)
	task_caption.hide()
	question_sheet.hide()
	report_heading.outline_size = 2
	report_card.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	report_text.outline_size = 4
	report_text.ink = Color("fff9ec")
	report_text.reading_ink = Color("fff9ec")
	report_text.meaning_ink = Color("fff3c7")
	report_text.reading_group_palette[0]=Color("ffe6a3")
	report_text.reading_group_palette[1]=Color("9fe7ff")
	report_text.meaning_size = 18
	report_text.min_reading_size = 12
	report_text.set_word(mission.get("report",{}),20,true)
	report_card.show()
	action_card.hide()
	listen_button.disabled = not voice_available
	_remove_targets()
	_arrange()
	show()

func begin_choice(value: Dictionary, can_listen: bool) -> void:
	mission = value.duplicate(true)
	_sync_presentation(mission)
	reveal_item = mission.get("revealItem",mission.get("report",{})).duplicate(true)
	question_item = mission.get("questionItem",{}).duplicate(true)
	if question_item.is_empty():
		for target in mission.get("targets",[]):
			if str(target.get("id",""))!=str(mission.get("answerId","")): continue
			var answer_word: Dictionary = target.get("label",{}).duplicate(true)
			if reveal_item.get("targetSpan") is Dictionary:
				answer_word["id"] = str(reveal_item.targetSpan.get("wordId",""))
			var blank: Dictionary = Cloze.build(reveal_item,answer_word)
			if bool(blank.valid): question_item = blank.questionItem
			break
	choice_voice_available = can_listen
	interaction_enabled = true
	choosing = true
	resolved = false
	hinted = false
	report_clock = 0
	correct_target = str(mission.get("answerId",""))
	mouse_filter = Control.MOUSE_FILTER_IGNORE if live_battle else Control.MOUSE_FILTER_STOP
	report_heading.set_word(mission.get("heading",{"jp":"援軍の要請","reading":"えんぐんのようせい","ko":"원군 요청"}),22,true)
	task_caption.text=str(mission.get("captionKo","요청의 뜻에 맞는 일본어를 선택하십시오."))
	task_caption.show()
	question_sheet.show()
	report_heading.outline_size = 0
	report_card.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	report_text.outline_size = 0
	report_text.ink = Color("282119")
	report_text.reading_ink = Color("51402b")
	report_text.meaning_ink = Color("59432b")
	report_text.reading_group_palette[0] = Color("795424")
	report_text.reading_group_palette[1] = Color("285f74")
	report_text.meaning_size = 20
	report_text.min_reading_size = 22
	report_text.set_word(question_item,36,true)
	report_card.show()
	action_card.show()
	# Give wrapped text its real width before the first long instruction;
	# otherwise Label can retain the height measured at its initial zero width.
	feedback.size = Vector2(maxf(100,size.x-60),60)
	_set_feedback_text("정답이면 전장 지원을 무작위로 받습니다." if live_battle else "요청에 맞는 목적지를 선택하면 전장에 맞는 지원을 무작위로 받습니다.")
	feedback.add_theme_color_override("font_color",Color(UIStyle.TEXT))
	hint_button.disabled = false
	listen_button.disabled = not can_listen
	listen_button.tooltip_text = "일본어 보고를 다시 듣습니다." if can_listen else "이 PC에는 일본어 읽기 음성이 없습니다. 글자로 확인하십시오."
	continue_button.text = "건너뛰기" if live_battle else "건너뛰고 전투 복귀"
	_build_targets(true)
	_arrange()
	show()
	if not live_battle and not target_buttons.is_empty():
		target_buttons[0].grab_focus()

func _build_targets(interactive: bool) -> void:
	_remove_targets()
	var index: int = 0
	for target in mission.get("targets",[]):
		var button = _button(self,"",_choose.bind(str(target.get("id",""))))
		button.name = "LearningTarget_%s" % str(target.get("id",""))
		button.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
		var label_word: Dictionary = mission.get("choiceItems",{}).get(str(target.get("id","")),target.get("label",{}))
		if interactive:
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.clip_contents = true
			var picture = TextureRect.new()
			picture.name = "DestinationImage"
			picture.flip_h = presentation_mirrored
			picture.visible=bool(target.get("showImage",true))
			if picture.visible: picture.texture = _target_crop(Presentation.point(target.get("position",{})),str(target.get("id","")))
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(picture)
			var number = _label(button,"%d" % (index+1),22,Color(UIStyle.BRASS))
			number.name = "ChoiceNumber"
			number.add_theme_constant_override("outline_size",3)
			number.add_theme_color_override("font_outline_color",Color(UIStyle.INK))
			var ko = _label(button,str(label_word.get("ko","")),20,Color(UIStyle.TEXT))
			ko.name = "DestinationName"
			ko.hide()
			ko.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ko.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var choice_word = RubyText.new()
			choice_word.name = "DestinationWord"
			choice_word.font = GameFonts.japanese()
			choice_word.reading_font = GameFonts.reading()
			choice_word.meaning_font = GameFonts.body()
			choice_word.ink = Color(UIStyle.TEXT)
			choice_word.reading_ink = Color(UIStyle.MUTED)
			choice_word.meaning_ink = Color(UIStyle.TEXT)
			choice_word.meaning_size = 20
			choice_word.min_reading_size=16
			choice_word.colour_reading_groups=true
			choice_word.wrap_japanese = true
			choice_word.set_word(label_word,48,true)
			button.add_child(choice_word)
			var caption_text: String="지형 참고 그림" if bool(target.get("displayOnlyTerrain",false)) else "현재 전장의 지형"
			if not bool(target.get("showImage",true)): caption_text="단어 선택"
			var caption = _label(button,caption_text,18,Color(UIStyle.MUTED))
			caption.name = "DestinationAction"
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			var label = RubyText.new()
			label.font = GameFonts.japanese()
			label.reading_font = GameFonts.reading()
			label.meaning_font = GameFonts.body()
			label.meaning_size = 18
			label.set_word(label_word,25,true)
			label.position = Vector2(6,0)
			label.size = Vector2(150,82)
			button.add_child(label)
		button.tooltip_text = "" if interactive else str(label_word.get("ko",""))
		target_buttons.append(button)
		target_anchors.append(_target_view_point(Presentation.point(target.get("position",{}))))
		index += 1

func _choose(target_id: String) -> void:
	if not choosing or resolved or not interaction_enabled:
		return
	target_chosen.emit(target_id)

func _set_feedback_text(value: String) -> void:
	var context: Array=[reveal_item,question_item,mission.get("report",{})]
	for target in mission.get("targets",[]): context.append(target.get("label",{}))
	for item in mission.get("choiceItems",{}).values(): context.append(item)
	feedback.set("ruby_context_words",context)
	feedback.text=value
	feedback.call("refresh_ruby")

func show_hint() -> void:
	if not choosing or resolved:
		return
	hinted = true
	report_text.set_word(reveal_item,36,true)
	hint_button.disabled = true
	_set_feedback_text("원문을 확인했습니다. 정답이면 약한 전장 지원을 받습니다.\n다음에 혼자 답하면 기억 확인에 반영됩니다.")
	_arrange()

func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	for button in target_buttons:
		button.disabled = not enabled or resolved
	hint_button.disabled = not enabled or hinted or resolved
	listen_button.disabled = not enabled or not choice_voice_available
	continue_button.disabled = not enabled

func show_result(correct: bool, value: String, selected_id: String = "") -> void:
	resolved = true
	report_text.set_word(reveal_item,36,true)
	_set_feedback_text(value)
	feedback.add_theme_color_override("font_color",Color("a9d4ca") if correct else Color("dfb5a4"))
	hint_button.disabled = true
	continue_button.text = "확인  ›" if live_battle else "전투로 복귀  ›"
	for index in range(target_buttons.size()):
		var button: Button = target_buttons[index]
		button.disabled = true
		if str(mission.targets[index].id) == correct_target:
			button.add_theme_stylebox_override("disabled",UIStyle.textured_panel("lacquer",Color("9dc5b0")))
			button.get_node("DestinationAction").text = "요청한 목적지" if bool(mission.targets[index].get("showImage",true)) else "정답"
			button.get_node("DestinationAction").add_theme_color_override("font_color",Color("c5e6c6"))
		elif str(mission.targets[index].id) == selected_id:
			button.add_theme_stylebox_override("disabled",UIStyle.textured_panel("lacquer",Color("c98d78")))
			button.get_node("DestinationAction").text = "선택한 목적지" if bool(mission.targets[index].get("showImage",true)) else "선택한 답"
			button.get_node("DestinationAction").add_theme_color_override("font_color",Color("efbfaa"))
		else:
			button.modulate = Color(.70,.65,.56,.80)
	_arrange()
	queue_redraw()

func suspend_choice() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _arrange_live_battle() -> void:
	# Main supplies the free battlefield rectangle above its toolbar. The root
	# remains transparent to input; only this panel and its controls stop it.
	var safe: Rect2=Rect2(Vector2.ZERO,size)
	if live_battle_bounds.has_area(): safe=safe.intersection(live_battle_bounds)
	if not safe.has_area():
		live_panel_rect=Rect2()
		_live_layout_overflow=true
		return
	var panel_width: float=minf(520,safe.size.x)
	var inner_width: float=maxf(1,panel_width-20)
	var count: int=maxi(1,target_buttons.size())
	var card_width: float=maxf(1,(inner_width-8*(count-1))/count)
	var limit_height: float=minf(450,safe.size.y)
	var heading_height: float=0
	var question_height: float=0
	var card_height: float=0
	var image_height: float=0
	var feedback_height: float=0
	var button_height: float=0
	var panel_height: float=0
	announcement_anchor.hide()
	report_heading.meaning_size=12
	report_heading.min_reading_size=11
	report_heading.size.x=minf(174,inner_width*.44)
	report_heading.set_word(mission.get("heading",{"jp":"援軍の要請","reading":"えんぐんのようせい","ko":"원군 요청"}),17,true)
	report_heading._sync_minimum_height()
	report_heading.size.y=report_heading.custom_minimum_size.y
	task_caption.add_theme_font_size_override("font_size",13)
	task_caption.size.x=maxf(1,inner_width-report_heading.size.x-8)
	task_caption.size.y=task_caption.get_minimum_size().y
	heading_height=maxf(report_heading.size.y,task_caption.size.y)
	# Measure the real JP/ruby/Korean blocks, including hint/result text. A
	# denser tier reduces only typography and thumbnail height, never content.
	for density in range(4):
		report_text.meaning_size=15 if density<2 else 14
		report_text.min_reading_size=12 if density<2 else 11
		report_text.group_spacing=3.0
		report_text.size.x=maxf(1,inner_width-12)
		report_text.set_word(reveal_item if hinted or resolved else question_item,23-density*2,true)
		report_text._sync_minimum_height()
		report_text.size.y=report_text.custom_minimum_size.y
		question_height=report_text.size.y+8
		image_height=48-density*6
		card_height=0
		for button in target_buttons:
			var choice_word: Control=button.get_node("DestinationWord")
			choice_word.custom_minimum_size.x=1
			choice_word.size.x=maxf(1,card_width-12)
			choice_word.meaning_size=14 if density<2 else 13
			choice_word.min_reading_size=11
			choice_word.group_spacing=2.0
			choice_word.set_word(choice_word.word,23-density,true)
			choice_word._sync_minimum_height()
			choice_word.size.y=choice_word.custom_minimum_size.y
			var caption: Label=button.get_node("DestinationAction")
			caption.add_theme_font_size_override("font_size",11)
			caption.size.x=maxf(1,card_width-12)
			caption.size.y=maxf(16,caption.get_minimum_size().y)
			var picture_height: float=image_height if button.get_node("DestinationImage").visible else 22.0
			card_height=maxf(card_height,picture_height+choice_word.size.y+caption.size.y+12)
		feedback.add_theme_font_size_override("font_size",14 if density<2 else 13)
		feedback.size.x=inner_width
		feedback.call("refresh_ruby")
		feedback_height=maxf(20,feedback.get_combined_minimum_size().y)
		button_height=32
		for button in [hint_button,listen_button,continue_button]:
			button_height=maxf(button_height,button.get_combined_minimum_size().y)
		panel_height=20+heading_height+6+question_height+8+card_height+8+feedback_height+6+button_height
		if panel_height<=limit_height: break
	# Keep all measured content instead of clipping a long localized result.
	# A host with insufficient free space can inspect this flag and enlarge it.
	_live_layout_overflow=panel_height>limit_height
	live_panel_rect=Rect2(Vector2(safe.end.x-panel_width,maxf(safe.position.y,safe.end.y-panel_height)),Vector2(panel_width,panel_height))
	live_panel.position=live_panel_rect.position
	live_panel.size=live_panel_rect.size
	report_card.position=live_panel_rect.position+Vector2(10,10)
	report_heading.position=Vector2.ZERO
	task_caption.position=Vector2(report_heading.size.x+8,maxf(0,(heading_height-task_caption.size.y)*.5))
	question_sheet.position=Vector2(0,heading_height+6)
	question_sheet.size=Vector2(inner_width,question_height)
	report_text.position=question_sheet.position+Vector2(6,4)
	report_card.size=Vector2(inner_width,question_sheet.position.y+question_height)
	var cards_y: float=report_card.position.y+report_card.size.y+8
	for index in range(target_buttons.size()):
		var button: Button=target_buttons[index]
		button.position=Vector2(report_card.position.x+(card_width+8)*index,cards_y)
		button.size=Vector2(card_width,card_height)
		var picture: TextureRect=button.get_node("DestinationImage")
		picture.position=Vector2.ONE
		picture.size=Vector2(maxf(1,card_width-2),image_height)
		var number: Label=button.get_node("ChoiceNumber")
		number.add_theme_font_size_override("font_size",15)
		number.position=Vector2(6,3)
		number.size=Vector2(24,22)
		var choice_word: Control=button.get_node("DestinationWord")
		choice_word.position=Vector2(6,(image_height if picture.visible else 22.0)+4)
		var caption: Label=button.get_node("DestinationAction")
		caption.position=Vector2(6,card_height-caption.size.y-4)
	action_card.position=Vector2(report_card.position.x,cards_y+card_height+8)
	action_card.size=Vector2(inner_width,feedback_height+6+button_height)
	feedback.position=Vector2.ZERO
	feedback.size=Vector2(inner_width,feedback_height)
	var buttons: Array=[hint_button,listen_button,continue_button]
	var action_width: float=(inner_width-16)/3.0
	for index in range(buttons.size()):
		buttons[index].position=Vector2((action_width+8)*index,feedback_height+6)
		buttons[index].size=Vector2(action_width,button_height)
	queue_redraw()

func _arrange() -> void:
	if report_card == null or size.x < 10:
		return
	live_panel.visible=live_battle and choosing
	if live_battle and choosing:
		_arrange_live_battle()
		return
	live_panel_rect=Rect2()
	if not choosing:
		announcement_anchor.hide()
		var banner_width: float = minf(340,size.x-24)
		report_card.position = Vector2(12,12)
		report_heading.position = Vector2(12,5)
		report_heading.size = Vector2(banner_width-24,30)
		report_heading._sync_minimum_height()
		report_heading.size.y = maxf(30,report_heading.get_combined_minimum_size().y)
		report_text.position = Vector2(12,report_heading.position.y+report_heading.size.y+8)
		report_text.size.x = banner_width-24
		var face: Font = GameFonts.japanese()
		var span: float = face.get_string_size(str(mission.get("report",{}).get("jp","")),HORIZONTAL_ALIGNMENT_LEFT,-1,20).x
		var point_size: int = 20 if span<=banner_width-32 else 18
		if report_text.base_size!=point_size:
			report_text.set_word(mission.get("report",{}),point_size,true)
		report_text._sync_minimum_height()
		report_text.size.y = report_text.custom_minimum_size.y
		report_card.size = Vector2(banner_width,report_text.position.y+report_text.size.y+6)
		queue_redraw()
		return
	var content_width: float = minf(1184,size.x-96)
	var content_x: float = (size.x-content_width)*.5
	report_card.position = Vector2(content_x,36)
	report_heading.position = Vector2(0,0)
	var announcement_width: float = minf(420,content_width*.4)
	var heading_width: float = content_width-announcement_width-24
	announcement_anchor.position = Vector2(content_width-announcement_width,0)
	announcement_anchor.size = Vector2(announcement_width,112)
	announcement_anchor.show()
	report_heading.size = Vector2(heading_width,32)
	report_heading._sync_minimum_height()
	report_heading.size.y = maxf(32,report_heading.get_combined_minimum_size().y)
	task_caption.position = Vector2(0,report_heading.size.y+8)
	task_caption.size.x = heading_width
	task_caption.size.y = maxf(32,task_caption.get_minimum_size().y)
	report_text.position = Vector2(0,maxf(124,task_caption.position.y+task_caption.size.y+18))
	report_text.size.x = content_width
	if report_text.base_size!=36:
		report_text.set_word(reveal_item if hinted or resolved else question_item,36,true)
	report_text._sync_minimum_height()
	report_text.size.y = report_text.custom_minimum_size.y
	question_sheet.position = report_text.position-Vector2(18,12)
	question_sheet.size = report_text.size+Vector2(36,24)
	report_card.size = Vector2(content_width,report_text.position.y+report_text.custom_minimum_size.y+6)
	action_card.size.x=content_width
	var footer_content: Rect2=UIStyle.content_rect(action_card)
	feedback.position = footer_content.position
	feedback.size.x = footer_content.size.x
	feedback.call("refresh_ruby")
	var feedback_height: float = maxf(54,feedback.get_combined_minimum_size().y)
	feedback.size.y = feedback_height
	var button_y: float = feedback.position.y+feedback_height+8
	var button_height: float=maxf(48,maxf(hint_button.get_combined_minimum_size().y,maxf(listen_button.get_combined_minimum_size().y,continue_button.get_combined_minimum_size().y)))
	var footer_style: StyleBox=action_card.get_theme_stylebox("panel")
	var footer_height: float = button_y+button_height+footer_style.get_margin(SIDE_BOTTOM)
	action_card.position = Vector2(content_x,size.y-footer_height-28)
	action_card.size = Vector2(content_width,footer_height)
	var available: float = (footer_content.size.x-24)/3.0
	hint_button.position = Vector2(footer_content.position.x,button_y)
	hint_button.size = Vector2(available,button_height)
	listen_button.position = Vector2(footer_content.position.x+12+available,button_y)
	listen_button.size = Vector2(available,button_height)
	continue_button.position = Vector2(footer_content.position.x+24+available*2,button_y)
	continue_button.size = Vector2(available,button_height)
	var count: int = maxi(1,target_buttons.size())
	var gap: float = 20
	var card_width: float = (content_width-gap*(count-1))/count
	var top: float = report_card.position.y+report_card.size.y+24
	var bottom: float = action_card.position.y-24
	var card_height: float = minf(365,bottom-top)
	var card_y: float = top+(bottom-top-card_height)*.5
	for index in range(target_buttons.size()):
		var button: Button = target_buttons[index]
		button.position = Vector2(content_x+(card_width+gap)*index,card_y)
		button.size = Vector2(card_width,card_height)
		var choice_word: Control = button.get_node("DestinationWord")
		choice_word.size.x = card_width-28
		var label_word: Dictionary=choice_word.word
		var points: int=48
		while points>30:
			choice_word.set_word(label_word,points,true)
			choice_word._sync_minimum_height()
			var jp_width: float=GameFonts.japanese().get_string_size(str(label_word.get("jp","")),HORIZONTAL_ALIGNMENT_LEFT,-1,points).x
			if choice_word.custom_minimum_size.y<=card_height*.56 and jp_width<=card_width-32: break
			points-=2
		choice_word.set_word(label_word,points,true)
		choice_word._sync_minimum_height()
		choice_word.size.y = choice_word.custom_minimum_size.y
		var image_height: float = maxf(24,card_height-choice_word.size.y-56)
		var image: TextureRect = button.get_node("DestinationImage")
		image.position = Vector2(1,1)
		image.size = Vector2(card_width-2,image_height)
		var number: Label = button.get_node("ChoiceNumber")
		number.position = Vector2(14,10)
		number.size = Vector2(36,30)
		var title: Label = button.get_node("DestinationName")
		title.position = Vector2(14,image_height+15)
		title.size = Vector2(card_width-28,52)
		choice_word.position = Vector2(14,image_height+8)
		var caption: Label = button.get_node("DestinationAction")
		caption.position = Vector2(14,card_height-40)
		caption.size = Vector2(card_width-28,28)
	queue_redraw()

func _process(delta: float) -> void:
	if report_clock > 0 and is_visible_in_tree() and not flow_paused:
		report_clock -= delta
		if report_clock <= 0 and not choosing:
			report_card.hide()
			_remove_targets()
			queue_redraw()

func _draw() -> void:
	if live_battle or not visible or mission.is_empty() or not choosing:
		return
	draw_rect(Rect2(Vector2.ZERO,size),Color(UIStyle.INK))
	if stage_texture != null:
		draw_texture_rect(stage_texture,background_draw_rect(),false,Color(.52,.48,.40,1))
	else:
		draw_style_box(UIStyle.textured_panel("lacquer"),Rect2(Vector2.ZERO,size))
	draw_rect(Rect2(Vector2.ZERO,size),Color(.07,.05,.025,.25))
