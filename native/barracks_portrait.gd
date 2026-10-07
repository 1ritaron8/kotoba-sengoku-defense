extends Control
## Live barracks cutout made from the original authored standing poses.
## The canvas transform and foot anchor stay fixed for the entire animation.

const MANIFESTS: Array[String] = [
	"res://assets/units-standing/core.json",
	"res://assets/units-standing/support.json",
	"res://assets/units-standing/manifest.json",
	"res://assets/units-animated/manifest.json"
]
const POSE_SHADER: String = """
shader_type canvas_item;
uniform vec4 frame_a = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 frame_b = vec4(0.0, 0.0, 1.0, 1.0);
uniform float pose_blend : hint_range(0.0, 1.0) = 0.0;
uniform vec2 registration_a = vec2(0.0);
uniform vec2 registration_b = vec2(0.0);
uniform vec2 canvas_origin = vec2(0.0);
uniform vec2 canvas_span = vec2(1.0);
uniform vec2 half_pixel = vec2(0.001953125);
varying vec4 portrait_tint;
void vertex() { portrait_tint = COLOR; }
void fragment() {
	vec2 a_uv = canvas_origin + UV * canvas_span + registration_a;
	vec2 b_uv = canvas_origin + UV * canvas_span + registration_b;
	vec4 a = vec4(0.0);
	vec4 b = vec4(0.0);
	if (a_uv.x >= 0.0 && a_uv.x <= 1.0 && a_uv.y >= 0.0 && a_uv.y <= 1.0) {
		a = texture(TEXTURE, frame_a.xy + clamp(a_uv, half_pixel, vec2(1.0) - half_pixel) * frame_a.zw);
	}
	if (b_uv.x >= 0.0 && b_uv.x <= 1.0 && b_uv.y >= 0.0 && b_uv.y <= 1.0) {
		b = texture(TEXTURE, frame_b.xy + clamp(b_uv, half_pixel, vec2(1.0) - half_pixel) * frame_b.zw);
	}
	float alpha = mix(a.a, b.a, pose_blend);
	vec3 premultiplied = mix(a.rgb * a.a, b.rgb * b.a, pose_blend);
	vec3 pigment = premultiplied / max(alpha, 0.00001);
	COLOR = vec4(pigment, alpha) * portrait_tint;
}
"""

static var _bounds_cache: Dictionary = {}
static var _shader: Shader

var unit_id: String = "archer"
var evolution_stage: int = 0
var available: bool = true
var elapsed: float = 0.0
var active: bool = false
var texture: Texture2D
var frame: int = 0
var next_frame: int = 1
var frames: int = 6
var fps: float = 5.0
var row: int = 0
var cell_size: Vector2 = Vector2(256,256)
var baseline: Vector2 = Vector2(128,228)
var smooth_blending: bool = false
var animate_poses: bool = false
var output: TextureRect

var _source: Dictionary = {}
var _pose_material: ShaderMaterial
var _body_bounds: Rect2 = Rect2()
var _draw_rect: Rect2 = Rect2()
var _foot_position: Vector2 = Vector2.ZERO
var _ready_art: bool = false
var _blend: float = 0.0
var _reason: String = ""
var _frame_anchors: Array[Vector2] = []
var _frame_registration: Array[Vector2] = []
var _source_bounds: Array[Rect2] = []
var _registered_bounds: Array[Rect2] = []
var _canvas_origin: Vector2 = Vector2(-32,-32)
var _canvas_size: Vector2 = Vector2(320,320)
var _registration_source: String = ""
var _registration_band: int = 12

func configure(id: String, evolution: int = 0, unlocked: bool = true) -> void:
	unit_id = id
	evolution_stage = clampi(evolution,0,2)
	available = unlocked
	elapsed = 0.0
	frame = 0
	next_frame = 1
	if is_node_ready():
		_load_art()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	output = TextureRect.new()
	output.name = "AuthoredStandingPoses"
	output.mouse_filter = Control.MOUSE_FILTER_IGNORE
	output.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	output.stretch_mode = TextureRect.STRETCH_SCALE
	output.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if _shader==null:
		_shader = Shader.new()
		_shader.code = POSE_SHADER
	_pose_material = ShaderMaterial.new()
	_pose_material.shader = _shader
	output.material = _pose_material
	add_child(output)
	resized.connect(_layout_art)
	_load_art()
	_sync_activity()

