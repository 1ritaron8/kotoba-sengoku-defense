extends Node2D
## QA-only annotations. Never used as an accepted product/art screenshot.
var battle_ref: WeakRef
var measured: Dictionary = {}
var last_marks: Array = []

func configure(battle: Node2D, source_measurement: Dictionary) -> void:
	battle_ref = weakref(battle)
	measured = source_measurement.duplicate(true)
	set_process(true)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if battle_ref == null: return
	var battle: Node2D = battle_ref.get_ref() as Node2D
	if not is_instance_valid(battle): return
	var font: Font = ThemeDB.fallback_font
	var top: PackedVector2Array = []
	var bottom: PackedVector2Array = []
	var art_height: float = float(measured.get("assetPixels",[1831,859])[1])
	for sample in measured.get("sourceRoadSamples",[]):
		top.append(battle.field_point_to_screen(Vector2(float(sample.xNormalized),float(sample.detectedRoadTopPixel)/art_height)))
		bottom.append(battle.field_point_to_screen(Vector2(float(sample.xNormalized),float(sample.detectedRoadBottomPixel)/art_height)))
	if top.size()>=2:
		var polygon: PackedVector2Array = top.duplicate()
		for index in range(bottom.size()-1,-1,-1): polygon.append(bottom[index])
		draw_colored_polygon(polygon,Color(.2,1.0,.55,.10))
		draw_polyline(top,Color(.2,1.0,.55,.90),1.5,true)
		draw_polyline(bottom,Color(.2,1.0,.55,.90),1.5,true)
	var route: Dictionary = measured.get("canonicalRoute",{})
	var entry: Array = route.get("visibleEntry",[1,.0221472393])
	var gate: Array = route.get("gate",[.255,.79])
	draw_line(battle.field_point_to_screen(Vector2(float(entry[0]),float(entry[1]))),battle.field_point_to_screen(Vector2(float(gate[0]),float(gate[1]))),Color(1,.83,.12),2.0,true)
	last_marks.clear()
	for group in [{"actors":battle.units,"side":"F","color":Color(.2,.85,1.0)},{"actors":battle.enemies,"side":"E","color":Color(1.0,.35,.45)}]:
		for actor in group.actors:
			var model: Vector2 = actor.position
			if float(actor.get("hp",1))<=0 or not Rect2(Vector2.ZERO,Vector2.ONE).has_point(model): continue
			var point: Vector2 = battle.field_point_to_screen(model)
			draw_circle(point,3.0,group.color,true,-1.0,true)
			draw_line(point-Vector2(5,0),point+Vector2(5,0),Color.BLACK,1.0)
			draw_line(point-Vector2(0,5),point+Vector2(0,5),Color.BLACK,1.0)
			var label: String = str(group.side)+str(actor.id)
			draw_string(font,point+Vector2(6,14),label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.BLACK)
			draw_string(font,point+Vector2(5,13),label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,group.color)
			last_marks.append({"id":actor.id,"side":group.side,"canonicalPosition":str(model),"actualScreenOrigin":str(point),"animation":str(actor.get("animation","idle"))})
	var legend: Vector2 = battle.field_point_to_screen(Vector2(.31,.92))
	draw_rect(Rect2(legend-Vector2(6,19),Vector2(600,43)),Color(.02,.04,.04,.82))
	draw_string(font,legend,"QA ONLY | yellow: route | green: measured tan-road band",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
	draw_string(font,legend+Vector2(0,17),"Dots: actual model/render origins, not detected anatomical soles",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color(.9,.94,.94))

func diagnostics() -> Dictionary:
	return {"qaOnly":true,"acceptedArtCapture":false,"source":"res://tests/profiles/painted-game-01/road-alignment.json","roadPolygon":"Source color threshold samples x=.30..1.00, linearly joined; feathered edge approximation","footDots":"Actual live actor model/render registration origins; not anatomical sole detection","marks":last_marks.duplicate(true)}
