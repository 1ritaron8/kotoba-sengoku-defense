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
		return RubyText.make_tooltip(for_text,ruby_context_words)
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
		var signature: String=str([text,size,points,ink,horizontal_alignment,vertical_alignment,autowrap_mode,get_theme_font("font").get_instance_id(),get_theme_constant("outline_size"),get_theme_color("font_outline_color"),ruby_context_words])
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
		ruby_text.colour_reading_groups=false
		ruby_text.wrap_japanese=autowrap_mode!=TextServer.AUTOWRAP_OFF
		ruby_text.horizontal_alignment=horizontal_alignment
		ruby_text.outline_size=mini(2,get_theme_constant("outline_size"))
		ruby_text.outline_ink=get_theme_color("font_outline_color")
		ruby_text.size.x=maxf(1,size.x)
		ruby_text.set_text(text,points,ruby_context_words)
		var height: float=float(ruby_text.get_text_layout().height)
		ruby_text.size.y=height
		if not is_equal_approx(custom_minimum_size.y,_ruby_minimum): _minimum_before_ruby=custom_minimum_size.y
		_ruby_minimum=maxf(_minimum_before_ruby,height)
		custom_minimum_size.y=_ruby_minimum
		ruby_text.position=Vector2(0,maxf(0,size.y-height)*(.5 if vertical_alignment==VERTICAL_ALIGNMENT_CENTER else 1.0 if vertical_alignment==VERTICAL_ALIGNMENT_BOTTOM else 0.0))
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
		return RubyText.make_tooltip(for_text,ruby_context_words)
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
		var signature: String=str([text,size,points,ink,alignment,get_theme_font("font").get_instance_id(),get_theme_constant("outline_size"),_colours.get("font_outline_color",Color.BLACK),ruby_context_words])
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
			ruby_text.colour_reading_groups=false
			ruby_text.horizontal_alignment=alignment
			ruby_text.wrap_japanese=true
			ruby_text.size.x=maxf(1,size.x-8)
			ruby_text.set_text(text,points,ruby_context_words)
			var height: float=float(ruby_text.get_text_layout().height)
			ruby_text.size.y=height
			if not is_equal_approx(custom_minimum_size.y,_ruby_minimum): _minimum_before_ruby=custom_minimum_size.y
			_ruby_minimum=maxf(_minimum_before_ruby,height+4)
			custom_minimum_size.y=_ruby_minimum
			ruby_text.position=Vector2(4,maxf(0,size.y-height)*.5)
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
	panel.content_margin_top = 7
	panel.content_margin_bottom = 7
	return panel

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
