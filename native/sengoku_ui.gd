extends Control

const RubyText = preload("res://native/ruby_label.gd")
const RubyReadings = preload("res://native/ruby_readings.gd")

# Native Label/Button contracts remain intact. The annotated child renders the
# complete original body and readings; coverage is checked on its actual runs.
class TooltipLabel extends Label:
	var ruby_context_words: Array=[]:
		set(value):
			ruby_context_words=value
			_signature=""
			queue_redraw()
			if is_node_ready(): refresh_ruby()
	var ruby_text: Control
	var _signature: String=""
	var _native_modulate: Color=Color.WHITE
	var _ruby_minimum: float=0.0
	var _minimum_before_ruby: float=0.0
	var _syncing: bool=false
	func _ready() -> void:
		_native_modulate=self_modulate
		resized.connect(refresh_ruby)
		minimum_size_changed.connect(refresh_ruby)
		refresh_ruby()
	func _draw() -> void:
		refresh_ruby()
	func _make_custom_tooltip(for_text: String) -> Object:
		var value: String=for_text if not for_text.strip_edges().is_empty() else tooltip_text
		if value.strip_edges().is_empty() and clip_text: value=text
		return RubyText.make_tooltip(value,ruby_context_words)
	func refresh_ruby() -> void:
		if _syncing or not is_inside_tree(): return
		_syncing=true
		if not RubyReadings.contains_kanji(text):
			self_modulate=_native_modulate
			if is_instance_valid(ruby_text): ruby_text.hide()
			if is_equal_approx(custom_minimum_size.y,_ruby_minimum): custom_minimum_size.y=_minimum_before_ruby
			_signature=""
			_syncing=false
			return
		var points: int=get_theme_font_size("font_size")
		var ink: Color=get_theme_color("font_color")
		var content: Rect2=load("res://native/sengoku_ui.gd").content_rect(self,"normal")
		if content.size.x<=1:
			_syncing=false
			return
		var signature: String=str([text,size,content,points,ink,horizontal_alignment,vertical_alignment,autowrap_mode,get_theme_font("font").get_instance_id(),get_theme_constant("outline_size"),get_theme_color("font_outline_color"),ruby_context_words])
		if signature==_signature and is_instance_valid(ruby_text): _syncing=false; return
		_signature=signature
		if not is_instance_valid(ruby_text):
			ruby_text=RubyText.new()
			ruby_text.name="VisibleAnnotatedText"
			ruby_text.custom_minimum_size.x=1
			add_child(ruby_text)
		ruby_text.show()
		ruby_text.font=get_theme_font("font")
		ruby_text.ink=ink
		ruby_text.reading_ink=ink
		ruby_text.colour_reading_groups=true
		var dark_ink: bool=ink.r*.2126+ink.g*.7152+ink.b*.0722<.45
		ruby_text.reading_group_palette[0]=Color("795424") if dark_ink else Color("f5d58a")
		ruby_text.reading_group_palette[1]=Color("285f74") if dark_ink else Color("a3dafa")
		ruby_text.wrap_japanese=autowrap_mode!=TextServer.AUTOWRAP_OFF
		ruby_text.horizontal_alignment=horizontal_alignment
		ruby_text.outline_size=mini(2,get_theme_constant("outline_size"))
		ruby_text.outline_ink=get_theme_color("font_outline_color")
		ruby_text.size.x=content.size.x
		ruby_text.set_text(text,points,ruby_context_words)
		var height: float=float(ruby_text.get_text_layout().height)
		ruby_text.size.y=height
		if not is_equal_approx(custom_minimum_size.y,_ruby_minimum): _minimum_before_ruby=custom_minimum_size.y
		_ruby_minimum=maxf(_minimum_before_ruby,height+size.y-content.size.y)
		custom_minimum_size.y=_ruby_minimum
		ruby_text.position=content.position+Vector2(0,maxf(0,content.size.y-height)*(.5 if vertical_alignment==VERTICAL_ALIGNMENT_CENTER else 1.0 if vertical_alignment==VERTICAL_ALIGNMENT_BOTTOM else 0.0))
		# Only the duplicate native glyphs are replaced; child body remains visible.
		self_modulate=Color(_native_modulate,0)
		_syncing=false

