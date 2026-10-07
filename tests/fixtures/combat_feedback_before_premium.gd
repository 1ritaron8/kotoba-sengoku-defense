extends Node2D
## Render feedback from committed combat events, without changing simulation.

var battle: Node2D
var font: Font
var paused: bool = false
var marks: Array[Dictionary] = []
var event_counts: Dictionary = {}
var banner: String = ""
var banner_clock: float = 0.0
var danger_clock: float = 0.0
var last_number: Dictionary = {}

func _ready() -> void:
	z_index = 2250

func reset() -> void:
	marks.clear()
	last_number.clear()
	event_counts.clear()
	banner = ""
	banner_clock = 0.0
	danger_clock = 0.0
	queue_redraw()

func _point(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary and value.has("x") and value.has("y"):
		return Vector2(float(value.x),float(value.y))
	return Vector2(-1,-1)

func _valid(point: Vector2) -> bool:
	return is_finite(point.x) and is_finite(point.y) and point.x>=0 and point.y>=0

func _mark(kind: String, point: Vector2, lifetime: float, extra: Dictionary = {}) -> void:
	if not _valid(point): return
	var value: Dictionary = {"kind":kind,"point":point,"age":0.0,"life":lifetime}
	value.merge(extra,true)
	marks.append(value)
	# A mass splash hit cannot retain unbounded drawing work or old text.
	if marks.size()>96:
		marks.pop_front()

func consume_event(event: Dictionary) -> void:
	var action: String = str(event.get("action",event.get("type","")))
	event_counts[action] = int(event_counts.get(action,0))+1
	var point: Vector2 = _point(event.get("victimPosition",event.get("position",{})))
	var source: Vector2 = _point(event.get("sourcePosition",event.get("position",{})))
	var weapon: String = str(event.get("weapon",""))
	var enemy_victim: bool = str(event.get("victimSide","enemy"))=="enemy"
	match action:
		"shot":
			if weapon=="matchlock":
				_mark("muzzle",source,.19,{"target":point})
				_mark("smoke",source,.65)
			elif weapon=="bow":
				_mark("release",source,.14,{"target":point})
			elif weapon!="charge":
				_mark("slash",point,.18,{"source":source,"weapon":weapon})
		"hit":
			var damage: float = float(event.get("damage",0))
			if damage<=0: return
			_mark("hit",point,.30,{"source":source,"enemyVictim":enemy_victim,"weapon":weapon,"seed":int(event.get("victimId",0))})
			var key: String = str(event.get("victimSide",""))+":"+str(event.get("victimId",-1))
			var now: float = float(Time.get_ticks_msec())/1000.0
			if now-float(last_number.get(key,-100.0))>=.12:
				_mark("number",point,.64,{"text":str(roundi(damage)),"enemyVictim":enemy_victim})
				last_number[key] = now
		"killed":
			_mark("fall",point,.46)
			var reward: int = int(event.get("reward",0))
			if reward>0:
				_mark("reward",point,.70,{"text":"+%d" % reward})
		"charge_impact":
			_mark("charge",point,.36,{"source":source})
		"deploy", "placed", "tower_placed":
			_mark("deploy",_point(event.get("position",{})),.44)
		"objective_hit":
			danger_clock = .65
			_mark("charge",point,.36,{"source":source})
		"wavebegin", "wave":
			banner = "第 %02d 陣 · 敵襲" % int(event.get("wave",1))
			banner_clock = 1.0
		"waveend":
			banner = "陣を守り抜いた · 방어 성공"
			banner_clock = 1.05
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not is_instance_valid(battle): return
	if not paused:
		for mark in marks:
			mark.age = float(mark.age)+minf(delta,.15)
		marks = marks.filter(func(mark): return float(mark.age)<float(mark.life))
		banner_clock = maxf(0,banner_clock-delta)
		danger_clock = maxf(0,danger_clock-delta)
	queue_redraw()

func _ground(point: Vector2) -> Vector2:
	return point*battle.field_rect.size

func _body(point: Vector2) -> Vector2:
	var position_value: Vector2 = _ground(point)
	var offset: float = battle.field_rect.size.x/22.0*.42*battle._depth_scale(point.y)*battle.three_d_actor_scale if battle.three_d_enabled else 17.0
	return position_value-Vector2(0,offset)

func _ink(value: String, color: Color, position_value: Vector2, size_value: int) -> void:
	var face: Font = font if font!=null else ThemeDB.fallback_font
	var width: float = face.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_value).x
	position_value.x -= width*.5
	draw_string_outline(face,position_value,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_value,2,Color(0.02,.025,.02,color.a))
	draw_string(face,position_value,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_value,color)