static func source_for(id: String, evolution: int = 0) -> Dictionary:
	# A missing class never silently borrows a different class's appearance.
	for path in MANIFESTS:
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			continue
		var sprites: Dictionary = data.get("sprites",{})
		if not sprites.has(id):
			continue
		var description: Variant = sprites[id]
		var sprite: Dictionary = description.duplicate(true) if description is Dictionary else {"path":str(description)}
		# Legacy poses remain available until the newly authored sheet is imported.
		if not ResourceLoader.exists(str(sprite.get("path",""))):
			continue
		var columns: int = maxi(1,int(data.get("columns",6)))
		var rows: int = maxi(1,int(data.get("rows",4)))
		var idle: Dictionary = data.get("animations",{}).get("idle",{})
		var result: Dictionary = {
			"path":str(sprite.get("path","")),"manifestPath":path,
			"columns":columns,"rows":rows,
			"row":int(sprite.get("row",idle.get("row",0))),
			"frames":clampi(int(sprite.get("frames",idle.get("frames",6))),1,columns),
			"fps":maxf(0.1,float(sprite.get("fps",idle.get("fps",5.0)))),
			"anchor":sprite.get("anchor",data.get("anchor",{"x":.5,"y":.890625})),
			"baselineY":float(sprite.get("baselineY",data.get("baselineY",0))),
			"cellHeight":float(data.get("cellHeight",0)),
			"normalizedBaseline":float(sprite.get("baseline",data.get("baseline",-1))),
			"frameAnchors":sprite.get("frameAnchors",[]),
			"evolution":clampi(evolution,0,2),"visualEvolution":false
		}
		return result
	return {}

static func resolve_source(id: String, evolution: int = 0) -> Dictionary:
	return source_for(id,evolution)

static func frame_texture(id: String, evolution: int = 0) -> AtlasTexture:
	var source: Dictionary = source_for(id,evolution)
	if source.is_empty() or not ResourceLoader.exists(str(source.path)):
		return null
	var sheet: Texture2D = load(str(source.path)) as Texture2D
	if sheet==null:
		return null
	var cell: Vector2 = sheet.get_size()/Vector2(float(source.columns),float(source.rows))
	var result: AtlasTexture = AtlasTexture.new()
	result.atlas = sheet
	result.region = Rect2(Vector2(0,float(source.row)*cell.y),cell)
	return result

static func first_frame_texture(id: String, evolution: int = 0) -> AtlasTexture:
	return frame_texture(id,evolution)

func _load_art() -> void:
	_source = source_for(unit_id,evolution_stage)
	texture = null
	_ready_art = false
	_reason = ""
	if not _source.is_empty() and ResourceLoader.exists(str(_source.path)):
		texture = load(str(_source.path)) as Texture2D
	if texture==null:
		_reason = "No authored standing sheet is available for "+unit_id
		output.texture = null
		output.visible = false
		queue_redraw()
		_sync_activity()
		return
	cell_size = texture.get_size()/Vector2(float(_source.columns),float(_source.rows))
	row = clampi(int(_source.row),0,int(_source.rows)-1)
	frames = int(_source.frames)
	fps = float(_source.fps)
	var anchor: Dictionary = _source.anchor
	baseline = Vector2(float(anchor.get("x",.5))*cell_size.x,float(anchor.get("y",.890625))*cell_size.y)
	if float(_source.baselineY)>0:
		var original_height: float = float(_source.cellHeight)
		baseline.y = float(_source.baselineY)*cell_size.y/original_height if original_height>0 else float(_source.baselineY)
	if float(_source.normalizedBaseline)>=0:
		baseline.y = float(_source.normalizedBaseline)*cell_size.y
	var registration: Dictionary = _measure_poses()
	_body_bounds = registration.bounds
	_frame_anchors.assign(registration.anchors)
	_source_bounds.assign(registration.sourceBounds)
	_registered_bounds.assign(registration.registeredBounds)
	_frame_registration.clear()
	var padding: Vector2 = Vector2(32,32)
	for anchor_value in _frame_anchors:
		var delta: Vector2 = anchor_value-baseline
		_frame_registration.append(delta/cell_size)
		padding.x = maxf(padding.x,ceilf(absf(delta.x))+2)
		padding.y = maxf(padding.y,ceilf(absf(delta.y))+2)
	_canvas_origin = -padding
	_canvas_size = cell_size+padding*2
	_registration_source = str(registration.source)
	_ready_art = _body_bounds.has_area()
	output.texture = texture
	output.visible = _ready_art
	output.modulate = Color.WHITE if available else Color(.62,.58,.50,1)
	_layout_art()
	_update_pose()
	_sync_activity()