class TooltipButton extends Button:
	var ruby_context_words: Array=[]:
		set(value):
			ruby_context_words=value
			_signature=""
			queue_redraw()
			if is_node_ready(): refresh_ruby()
	var ruby_text: Control
	var _signature: String=""
	var _colours: Dictionary={}
	var _syncing: bool=false
	var _minimum_before_ruby: float=0.0
	var _ruby_minimum: float=0.0
	const MASKED_COLOURS: Array[String]=["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_disabled_color","font_focus_color","font_outline_color"]
	func _ready() -> void:
		resized.connect(refresh_ruby)
		minimum_size_changed.connect(refresh_ruby)
		refresh_ruby()
	func _draw() -> void:
		refresh_ruby()
	func _make_custom_tooltip(for_text: String) -> Object:
		var value: String=for_text if not for_text.strip_edges().is_empty() else tooltip_text
		if value.strip_edges().is_empty() and clip_text: value=text
		return RubyText.make_tooltip(value,ruby_context_words)
	func refresh_ruby() -> void:
		if _syncing or not is_inside_tree(): return
		_syncing=true
		if not RubyReadings.contains_kanji(text):
			if is_instance_valid(ruby_text): ruby_text.hide()
			for key in _colours:
				if get_theme_color(key).a==0: add_theme_color_override(key,_colours[key])
			_colours.clear()
			if is_equal_approx(custom_minimum_size.y,_ruby_minimum): custom_minimum_size.y=_minimum_before_ruby
			_signature=""
			_syncing=false
			return
		begin_bulk_theme_override()
		for key in MASKED_COLOURS:
			var current: Color=get_theme_color(key)
			if current.a>0 or not _colours.has(key): _colours[key]=current
			if current.a>0: add_theme_color_override(key,Color(current,0))
		end_bulk_theme_override()
		var colour_key: String="font_disabled_color" if disabled else "font_hover_pressed_color" if is_pressed() and is_hovered() else "font_pressed_color" if is_pressed() else "font_hover_color" if is_hovered() else "font_color"
		var ink: Color=_colours.get(colour_key,Color(TEXT))
		var points: int=get_theme_font_size("font_size")
		var content: Rect2=load("res://native/sengoku_ui.gd").content_rect(self,"normal")
		if content.size.x<=1:
			_syncing=false
			return
		var signature: String=str([text,size,content,points,ink,alignment,get_theme_font("font").get_instance_id(),get_theme_constant("outline_size"),_colours.get("font_outline_color",Color.BLACK),ruby_context_words])
		if signature!=_signature or not is_instance_valid(ruby_text):
			_signature=signature
			if not is_instance_valid(ruby_text):
				ruby_text=RubyText.new()
				ruby_text.name="VisibleAnnotatedText"
				ruby_text.custom_minimum_size.x=1
				add_child(ruby_text)
			ruby_text.show()
			ruby_text.font=get_theme_font("font")
			ruby_text.ink=ink
			ruby_text.reading_ink=ink
			ruby_text.outline_size=mini(2,get_theme_constant("outline_size"))
			ruby_text.outline_ink=_colours.get("font_outline_color",Color.BLACK)
			ruby_text.colour_reading_groups=true
			var dark_ink: bool=ink.r*.2126+ink.g*.7152+ink.b*.0722<.45
			ruby_text.reading_group_palette[0]=Color("795424") if dark_ink else Color("f5d58a")
			ruby_text.reading_group_palette[1]=Color("285f74") if dark_ink else Color("a3dafa")
			ruby_text.horizontal_alignment=alignment
			ruby_text.wrap_japanese=true
			ruby_text.size.x=content.size.x
			ruby_text.set_text(text,points,ruby_context_words)
			var height: float=float(ruby_text.get_text_layout().height)
			ruby_text.size.y=height
			if not is_equal_approx(custom_minimum_size.y,_ruby_minimum): _minimum_before_ruby=custom_minimum_size.y
			_ruby_minimum=maxf(_minimum_before_ruby,height+size.y-content.size.y)
			custom_minimum_size.y=_ruby_minimum
			ruby_text.position=content.position+Vector2(0,maxf(0,content.size.y-height)*.5)
		_syncing=false