func _draw() -> void:
	if not is_instance_valid(battle): return
	for shot in battle.projectiles:
		var point: Vector2 = _body(shot.position)
		var target: Vector2 = _body(shot.targetPos)
		var direction: Vector2 = (target-point).normalized()
		var gun: bool = str(shot.type)=="gunner"
		draw_line(point-direction*(24 if gun else 16),point,Color(.04,.035,.025,.90),3.8,true)
		draw_line(point-direction*(24 if gun else 16),point,Color("ffcf7d" if gun else "f2eed9"),2.0,true)
		if not gun:
			draw_line(point-direction.rotated(.45)*4,point,Color("fff3d5"),1.4,true)
			draw_line(point-direction.rotated(-.45)*4,point,Color("fff3d5"),1.4,true)
	for mark in marks:
		var t: float = clampf(float(mark.age)/float(mark.life),0,1)
		var alpha: float = 1.0-t
		var point: Vector2 = _body(mark.point)
		match str(mark.kind):
			"muzzle":
				var direction: Vector2 = (_body(mark.target)-point).normalized()
				draw_line(point,point+direction*(20-10*t),Color(1,.78,.35,alpha),5.0*alpha,true)
				draw_circle(point+direction*5,4.0*alpha,Color(1,.94,.7,alpha))
			"release":
				var direction: Vector2 = (_body(mark.target)-point).normalized()
				draw_line(point-direction.rotated(.3)*7,point+direction*8,Color(.91,.93,.83,alpha*.6),1.6,true)
			"slash":
				var source: Vector2 = _body(mark.source) if _valid(mark.source) else point-Vector2(15,5)
				var direction: Vector2 = (point-source).normalized()
				if direction.length_squared()<.1: direction=Vector2.RIGHT
				var tip: Vector2 = point+direction.rotated(-.6+t*1.2)*11
				draw_line(point-direction.rotated(.4)*8,tip,Color(.96,.91,.74,alpha*.8),2.2*alpha,true)
			"hit":
				var color: Color = Color(1,.84,.52,alpha) if bool(mark.enemyVictim) else Color(1,.42,.32,alpha)
				if t<.20: draw_circle(point,3*(1-t),Color(1,.97,.87,alpha))
				for index in range(5):
					var angle: float = index*TAU/5.0+float(mark.seed%13)*.24
					var direction: Vector2 = Vector2(cos(angle),sin(angle)*.65)
					var start: Vector2 = point+direction*(3+t*13)
					draw_line(start,start+direction*4*alpha,color,1.4,true)
			"number", "reward":
				var color: Color = Color(1,.87,.50,alpha) if str(mark.kind)=="reward" else Color(1,.98,.88,alpha) if bool(mark.enemyVictim) else Color(1,.47,.40,alpha)
				_ink(str(mark.text),color,point-Vector2(0,10+t*23),17 if str(mark.kind)=="reward" else 20)
			"smoke", "fall":
				for index in range(3):
					var offset: Vector2 = Vector2((index-1)*5+sin(t*3+index)*4,-t*12)
					draw_circle(point+offset,(3+t*5),Color(.67,.62,.52,alpha*.18))
			"charge":
				var ground: Vector2 = _ground(mark.point)
				var ring: PackedVector2Array = PackedVector2Array()
				for index in range(25):
					var angle: float = TAU*index/24.0
					ring.append(ground+Vector2(cos(angle),sin(angle)*.38)*(7+t*20))
				draw_polyline(ring,Color(.88,.74,.45,alpha*.85),2.0*alpha,true)
			"deploy":
				var ground: Vector2 = _ground(mark.point)
				var ring: PackedVector2Array = PackedVector2Array()
				for index in range(25):
					var angle: float = TAU*index/24.0
					ring.append(ground+Vector2(cos(angle),sin(angle)*.38)*(7+t*15))
				draw_polyline(ring,Color(.34,.68,1,alpha*.8),1.8,true)
	if danger_clock>0:
		draw_rect(Rect2(Vector2.ONE,battle.field_rect.size-Vector2.ONE*2),Color(.91,.20,.16,danger_clock*.65),false,4.0)
	if banner_clock>0:
		var center: Vector2 = Vector2(battle.field_rect.size.x*.70,34)
		var alpha: float = minf(1,banner_clock*4)
		draw_rect(Rect2(center-Vector2(160,24),Vector2(320,47)),Color(.075,.065,.05,alpha*.82))
		draw_line(center-Vector2(151,24),center+Vector2(151,-24),Color(.78,.56,.33,alpha*.8),1.0)
		_ink(banner,Color(.99,.87,.65,alpha),center+Vector2(0,7),22)

func diagnostics() -> Dictionary:
	return {"events":event_counts.duplicate(true),"activeMarks":marks.size(),"maxMarks":96,"projectiles":battle.projectiles.size() if is_instance_valid(battle) else 0,"paused":paused,"scope":"Feedback consumes actual committed events; no combat damage, speed, rewards or actor position changes."}
