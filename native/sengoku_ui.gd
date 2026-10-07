extends Control

# Ink, lacquered wood and aged gold connect the menus to the painted screens.
const INK = "171410"
const SURFACE = "26201bee"
const RAISED = "382c20ee"
const LINE = "64523b"
const BRASS = "c9ac6a"
const TEXT = "f2ead9"
const MUTED = "c0b49c"
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
	var pigment: Color = Color("d0c0a5")
	match state:
		"hover": pigment=Color("f5dfb6")
		"pressed": pigment=Color("bda382")
		"disabled": pigment=Color("756d60")
	if emphasized: pigment*=Color("efba97")
	if is_selected: pigment*=Color("ffdf9b")
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
		"hover": box=frame("463727f5","b49a6c")
		"pressed": box=frame("58402cf5",BRASS,true)
		"disabled": box=frame("221c16c0","44382b")
		"focus":
			box=frame("00000000",BRASS)
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
	box.bg_color=Color("493725f5")
	box.border_color=Color(BRASS)
	box.border_width_bottom=2
	return box

static func primary() -> StyleBoxFlat:
	var box=frame("512b21f5",BRASS,true)
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