# Shared materials: charcoal lacquer, dull metal edges and warm ivory text.
const INK = "141819"
const SURFACE = "1d2223f5"
const RAISED = "2a3132f5"
const LINE = "67614f"
const BRASS = "bda978"
const TEXT = "eee8d9"
const MUTED = "b8b7aa"
const BLUE = "79b3d4"
const DISABLED = "777f80"
const WARNING = "d4b579"
const DANGER = "d68f7d"
const MATERIAL_PATHS: Dictionary = {
	"lacquer":"res://assets/ui/lacquer-panel.png",
	"wood":"res://assets/ui/lacquer-panel.png",
	"paper":"res://assets/ui/washi-paper.png"
}
static var _material_textures: Dictionary = {}
static var _floating_style: StyleBox

class DetailReader extends Control:
	var heading: String=""
	var sections: Array=[]
	var section_index: int=0
	var page_index: int=0
	var _layout_queued: bool=false
	func _ready() -> void:
		mouse_filter=Control.MOUSE_FILTER_STOP
		z_index=200
		resized.connect(_queue_layout)
		_queue_layout()
	func _queue_layout() -> void:
		if _layout_queued: return
		_layout_queued=true
		call_deferred("_build")
	func close() -> void:
		if get_parent()!=null: get_parent().remove_child(self)
		queue_free()
	func _choose_section(index: int) -> void:
		section_index=index
		page_index=0
		_queue_layout()
	func _choose_page(index: int) -> void:
		page_index=index
		_queue_layout()
	func _action(parent: Control, caption: String, rect: Rect2, action: Callable) -> Button:
		var style: Script=load("res://native/sengoku_ui.gd")
		var button: Button=Button.new()
		button.text=caption
		button.position=rect.position
		button.size=rect.size
		button.add_theme_font_override("font",load("res://native/game_fonts.gd").body())
		button.add_theme_font_size_override("font_size",20)
		for state_name in ["normal","hover","pressed","disabled","focus"]:
			button.add_theme_stylebox_override(state_name,style.textured_button(state_name))
		button.pressed.connect(action)
		parent.add_child(button)
		return button
	func _build() -> void:
		_layout_queued=false
		if not is_inside_tree() or size.x<500 or size.y<400 or sections.is_empty(): return
		for child in get_children():
			remove_child(child)
			child.queue_free()
		var style: Script=load("res://native/sengoku_ui.gd")
		var shade: Panel=Panel.new()
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.add_theme_stylebox_override("panel",style.frame("171410d9","17141000"))
		shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
		add_child(shade)
		var paper: Panel=Panel.new()
		paper.name="DetailPaper"
		paper.position=Vector2(32,32)
		paper.size=size-Vector2(64,64)
		paper.add_theme_stylebox_override("panel",style.textured_panel("paper",Color("ebdfc8")))
		add_child(paper)
		var title: Control=RubyText.new()
		title.name="DetailTitle"
		title.size.x=paper.size.x-48
		title.position=Vector2(24,18)
		title.wrap_japanese=true
		title.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
		title.ink=Color("30251b")
		title.reading_ink=Color("65533e")
		title.set_text(heading,26)
		title.size.y=title.get_text_layout().height
		paper.add_child(title)
		var tabs_y: float=title.position.y+title.size.y+12
		var tab_width: float=(paper.size.x-48-10*(sections.size()-1))/sections.size()
		for index in range(sections.size()):
			var tab: Button=_action(paper,str(sections[index].get("title","상세")),Rect2(24+(tab_width+10)*index,tabs_y,tab_width,52),_choose_section.bind(index))
			tab.name="DetailSection_%d"%index
			if index==section_index: tab.add_theme_stylebox_override("normal",style.textured_button("normal",false,true))
		var body_y: float=tabs_y+68
		var footer_y: float=paper.size.y-70
		var body_size: Vector2=Vector2(paper.size.x-48,maxf(80,footer_y-body_y-16))
		section_index=clampi(section_index,0,sections.size()-1)
		var section: Dictionary=sections[section_index]
		var context: Array=section.get("context",[])
		var pages: Array=style.detail_pages(str(section.get("text","자료 준비 중입니다.")),body_size,context)
		page_index=clampi(page_index,0,pages.size()-1)
		var body: Control=RubyText.new()
		body.name="DetailBody"
		body.position=Vector2(24,body_y)
		body.size=body_size
		body.wrap_japanese=true
		body.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
		body.ink=Color("30251b")
		body.reading_ink=Color("65533e")
		body.reading_group_palette[0]=Color("795424")
		body.reading_group_palette[1]=Color("285f74")
		body.set_text(pages[page_index],22,context)
		paper.add_child(body)
		var previous: Button=_action(paper,"이전",Rect2(24,footer_y,132,52),_choose_page.bind(page_index-1))
		previous.name="DetailPrevious"
		previous.disabled=page_index==0
		var next: Button=_action(paper,"다음",Rect2(166,footer_y,132,52),_choose_page.bind(page_index+1))
		next.name="DetailNext"
		next.disabled=page_index>=pages.size()-1
		var counter: Label=Label.new()
		counter.text="%d / %d"%[page_index+1,pages.size()]
		counter.position=Vector2(316,footer_y+10)
		counter.size=Vector2(160,34)
		counter.add_theme_font_size_override("font_size",20)
		counter.add_theme_color_override("font_color",Color("30251b"))
		paper.add_child(counter)
		_action(paper,"돌아가기",Rect2(paper.size.x-204,footer_y,180,52),close).name="AtlasDetailsBack" if get_parent().name=="CampaignAtlas" else "CatalogDetailsBack"