func _measure_poses() -> Dictionary:
	var authored_anchors: Array = _source.get("frameAnchors",[])
	# A mounted silhouette needs all four hooves. Its lowest twelve pixels can
	# contain just one near hoof, changing the inferred centre between poses.
	_registration_band = 32 if unit_id=="commander" else 12
	var key: String = texture.resource_path+":"+str(row)+":"+str(frames)+":"+str(baseline)+":"+str(authored_anchors)+":foot-band-"+str(_registration_band)
	if _bounds_cache.has(key):
		return _bounds_cache[key]
	var bounds: Rect2 = Rect2()
	var anchors: Array[Vector2] = []
	var source_bounds: Array[Rect2] = []
	var registered_bounds: Array[Rect2] = []
	var image: Image = texture.get_image()
	if image==null or image.is_empty():
		# Texture data may be unavailable in a dummy renderer. Keep a safe fit.
		for index in range(frames):
			anchors.append(baseline)
			source_bounds.append(Rect2(Vector2(12,8),cell_size-Vector2(24,24)))
			registered_bounds.append(source_bounds[index])
		return {"bounds":source_bounds[0],"anchors":anchors,"sourceBounds":source_bounds,"registeredBounds":registered_bounds,"source":"texture-data-unavailable"}
	if image.is_compressed():
		image.decompress()
	if image.get_format()!=Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	for index in range(frames):
		var source_rect: Rect2i = Rect2i(roundi(float(index)*cell_size.x),roundi(float(row)*cell_size.y),roundi(cell_size.x),roundi(cell_size.y))
		var crop: Image = image.get_region(source_rect)
		var pixels: PackedByteArray = crop.get_data()
		var width: int = crop.get_width()
		var height: int = crop.get_height()
		var left: int = width
		var right: int = -1
		var top: int = height
		var bottom: int = -1
		for y in range(height):
			for x in range(width):
				if pixels[(y*width+x)*4+3]>32:
					left = mini(left,x)
					right = maxi(right,x)
					top = mini(top,y)
					bottom = maxi(bottom,y)
		var used: Rect2 = Rect2(Vector2(left,top),Vector2(right-left+1,bottom-top+1)) if bottom>=0 else Rect2()
		var foot_left: int = width
		var foot_right: int = -1
		for y in range(maxi(0,bottom-_registration_band+1),bottom+1):
			for x in range(width):
				if pixels[(y*width+x)*4+3]>32:
					foot_left = mini(foot_left,x)
					foot_right = maxi(foot_right,x)
		var foot: Vector2 = Vector2(float(foot_left+foot_right+1)*.5,float(bottom+1)) if foot_right>=0 else baseline
		if authored_anchors.size()==frames and authored_anchors[index] is Dictionary:
			var anchor_data: Dictionary = authored_anchors[index]
			foot = Vector2(float(anchor_data.get("x",.5))*cell_size.x,float(anchor_data.get("y",.890625))*cell_size.y)
		anchors.append(foot)
		source_bounds.append(used)
		used.position += baseline-foot
		registered_bounds.append(used)
		if used.has_area():
			bounds = bounds.merge(used) if bounds.has_area() else used
	var result: Dictionary = {"bounds":bounds,"anchors":anchors,"sourceBounds":source_bounds,"registeredBounds":registered_bounds,"source":"manifest-foot-anchors" if authored_anchors.size()==frames else "alpha-foot-analysis"}
	_bounds_cache[key] = result
	return result

func _layout_art() -> void:
	if output==null or not _ready_art or size.x<2 or size.y<2:
		return
	var fit: float = minf(size.x*.90/maxf(1,_body_bounds.size.x),size.y*.86/maxf(1,_body_bounds.size.y))
	var visible_center_x: float = _body_bounds.get_center().x
	_foot_position = Vector2(size.x*.5+(baseline.x-visible_center_x)*fit,size.y*.91)
	_draw_rect = Rect2(_foot_position-(baseline-_canvas_origin)*fit,_canvas_size*fit)
	output.position = _draw_rect.position
	output.size = _draw_rect.size
	queue_redraw()

