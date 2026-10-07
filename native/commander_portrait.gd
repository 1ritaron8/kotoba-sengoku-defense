extends Control
## Static historical portrait cutout. No animation, viewport, or pose blending.

const CATALOG_PATH: String = "res://native/hero_catalog.json"
const DEFAULT_HERO: Dictionary = {
	"archer":"asano_nagamasa", "spear":"kato_kiyomasa",
	"samurai":"fukushima_masanori", "gunner":"ishida_mitsunari",
	"naginata":"kato_yoshiaki", "monk":"ankokuji_ekei",
	"commander":"kuroda_kanbei", "ninja":"hachisuka_masakatsu"
}
const HERO_UNITS: Dictionary = {
	"asano_nagamasa":"archer", "kato_kiyomasa":"spear",
	"fukushima_masanori":"samurai", "ishida_mitsunari":"gunner",
	"kato_yoshiaki":"naginata", "ankokuji_ekei":"monk",
	"kuroda_kanbei":"commander", "hachisuka_masakatsu":"ninja",
	"hachisuka_iemasa":"ninja"
}
const STANDING_MANIFESTS: Array[String] = [
	"res://assets/units-standing/core.json",
	"res://assets/units-standing/support.json",
	"res://assets/units-standing/manifest.json",
	"res://assets/units-animated/manifest.json"
]
static var _bounds_cache: Dictionary = {}

var unit_id: String = "archer"
var evolution_stage: int = 0
var available: bool = true
var hero_id: String = "asano_nagamasa"
var texture: Texture2D
var active: bool = false
var portrait_padding: float = 10.0:
	set(value):
		portrait_padding = maxf(0.0,value)
		_fit_art()

var _identity: String = ""
var _source_path: String = ""
var _requested_path: String = ""
var _source_region: Rect2 = Rect2()
var _alpha_bounds: Rect2 = Rect2()
var _image_rect: Rect2 = Rect2()
var _visible_bounds: Rect2 = Rect2()
var _fallback: bool = false
var _has_transparency: bool = false
var _ready_art: bool = false
var _reason: String = ""
var _loads: int = 0

func configure(id: String, evolution: int = 0, unlocked: bool = true, requested_hero: String = "") -> void:
	unit_id = id
	evolution_stage = clampi(evolution,0,2)
	available = unlocked
	var valid_heroes: Dictionary = _hero_units()
	var selected: String = requested_hero if not requested_hero.is_empty() else str(DEFAULT_HERO.get(id,""))
	if str(valid_heroes.get(selected,""))!=id:
		selected = str(DEFAULT_HERO.get(id,""))
	hero_id = selected
	var next_identity: String = unit_id+"/"+hero_id
	var changed: bool = _identity!=next_identity
	_identity = next_identity
	set_process(false)
	set_physics_process(false)
	if is_node_ready() and changed:
		_load_art()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_process(false)
	set_physics_process(false)
	resized.connect(_fit_art)
	_load_art()

func _draw() -> void:
	if _ready_art and texture!=null and _image_rect.has_area():
		draw_texture_rect_region(texture,_image_rect,_source_region,Color.WHITE,false)

func refresh_art() -> void:
	# Call after importing a new portrait; ordinary state updates never reload it.
	if is_node_ready():
		_load_art()

static func _hero_units() -> Dictionary:
	var result: Dictionary = HERO_UNITS.duplicate()
	if FileAccess.file_exists(CATALOG_PATH):
		var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if catalog is Dictionary:
			for entry in catalog.get("heroes",[]):
				if entry is Dictionary:
					var id: String = str(entry.get("id",""))
					var unit: String = str(entry.get("unitId",""))
					if not id.is_empty() and DEFAULT_HERO.has(unit):
						result[id] = unit
	return result