static func detail_pages(value: String, area: Vector2, context: Array=[]) -> Array:
	var result: Array=[]
	var probe: Control=RubyText.new()
	probe.wrap_japanese=true
	probe.size.x=area.x
	var remaining: String=value
	while not remaining.is_empty():
		var low: int=1
		var high: int=remaining.length()
		var fit: int=1
		while low<=high:
			var middle: int=(low+high)/2
			probe.set_text(remaining.left(middle),22,context)
			if float(probe.get_text_layout().height)<=area.y:
				fit=middle
				low=middle+1
			else: high=middle-1
		var cut: int=fit
		if fit<remaining.length():
			var prefix: String=remaining.left(fit)
			var boundary: int=maxi(prefix.rfind("\n"),maxi(prefix.rfind("。"),prefix.rfind(" ")))
			if boundary>fit/2: cut=boundary+1
		result.append(remaining.left(cut))
		remaining=remaining.substr(cut)
	probe.free()
	if result.is_empty(): result.append("자료 준비 중입니다.")
	return result

static func open_detail(parent: Control, title: String, sections: Array) -> Control:
	var existing: Node=parent.get_node_or_null("InterfaceDetailReader")
	if existing!=null:
		parent.remove_child(existing)
		existing.queue_free()
	var reader: Control=DetailReader.new()
	reader.name="InterfaceDetailReader"
	reader.heading=title
	reader.sections=sections
	parent.add_child(reader)
	reader.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return reader