func _update_pose() -> void:
	if not _ready_art:
		return
	var phase: float = elapsed*fps if animate_poses else 0.0
	frame = int(floor(phase))%frames
	next_frame = (frame+1)%frames
	_blend = smoothstep(0.0,1.0,fmod(phase,1.0)) if smooth_blending else 0.0
	var atlas_size: Vector2 = texture.get_size()
	var region_size: Vector2 = cell_size/atlas_size
	var region_a: Vector2 = Vector2(float(frame)*cell_size.x,float(row)*cell_size.y)/atlas_size
	var region_b: Vector2 = Vector2(float(next_frame)*cell_size.x,float(row)*cell_size.y)/atlas_size
	_pose_material.set_shader_parameter("frame_a",Vector4(region_a.x,region_a.y,region_size.x,region_size.y))
	_pose_material.set_shader_parameter("frame_b",Vector4(region_b.x,region_b.y,region_size.x,region_size.y))
	_pose_material.set_shader_parameter("pose_blend",_blend)
	_pose_material.set_shader_parameter("registration_a",_frame_registration[frame])
	_pose_material.set_shader_parameter("registration_b",_frame_registration[next_frame])
	_pose_material.set_shader_parameter("canvas_origin",_canvas_origin/cell_size)
	_pose_material.set_shader_parameter("canvas_span",_canvas_size/cell_size)
	_pose_material.set_shader_parameter("half_pixel",Vector2(.5,.5)/cell_size)

func _draw() -> void:
	if not _ready_art:
		return
	# Static soft ellipses attach the feet to the panel without changing poses.
	var width: float = minf(size.x*.21,66.0)
	if unit_id=="commander":
		width *= 1.30
	for layer in range(3):
		var expansion: float = 1.0+float(layer)*.32
		var points: PackedVector2Array = PackedVector2Array()
		for corner in range(40):
			var angle: float = TAU*float(corner)/40.0
			points.append(_foot_position+Vector2(cos(angle)*width*expansion,sin(angle)*6.0*expansion))
		draw_colored_polygon(points,Color(.035,.032,.025,.12-float(layer)*.026))

func _notification(what: int) -> void:
	if what==NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		_sync_activity()

func _sync_activity() -> void:
	active = animate_poses and _ready_art and is_inside_tree() and is_visible_in_tree()
	set_process(active)

func _process(delta: float) -> void:
	if not animate_poses or not active or not is_visible_in_tree():
		_sync_activity()
		return
	elapsed += maxf(0.0,delta)
	_update_pose()

func _exit_tree() -> void:
	active = false
	set_process(false)
	if output!=null:
		output.texture = null
	texture = null

func diagnostics() -> Dictionary:
	var frame_rect: Rect2 = Rect2(Vector2(float(frame)*cell_size.x,float(row)*cell_size.y),cell_size)
	var next_rect: Rect2 = Rect2(Vector2(float(next_frame)*cell_size.x,float(row)*cell_size.y),cell_size)
	var fit: Vector2 = _draw_rect.size/_canvas_size
	var rendered_bounds: Rect2 = Rect2(_draw_rect.position+(_body_bounds.position-_canvas_origin)*fit,_body_bounds.size*fit)
	return {"unitId":unit_id,"evolution":evolution_stage,"active":active,"animationClock":elapsed,"ready":_ready_art,"reason":_reason,"sourceKind":"authored-idle-sheet","sourcePath":texture.resource_path if texture!=null else "","manifestPath":str(_source.get("manifestPath","")),"frame":frame,"nextFrame":next_frame,"frameRect":frame_rect,"nextFrameRect":next_rect,"blend":_blend,"frames":frames,"fps":fps,"row":row,"cellSize":cell_size,"baseline":baseline,"canonicalFoot":baseline,"frameAnchors":_frame_anchors,"registration":_frame_registration,"registrationSource":_registration_source,"footAnalysisBand":_registration_band,"registrationApplied":_ready_art,"sourceBounds":_source_bounds,"registeredBounds":_registered_bounds,"canvasOrigin":_canvas_origin,"canvasSize":_canvas_size,"footPosition":_foot_position,"drawRect":_draw_rect,"renderedBounds":rendered_bounds,"visibleBounds":_body_bounds,"visualEvolution":bool(_source.get("visualEvolution",false)),"unlocked":available,"smoothBlending":smooth_blending}
