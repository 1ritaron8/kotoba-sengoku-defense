extends Node2D

# Presentation only; the preview is supplied by the existing recruitment rules.
var battle: Node2D
var preview: Dictionary = {}

func _ready() -> void:
	z_index = 1000

func present(value: Dictionary) -> void:
	preview = value
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(battle) or not bool(preview.get("visible",false)): return
	var data: Dictionary = preview.get("position",{})
	var point: Vector2 = Vector2(float(data.get("x",-1)),float(data.get("y",-1)))
	if not point.is_finite() or not Rect2(Vector2.ZERO,Vector2.ONE).has_point(point): return
	var valid: bool = bool(preview.get("valid",false))
	var color: Color = Color("73e5d2") if valid else Color("f28c79")
	var screen: Vector2 = battle._screen(point)
	battle._draw_world_circle(point,float(preview.get("range",0)),Color(color,.025),Color(color,.6),self,1.5)
	if str(preview.get("deploymentKind",""))=="marching":
		battle._draw_world_circle(point,float(preview.get("dropRadius",.055)),Color(color,.08),color,self,2.0)
	var footprint: PackedVector2Array = PackedVector2Array()
	for index in range(33):
		var angle: float = TAU*index/32.0
		footprint.append(screen+Vector2(cos(angle)*22,sin(angle)*8))
	draw_colored_polygon(footprint,Color(.025,.04,.03,.72))
	draw_polyline(footprint,color,2.4,true)
	if valid:
		draw_line(screen+Vector2(-6,0),screen+Vector2(-1,5),Color("f3efda"),2.4,true)
		draw_line(screen+Vector2(-1,5),screen+Vector2(8,-5),Color("f3efda"),2.4,true)
	else:
		draw_line(screen+Vector2(-7,-6),screen+Vector2(7,6),color,2.4,true)
		draw_line(screen+Vector2(7,-6),screen+Vector2(-7,6),color,2.4,true)