static func stage_detail_sections(stage: Dictionary, story: Dictionary, geo: Dictionary, plan: Dictionary={}) -> Array:
	var context: Array=[{"jp":geo.get("oldNameJP",""),"reading":geo.get("oldNameReading","")},{"jp":geo.get("modernNameJP",""),"reading":geo.get("modernNameReading","")},{"jp":story.get("briefingJP",""),"reading":story.get("briefingReading","")}]
	var history: String=str(story.get("historyNarrativeKo",story.get("historySummaryKo","")))
	history+="\n\n결과 · "+str(story.get("historyOutcomeKo",""))+"\n"+str(story.get("phaseKo",""))
	var location: String="당시 지명\n%s\n%s\n\n현재 지명\n%s\n%s"%[str(geo.get("oldNameJP","")),str(geo.get("oldNameKo","")),str(geo.get("modernNameJP","")),str(geo.get("modernNameKo",""))]
	var point: Dictionary=geo.get("phaseLocation",geo)
	location+="\n\n위도 %s° · 경도 %s°"%[str(point.get("lat",geo.get("lat",""))),str(point.get("lon",geo.get("lon","")))]
	for location_key in ["phaseLocation","stageMissionLocation"]:
		var detail=geo.get(location_key,{})
		if detail is Dictionary: location+="\n"+str(detail.get("reasonKo",detail.get("descriptionKo","")))
	for condition in ["season","weather","terrain"]:
		var value=geo.get(condition,"")
		location+="\n"+(str(value.get("labelKo",value.get("descriptionKo",value.get("nameKo",value.get("ko",""))))) if value is Dictionary else str(value))
	var combat: String=str(story.get("briefingJP",""))+"\n"+str(story.get("briefingKo",story.get("playerGoalKo","")))
	combat+="\n\n상대 · "+str(story.get("opponent",{}).get("nameKo",""))+"\n제작 근거 · "+str(geo.get("renderingBasisKo",""))
	var accuracy: Dictionary=geo.get("historicalAccuracyKnownVsGame",{})
	combat+="\n\n확인된 사실\n"+"\n".join(PackedStringArray(accuracy.get("knownKo",[])))
	combat+="\n\n게임 각색\n"+"\n".join(PackedStringArray(accuracy.get("gameAdaptationKo",[])))+"\n"+str(accuracy.get("limitsKo",""))
	return [{"title":"역사","text":history,"context":context},{"title":"지명·지형","text":location,"context":context},{"title":"전투·각색","text":combat,"context":context},{"title":"학습 목표","text":str(plan.get("goalKo","전장의 단어와 표현을 확인합니다.")),"context":context},{"title":"자료 출처","text":"\n\n".join(PackedStringArray(geo.get("sources",[]))),"context":context}]

# Panel is a drawing control: it does not inset manually positioned children.
# Button's built-in text respects its StyleBox; our annotated child must do so too.
static func content_rect(control: Control, style_name: String = "panel") -> Rect2:
	var insets: Vector4=Vector4.ZERO
	var styles: Array[String]=[]
	if control is Button:
		styles.assign(["normal","hover","pressed","hover_pressed","disabled","focus"])
	else:
		styles.append(style_name)
	for state in styles:
		var style: StyleBox=control.get_theme_stylebox(state)
		insets.x=maxf(insets.x,style.get_margin(SIDE_LEFT))
		insets.y=maxf(insets.y,style.get_margin(SIDE_TOP))
		insets.z=maxf(insets.z,style.get_margin(SIDE_RIGHT))
		insets.w=maxf(insets.w,style.get_margin(SIDE_BOTTOM))
	return Rect2(Vector2(insets.x,insets.y),Vector2(maxf(1,control.size.x-insets.x-insets.z),maxf(1,control.size.y-insets.y-insets.w)))
const PORTRAIT_FOCUS = {
	"archer":Rect2(86,31,92,125),"spear":Rect2(85,63,98,113),
	"samurai":Rect2(87,27,91,127),"commander":Rect2(82,25,102,126),
	"gunner":Rect2(90,24,94,132),"naginata":Rect2(88,14,100,137),
	"monk":Rect2(90,9,90,133),"ninja":Rect2(91,13,90,128)
}
var kind: String = "frame"
var tint: Color = Color(BRASS)

class MaterialSurface extends Control:
	var surface_style: StyleBox
	var surface_kind: String = "lacquer"
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)
		set_physics_process(false)
		resized.connect(queue_redraw)
	func _draw() -> void:
		if surface_style!=null and size.x>0 and size.y>0:
			draw_style_box(surface_style,Rect2(Vector2.ZERO,size))
	func diagnostics() -> Dictionary:
		return {"surface":surface_kind,"static":true,"processing":is_processing(),
			"textureBacked":surface_style is StyleBoxTexture,"mouseIgnored":mouse_filter==Control.MOUSE_FILTER_IGNORE}

