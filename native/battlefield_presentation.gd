extends RefCounted
## Display-only orientation. Authored terrain, paths, actors and gameplay
## coordinates stay canonical; text and the camera's pan/zoom stay upright.

const POSITION_EPSILON: float = 0.000001
const FRIENDLY_SECTOR_MAX_ASPECT: float = 1888.0 / 900.0

static func point(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Dictionary: return Vector2(float(value.get("x",0)),float(value.get("y",0)))
	if value is Array and value.size()>=2: return Vector2(float(value[0]),float(value[1]))
	return Vector2.ZERO

static func allows_friendly(value: Vector2) -> bool:
	return allows_friendly_at_aspect(value,FRIENDLY_SECTOR_MAX_ASPECT)

static func allows_friendly_at_aspect(value: Vector2, aspect: float) -> bool:
	# Clock 8 through 5 is measured in actual screen pixels, not a square
	# normalized map. This includes lower-left, bottom and lower-right only.
	var dx: float = (value.x-0.5)*aspect
	var dy: float = value.y-0.5
	return dy>0.0 and dx>=-sqrt(3.0)*dy-POSITION_EPSILON and dx<=dy/sqrt(3.0)+POSITION_EPSILON

static func to_view(value: Vector2, mirrored: bool) -> Vector2:
	return Vector2(1.0-value.x,value.y) if mirrored else value

static func to_model(value: Vector2, mirrored: bool) -> Vector2:
	return to_view(value,mirrored)

static func pixel_to_view(value: Vector2, extent: Vector2, mirrored: bool) -> Vector2:
	return Vector2(extent.x-value.x,value.y) if mirrored else value

static func direction_to_view(value: Vector2, mirrored: bool) -> Vector2:
	return Vector2(-value.x,value.y) if mirrored else value

static func rect_to_view(value: Rect2, mirrored: bool) -> Rect2:
	return Rect2(Vector2(1.0-value.end.x,value.position.y),value.size) if mirrored else value

static func decision(stage: Dictionary) -> Dictionary:
	var original_fits: bool = true
	var mirror_fits: bool = true
	var count: int = 0
	var escort: Array = stage.get("escortRoute",[])
	for objective in stage.get("objectives",[]):
		var anchor: Vector2=point(objective)
		if bool(objective.get("mobile",false)) and not escort.is_empty(): anchor=point(escort[0])
		original_fits = original_fits and allows_friendly(anchor)
		mirror_fits = mirror_fits and allows_friendly(to_view(anchor,true))
		count+=1
	# Keep an already-valid presentation. Never switch orientation during a
	# moving objective's loop, a combat frame, a resize or a camera gesture.
	var mirrored: bool = not original_fits and mirror_fits
	return {"mirrored":mirrored,"satisfiable":original_fits or mirror_fits,"objectiveCount":count,"originalFits":original_fits,"mirrorFits":mirror_fits,"coordinateSpace":"canonical","displayPolicy":"friendly_clock_8_to_5_lower","policyAspect":FRIENDLY_SECTOR_MAX_ASPECT}

static func mirror_for_stage(stage: Dictionary) -> bool:
	return bool(decision(stage).mirrored)
