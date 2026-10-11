extends RefCounted
## A conservative local illumination estimate from the authored battlefield.
## Broad painted illumination complements the real joint and terrain shadows.

const GRID_WIDTH: int = 48
const GRID_HEIGHT: int = 32
const CACHE_LIMIT: int = 64
static var _cache: Dictionary = {}
var _field: Dictionary = {}
var _source: String = ""

func configure(stage: Dictionary, provided_image: Image = null) -> void:
	_source = str(stage.get("background",""))
	_field = {}
	var cache_key: String = _source+":"+str(stage.get("sourceRevision",""))
	if provided_image==null and _cache.has(cache_key):
		_field = _cache[cache_key]
		return
	var image: Image = provided_image
	if image==null:
		if _source.is_empty(): return
		if ResourceLoader.exists(_source):
			var texture: Resource = load(_source)
			if texture is Texture2D: image=texture.get_image()
		# A newly generated source PNG can precede its editor import. Exported
		# resources use the imported Texture2D above; never load a missing file.
		if image==null and FileAccess.file_exists(_source):
			image=Image.load_from_file(ProjectSettings.globalize_path(_source))
	if image==null or image.is_empty(): return
	var source_size: Vector2i = image.get_size()
	var reduced: Image = image.duplicate()
	if reduced.is_compressed() and reduced.decompress()!=OK: return
	reduced.convert(Image.FORMAT_RGB8)
	reduced.resize(GRID_WIDTH,GRID_HEIGHT,Image.INTERPOLATE_LANCZOS)
	var colours = PackedColorArray()
	var brightness = PackedFloat32Array()
	colours.resize(GRID_WIDTH*GRID_HEIGHT)
	brightness.resize(GRID_WIDTH*GRID_HEIGHT)
	var total: float = 0.0
	# The broad neighbourhood reduces dark-albedo vs. shadow confusion and
	# stops individual stones or texture pixels from flashing a moving actor.
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var colour_sum = Color(0,0,0,0)
			var weight: float = 0.0
			for offset_y in range(-1,2):
				for offset_x in range(-1,2):
					var kernel: float = (2.0 if offset_x==0 else 1.0)*(2.0 if offset_y==0 else 1.0)
					colour_sum += reduced.get_pixel(clampi(x+offset_x,0,GRID_WIDTH-1),clampi(y+offset_y,0,GRID_HEIGHT-1))*kernel
					weight += kernel
			var colour: Color = colour_sum/weight
			colour.a = 1.0
			var luma: float = _luminance(colour)
			var index: int = y*GRID_WIDTH+x
			colours[index] = colour
			brightness[index] = luma
			total += luma
	_field = {"colours":colours,"brightness":brightness,"reference":clampf(total/float(GRID_WIDTH*GRID_HEIGHT),0.035,0.90),"sourceSize":source_size}
	if provided_image==null:
		if _cache.size()>=CACHE_LIMIT:
			_cache.erase(_cache.keys()[0])
		_cache[cache_key] = _field

static func _luminance(colour: Color) -> float:
	return colour.r*.2126+colour.g*.7152+colour.b*.0722

func sample(point: Vector2) -> Dictionary:
	var result: Dictionary = {"exposure":1.0,"tint":Color.WHITE,"saturation":1.0,"roughnessBias":0.0,"sourceLuminance":0.0}
	if _field.is_empty() or not point.is_finite(): return result
	var point_x: float = clampf(point.x,0,1)*float(GRID_WIDTH-1)
	var point_y: float = clampf(point.y,0,1)*float(GRID_HEIGHT-1)
	var x0: int = floori(point_x)
	var y0: int = floori(point_y)
	var x1: int = mini(x0+1,GRID_WIDTH-1)
	var y1: int = mini(y0+1,GRID_HEIGHT-1)
	var colours: PackedColorArray = _field.colours
	var top: Color = colours[y0*GRID_WIDTH+x0].lerp(colours[y0*GRID_WIDTH+x1],point_x-x0)
	var bottom: Color = colours[y1*GRID_WIDTH+x0].lerp(colours[y1*GRID_WIDTH+x1],point_x-x0)
	var colour: Color = top.lerp(bottom,point_y-y0)
	var luma: float = _luminance(colour)
	var reference: float = float(_field.reference)
	var exposure: float = clampf(pow(maxf(luma,0.006)/reference,0.28),0.80,1.16)
	# Broad reflected terrain colour is restrained so faction hues, skin and
	# armour material identity stay readable even beside green woods or water.
	var chroma = Vector3(colour.r,colour.g,colour.b)/maxf(luma,0.04)
	chroma = chroma.clamp(Vector3(0.5,0.5,0.5),Vector3(1.5,1.5,1.5))
	var tint = Vector3.ONE.lerp(chroma,0.10)
	result.exposure = exposure
	result.tint = Color(tint.x,tint.y,tint.z,1.0)
	result.saturation = lerpf(0.99,1.0,clampf((exposure-.80)/.36,0,1))
	result.sourceLuminance = luma
	return result

func diagnostics() -> Dictionary:
	return {"source":_source,"available":not _field.is_empty(),"gridWidth":GRID_WIDTH,"gridHeight":GRID_HEIGHT,"cachedFields":_cache.size(),"cachedGridPixels":_cache.size()*GRID_WIDTH*GRID_HEIGHT,"sourceSize":str(_field.get("sourceSize",Vector2i.ZERO)),"method":"Broad authored artwork neighbourhood; conservative local exposure and reflected terrain colour."}