static func material_texture(surface: String = "lacquer") -> Texture2D:
	var path: String = str(MATERIAL_PATHS.get(surface,MATERIAL_PATHS.lacquer))
	if _material_textures.has(path):
		return _material_textures[path]
	var result: Texture2D
	if ResourceLoader.exists(path):
		result = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image: Image = Image.load_from_file(path)
		if image!=null and not image.is_empty():
			result = ImageTexture.create_from_image(image)
	# Missing assets are not cached, so newly imported artwork becomes available.
	if result!=null:
		_material_textures[path] = result
	return result

static func textured_panel(surface: String = "lacquer", colour: Color = Color.WHITE, content_margin: float = 14.0) -> StyleBox:
	var picture: Texture2D = material_texture(surface)
	if picture==null:
		var fallback: StyleBoxFlat = frame("d7c7a2" if surface=="paper" else SURFACE,LINE)
		fallback.bg_color *= colour
		fallback.content_margin_left = content_margin
		fallback.content_margin_right = content_margin
		fallback.content_margin_top = 10
		fallback.content_margin_bottom = 10
		return fallback
	var panel: StyleBoxTexture = StyleBoxTexture.new()
	panel.texture = picture
	panel.modulate_color = colour
	# Small fixed corners retain the grain's scale without an ornamental frame.
	panel.set_texture_margin_all(clampf(minf(picture.get_width(),picture.get_height())*.018,4,24))
	panel.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	panel.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	panel.content_margin_left = content_margin
	panel.content_margin_right = content_margin
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	return panel

static func floating_label_style() -> StyleBox:
	if _floating_style==null:
		# Retain complete text-layout padding without adding a map backdrop.
		_floating_style=StyleBoxEmpty.new()
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
			_floating_style.set_content_margin(side,8.0)
	return _floating_style

static func texture_layer(parent: Control, surface: String = "lacquer", opacity: float = .35, inset: float = 1.0) -> Control:
	var layer: MaterialSurface = MaterialSurface.new()
	layer.name = "MaterialSurface_"+surface
	layer.surface_kind = surface
	layer.surface_style = textured_panel(surface)
	layer.modulate = Color(1,1,1,clampf(opacity,0,1))
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	layer.set_process(false)
	parent.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.offset_left = inset
	layer.offset_top = inset
	layer.offset_right = -inset
	layer.offset_bottom = -inset
	parent.move_child(layer,0)
	return layer

static func textured_button(state: String = "normal", emphasized: bool = false, is_selected: bool = false) -> StyleBox:
	# Native Button text is drawn after this stylebox. A child texture would
	# otherwise cover that text; texture_layer is for panels with child labels.
	if state=="focus":
		return button("focus")
	if material_texture("lacquer")==null:
		return selected() if is_selected else primary() if emphasized and state=="normal" else button(state)
	var pigment: Color = Color("b8c2c1")
	match state:
		"hover": pigment=Color("dde0d4")
		"pressed": pigment=Color("9cb1bb")
		"disabled": pigment=Color("6f7b7c")
	if emphasized: pigment*=Color("e3ca9e")
	if is_selected: pigment*=Color("9accec")
	var result: StyleBoxTexture = textured_panel("lacquer",pigment) as StyleBoxTexture
	if not emphasized and not is_selected:
		var picture: Texture2D = result.texture
		var sample_size: Vector2 = Vector2(minf(640,picture.get_width()-48),minf(160,picture.get_height()-48))
		result.region_rect = Rect2((picture.get_size()-sample_size)*.5,sample_size)
		result.set_texture_margin_all(4)
	# The ordinary controls sample a strip of wood rather than compressing the
	# whole square into 40px. Primary/selected controls retain the gilded edge.
	return result

static func frame(background: String = SURFACE, border: String = LINE, accent: bool = false) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = Color(background)
	box.border_color = Color(border)
	box.border_width_top = 1
	box.border_width_bottom = 2 if accent else 1
	box.border_width_left = 1
	box.border_width_right = 1
	box.corner_radius_top_left = 2
	box.corner_radius_top_right = 2
	box.corner_radius_bottom_left = 2
	box.corner_radius_bottom_right = 2
	box.corner_detail = 4
	box.shadow_color = Color("00000040")
	box.shadow_size = 4
	box.shadow_offset = Vector2(0,2)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box