static func _texture_at(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	# Newly written PNGs are usable before an editor import in source previews.
	if FileAccess.file_exists(path):
		var image: Image = Image.load_from_file(path)
		if image!=null and not image.is_empty():
			return ImageTexture.create_from_image(image)
	return null

static func _standing_source(id: String) -> Dictionary:
	for path in STANDING_MANIFESTS:
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			continue
		var description: Variant = data.get("sprites",{}).get(id,null)
		if description==null:
			continue
		var sprite: Dictionary = description if description is Dictionary else {"path":str(description)}
		var source: String = str(sprite.get("path",""))
		if not ResourceLoader.exists(source) and not FileAccess.file_exists(source):
			continue
		var columns: int = maxi(1,int(data.get("columns",6)))
		var rows: int = maxi(1,int(data.get("rows",4)))
		var idle: Dictionary = data.get("animations",{}).get("idle",{})
		return {"path":source,"columns":columns,"rows":rows,
			"row":clampi(int(sprite.get("row",idle.get("row",0))),0,rows-1)}
	return {}

func _load_art() -> void:
	_loads += 1
	texture = null
	_source_path = ""
	_source_region = Rect2()
	_alpha_bounds = Rect2()
	_ready_art = false
	_fallback = false
	_has_transparency = false
	_reason = ""
	_requested_path = "res://assets/commanders/"+hero_id+".png" if not hero_id.is_empty() else ""
	texture = _texture_at(_requested_path)
	if texture!=null:
		_source_path = _requested_path
		_source_region = Rect2(Vector2.ZERO,texture.get_size())
		_measure_alpha()
	if texture==null or not _alpha_bounds.has_area():
		_fallback = true
		_reason = "Historical portrait is unavailable; showing this class's static first authored frame."
		var standing: Dictionary = _standing_source(unit_id)
		texture = _texture_at(str(standing.get("path","")))
		if texture!=null:
			_source_path = str(standing.path)
			var cell: Vector2 = texture.get_size()/Vector2(float(standing.columns),float(standing.rows))
			_source_region = Rect2(Vector2(0,float(standing.row)*cell.y),cell)
			_measure_alpha()
		else:
			_source_path = ""
			_source_region = Rect2()
			_alpha_bounds = Rect2()
			_reason = "No historical portrait or same-class authored standing frame is available."
	_ready_art = texture!=null and _alpha_bounds.has_area()
	_fit_art()

func _measure_alpha() -> void:
	_alpha_bounds = Rect2(Vector2.ZERO,_source_region.size)
	_has_transparency = false
	var key: String = _source_path+":"+str(_source_region)
	if _bounds_cache.has(key):
		_alpha_bounds = _bounds_cache[key].bounds
		_has_transparency = bool(_bounds_cache[key].transparent)
		return
	var image: Image = texture.get_image()
	if image==null or image.is_empty():
		return
	if image.is_compressed() and image.decompress()!=OK:
		return
	var crop: Image = image.get_region(Rect2i(_source_region))
	if crop.is_empty():
		return
	# get_used_rect includes every nonzero alpha pixel, including soft edges.
	# It measures transparent padding only; visible clothing/faces are not cut.
	_alpha_bounds = Rect2(crop.get_used_rect())
	_has_transparency = crop.detect_alpha()!=Image.ALPHA_NONE
	if _bounds_cache.size()>=32:
		_bounds_cache.clear()
	_bounds_cache[key] = {"bounds":_alpha_bounds,"transparent":_has_transparency}

func _fit_art() -> void:
	_image_rect = Rect2()
	_visible_bounds = Rect2()
	if _ready_art and _alpha_bounds.has_area() and size.x>0 and size.y>0:
		var padding: float = minf(portrait_padding,minf(size.x,size.y)*.1)
		var available_size: Vector2 = size-Vector2.ONE*padding*2.0
		var scale_factor: float = minf(available_size.x/_alpha_bounds.size.x,available_size.y/_alpha_bounds.size.y)
		var fitted_size: Vector2 = _alpha_bounds.size*scale_factor
		var origin: Vector2 = (size-fitted_size)*.5
		_visible_bounds = Rect2(origin,fitted_size)
		_image_rect = Rect2(origin-_alpha_bounds.position*scale_factor,_source_region.size*scale_factor)
	queue_redraw()

func diagnostics() -> Dictionary:
	return {
		"heroId":hero_id,"unitId":unit_id,"evolution":evolution_stage,
		"unlocked":available,"sourcePath":_source_path,"requestedPath":_requested_path,
		"static2D":true,"actual3D":false,"alphaCrossfade":false,"depthOfField":false,
		"fallback":_fallback,"fallbackReason":_reason,"ready":_ready_art,
		"pixelSize":_source_region.size,"texturePixelSize":texture.get_size() if texture!=null else Vector2.ZERO,
		"visibleBounds":_visible_bounds,"alphaBounds":_alpha_bounds,"sourceRegion":_source_region,
		"hasTransparency":_has_transparency,"fullPortraitFit":true,"cropMode":"full",
		"frame":0,"framesDisplayed":1,"active":false,"processing":is_processing(),
		"loads":_loads,"animation":false,"visualEvolution":false
	}

func hero_diagnostics() -> Dictionary:
	return diagnostics()
