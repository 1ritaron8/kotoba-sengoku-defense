extends Node2D

# Presentation only; the preview is supplied by the existing recruitment rules.
var battle: Node2D
var preview: Dictionary = {}

func _ready() -> void:
	z_index = 1000
	self_modulate = Color(1,1,1,.62)

func present(value: Dictionary) -> void:
	preview = value
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(battle): return
	if bool(preview.get("allowsSupportDeployment",false)): _draw_support_areas()
	if not bool(preview.get("visible",false)): return
	var data: Dictionary = preview.get("position",{})
	var point: Vector2 = Vector2(float(data.get("x",-1)),float(data.get("y",-1)))
	if not point.is_finite() or not Rect2(Vector2.ZERO,Vector2.ONE).has_point(point): return
	var valid: bool = bool(preview.get("valid",false))
	var color: Color = Color("73e5d2") if valid else Color("f28c79")
	var screen: Vector2 = battle._screen(point)
	var footprint: PackedVector2Array = PackedVector2Array()
	for index in range(33):
		var angle: float = TAU*index/32.0
		footprint.append(screen+Vector2(cos(angle)*22,sin(angle)*8))
	draw_colored_polygon(footprint,Color(.025,.04,.03,.72))
	draw_polyline(footprint,color,2.4,true)
	if battle.painted_actors.is_ready():
		var actor: Dictionary={"type":str(preview.get("unitType",preview.get("type","spear"))),"animation":"idle"}
		battle.painted_actors.draw_actor(self,actor,screen,true,battle.painted_actors.body_height_screen*battle.field_rect.size.y/620.0,Vector2(1,-1))
	if valid:
		draw_line(screen+Vector2(-6,0),screen+Vector2(-1,5),Color("f3efda"),2.4,true)
		draw_line(screen+Vector2(-1,5),screen+Vector2(8,-5),Color("f3efda"),2.4,true)
	else:
		draw_line(screen+Vector2(-7,-6),screen+Vector2(7,6),color,2.4,true)
		draw_line(screen+Vector2(7,-6),screen+Vector2(-7,6),color,2.4,true)

func _draw_support_areas() -> void:
	# These circles describe support deployment only, never weapon range.
	# Terrain, structure and return-route checks still decide each actual click.
	var areas: Array=preview.get("supportAreas",[])
	for area in areas:
		var center_value: Variant=area.get("center",Vector2(INF,INF))
		var center: Vector2=center_value if center_value is Vector2 else Vector2(float(center_value.get("x",INF)),float(center_value.get("y",INF)))
		var radius: float=float(area.get("radius",0))
		if not center.is_finite() or radius<=0: continue
		var outline: PackedVector2Array=PackedVector2Array()
		for index in range(65):
			var angle: float=TAU*float(index)/64.0
			outline.append(battle._screen(center+Vector2(cos(angle),sin(angle))*radius))
		draw_colored_polygon(outline,Color(.22,.65,.55,.07))
		draw_polyline(outline,Color(.48,.88,.75,.68),1.6,true)