static func button(state: String = "normal") -> StyleBoxFlat:
	var box: StyleBoxFlat
	match state:
		"hover": box=frame("343c3df5","9e947b")
		"pressed": box=frame("263b48f5",BLUE,true)
		"disabled": box=frame("1a1e20d9","424a49")
		"focus":
			box=frame("00000000",BLUE)
			box.shadow_size=0
			return box
		_: box=frame(SURFACE,LINE)
	box.border_width_left=0
	box.border_width_right=0
	box.border_width_top=0
	box.shadow_size=0
	return box

static func selected() -> StyleBoxFlat:
	var box=button("normal")
	box.bg_color=Color("243b49f5")
	box.border_color=Color(BLUE)
	box.border_width_bottom=2
	return box

static func primary() -> StyleBoxFlat:
	var box=frame("3c3730f5",BRASS,true)
	box.shadow_size=0
	return box

static func portrait_focus(id: String) -> Rect2:
	return PORTRAIT_FOCUS.get(id,Rect2(80,24,112,136))

static func bust_texture(first: AtlasTexture, id: String) -> AtlasTexture:
	if first==null: return null
	var authored: Rect2=portrait_focus(id)
	var ratio: Vector2=first.region.size/Vector2(256,256)
	var bust=AtlasTexture.new()
	bust.atlas=first.atlas
	bust.region=Rect2(first.region.position+authored.position*ratio,authored.size*ratio)
	return bust

static func ornament(parent: Node, rect: Rect2, motif: String = "frame", colour: String = BRASS) -> Control:
	var detail = load("res://native/sengoku_ui.gd").new()
	detail.kind = motif
	detail.tint = Color(colour)
	detail.position = rect.position
	detail.size = rect.size
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(detail)
	return detail

func _draw() -> void:
	if kind == "paper":
		var grain = RandomNumberGenerator.new()
		grain.seed=1754
		for index in range(int(size.x*size.y/1100)):
			var start = Vector2(grain.randf_range(8,size.x-8),grain.randf_range(8,size.y-8))
			draw_line(start,start+Vector2(grain.randf_range(4,22),grain.randf_range(-1,1)),Color("5b4d3520"),1,true)
		for offset in [3.0,7.0,size.y-5.0]:
			draw_line(Vector2(8,offset),Vector2(size.x-8,offset),Color("8a75522a"),1)
	elif kind == "crest":
		var center = size / 2
		var radius = minf(size.x, size.y) * 0.43
		draw_arc(center, radius, 0, TAU, 64, tint, 2, true)
		for angle in [-PI / 2, PI / 6, PI * 5 / 6]:
			var position_now = center + Vector2(cos(angle), sin(angle)) * radius * 0.31
			draw_circle(position_now, radius * 0.23, tint, true, -1, true)
		draw_circle(center, radius * 0.1, tint, true, -1, true)
	elif kind == "divider":
		draw_line(Vector2(0, size.y / 2), Vector2(size.x, size.y / 2), Color(tint, 0.42), 1)
		draw_polygon(PackedVector2Array([Vector2(0, size.y / 2 - 3), Vector2(3, size.y / 2), Vector2(0, size.y / 2 + 3), Vector2(-3, size.y / 2)]), PackedColorArray([tint]))
	else:
		var r = Rect2(Vector2(5, 5), size - Vector2(10, 10))
		for point in [r.position, Vector2(r.end.x,r.position.y), r.end, Vector2(r.position.x,r.end.y)]:
			var direction = Vector2(1 if point.x < size.x / 2 else -1, 1 if point.y < size.y / 2 else -1)
			draw_line(point, point + Vector2(direction.x * 13, 0), tint, 2)
			draw_line(point, point + Vector2(0, direction.y * 13), tint, 2)
			draw_circle(point + direction * 4, 1.3, tint)
