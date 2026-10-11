extends RefCounted
## Display-only orientation. Authored terrain, paths, actors and gameplay
## coordinates stay canonical; text and the camera's pan/zoom stay upright.

const POSITION_EPSILON: float = 0.000001
const FRIENDLY_LEFT_MAX_X: float = 0.42
const FRIENDLY_LOWER_MIN_Y: float = 0.62
const DEFAULT_ELEVATION_DEGREES: float = 50.0

static func elevation_for_stage(stage: Dictionary) -> float:
	var historical: Dictionary = stage.get("historicalBattlefield",{})
	var viewpoint: Dictionary = historical.get("viewpoint",{})
	var elevation: float = float(viewpoint.get("elevationDegrees",DEFAULT_ELEVATION_DEGREES))
	return clampf(elevation,35.0,65.0) if is_finite(elevation) else DEFAULT_ELEVATION_DEGREES

static func point(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Dictionary: return Vector2(float(value.get("x",0)),float(value.get("y",0)))
	if value is Array and value.size()>=2: return Vector2(float(value[0]),float(value[1]))
	return Vector2.ZERO

static func allows_friendly(value: Vector2) -> bool:
	return value.is_finite() and (value.x<=FRIENDLY_LEFT_MAX_X+POSITION_EPSILON or value.y>=FRIENDLY_LOWER_MIN_Y-POSITION_EPSILON)

static func allows_friendly_at_aspect(value: Vector2, _aspect: float) -> bool:
	# A left-side or lower-side base is allowed at every viewport aspect.
	# Keep this entry point for callers inspecting layouts at different sizes.
	return allows_friendly(value)

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
	return {"mirrored":mirrored,"satisfiable":original_fits or mirror_fits,"objectiveCount":count,"originalFits":original_fits,"mirrorFits":mirror_fits,"coordinateSpace":"canonical","displayPolicy":"friendly_left_or_lower","leftMaxX":FRIENDLY_LEFT_MAX_X,"lowerMinY":FRIENDLY_LOWER_MIN_Y}

static func mirror_for_stage(stage: Dictionary) -> bool:
	return bool(decision(stage).mirrored)
