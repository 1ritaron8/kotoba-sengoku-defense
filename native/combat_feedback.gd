extends Node2D

const RubyText = preload("res://native/ruby_label.gd")
const RubyReadings = preload("res://native/ruby_readings.gd")
const GameFonts = preload("res://native/game_fonts.gd")
const BattlefieldHUD = preload("res://native/battlefield_hud.gd")
const BANNER_PADDING: float = 8.0
var _banner_layouts: Dictionary={}
## Committed combat feedback. This node never changes simulation or rewards.
signal emplacement_alerted(event: Dictionary)
const MAX_MARKS: int = 96
const MAX_NUMBERS: int = 4
const MAX_HEAL_LINKS: int = 6
var battle: Node2D
var troop_renderer: Control
var font: Font
var paused: bool = false
var marks: Array[Dictionary] = []
var event_counts: Dictionary = {}
var emitted_counts: Dictionary = {}
var banner: String = ""
var banner_clock: float = 0.0
var danger_clock: float = 0.0
var last_emplacement_notice: float = -100.0
var _emplacement_pulses: Dictionary = {}
var last_number: Dictionary = {}
var feedback_clock: float = 0.0
var duplicate_events: int = 0
var dropped_marks: int = 0
var _seen_events: Dictionary = {}
var _event_order: Array[String] = []
var _event_order_cursor: int = 0
var _skill_impact_receipts: Dictionary = {}
var _soft_texture: GradientTexture2D
var _painted_offsets: Dictionary={true:{},false:{}}
var _offset_frame: int=-1
var _offset_generation: int=-1
var _offset_battle_id: int=0
var _offset_field: Rect2
var _last_simulation_clock: float=-1.0
var _clock_generation: int=-1
var _clock_battle_id: int=0

func _ready() -> void:
	z_index = 2250
	_prepare_texture()
	_sample_simulation_clock()

func _prepare_texture() -> void:
	if _soft_texture != null: return
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0,0.22,0.58,1.0])
	gradient.colors = PackedColorArray([Color(1,1,1,0.78),Color(1,1,1,0.57),Color(1,1,1,0.17),Color(1,1,1,0)])
	_soft_texture = GradientTexture2D.new()
	_soft_texture.gradient = gradient
	_soft_texture.width = 32
	_soft_texture.height = 32
	_soft_texture.fill = GradientTexture2D.FILL_RADIAL
	_soft_texture.fill_from = Vector2(0.5,0.5)
	_soft_texture.fill_to = Vector2(0.5,0)

func reset() -> void:
	marks.clear()
	last_number.clear()
	event_counts.clear()
	emitted_counts.clear()
	_seen_events.clear()
	_event_order.clear()
	_event_order_cursor = 0
	_skill_impact_receipts.clear()
	banner = ""
	banner_clock = 0.0
	danger_clock = 0.0
	last_emplacement_notice = -100.0
	_emplacement_pulses.clear()
	feedback_clock = 0.0
	duplicate_events = 0
	dropped_marks = 0
	_offset_frame=-1
	_painted_offsets[true].clear(); _painted_offsets[false].clear()
	_sample_simulation_clock()
	queue_redraw()

func _sample_simulation_clock() -> void:
	if not is_instance_valid(battle):
		_last_simulation_clock=-1.0; _clock_generation=-1; _clock_battle_id=0
		return
	_last_simulation_clock=float(battle.animation_time)
	_clock_generation=int(battle.battle_generation)
	_clock_battle_id=battle.get_instance_id()

func _feedback_delta(delta: float) -> float:
	var now: float=float(battle.animation_time)
	var same_battle: bool=_clock_generation==int(battle.battle_generation) and _clock_battle_id==battle.get_instance_id()
	var advanced: float=maxf(0.0,now-_last_simulation_clock) if same_battle and _last_simulation_clock>=0.0 else 0.0
	_sample_simulation_clock()
	if paused or bool(battle.paused): return 0.0
	if advanced>0.0: return advanced
	# Active combat effects follow completed simulation steps, including
	# backlog frames. End-of-wave/death-only fades keep their existing clock.
	if not bool(battle.running) or bool(battle.between_waves) or bool(battle.finished) or bool(battle.battle_closed):
		return minf(maxf(delta,0),0.25)*float(battle.effective_speed())
	return advanced

func _point(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Dictionary and value.has("x") and value.has("y"):
		return Vector2(float(value.x),float(value.y))
	return Vector2(-1,-1)

func _valid(point: Vector2) -> bool:
	return is_finite(point.x) and is_finite(point.y) and point.x>=0 and point.y>=0 and point.x<=1 and point.y<=1

func _accept_event(event: Dictionary) -> bool:
	if not event.has("eventId"): return true
	var key: String = str(event.get("mapId",""))+":"+str(event.eventId)
	if _seen_events.has(key):
		duplicate_events += 1
		return false
	_seen_events[key] = true
	if _event_order.size()<512:
		_event_order.append(key)
	else:
		_seen_events.erase(_event_order[_event_order_cursor])
		_event_order[_event_order_cursor] = key
		_event_order_cursor = (_event_order_cursor+1)%512
	return true

func _mark(kind: String, point: Vector2, lifetime: float, extra: Dictionary = {}, priority: int = 2) -> void:
	if not _valid(point): return
	var value: Dictionary = {"kind":kind,"point":point,"age":0.0,"life":lifetime,"newborn":true,"priority":priority}
	value.merge(extra,true)
	if marks.size()>=MAX_MARKS:
		var oldest_low_priority: int = -1
		var lowest: int = priority
		for index in range(marks.size()):
			if int(marks[index].priority)<=lowest:
				if oldest_low_priority<0 or int(marks[index].priority)<lowest:
					oldest_low_priority=index
					lowest=int(marks[index].priority)
		if oldest_low_priority<0:
			dropped_marks += 1
			return
		marks.remove_at(oldest_low_priority)
		dropped_marks += 1
	marks.append(value)
	emitted_counts[kind] = int(emitted_counts.get(kind,0))+1

func _selected_id() -> int:
	return int(battle.selected_id) if is_instance_valid(battle) else -1

func _important_hit(event: Dictionary) -> bool:
	var selected: int = _selected_id()
	if selected>=0 and ((str(event.get("side",""))=="friendly" and int(event.get("actorId",-1))==selected) or (str(event.get("victimSide",""))=="friendly" and int(event.get("victimId",-1))==selected)):
		return true
	return str(event.get("weapon",""))=="charge" or float(event.get("damage",0))>=35.0 or (str(event.get("victimType","")) in ["heavy","commander"] and float(event.get("damage",0))>=22.0)

func _damage_number(event: Dictionary, point: Vector2) -> void:
	if not _important_hit(event) or not _valid(point): return
	var key: String = str(event.get("victimSide",""))+":"+str(event.get("victimId",-1))
	if feedback_clock-float(last_number.get(key,-100.0))<0.55: return
	var count: int = 0
	for mark in marks:
		if str(mark.kind)=="number": count+=1
	if count>=MAX_NUMBERS: return
	if not last_number.has(key) and last_number.size()>=256:
		last_number.erase(last_number.keys()[0])
	last_number[key] = feedback_clock
	_mark("number",point,0.50,{"text":str(roundi(float(event.get("damage",0)))),"enemyVictim":str(event.get("victimSide","enemy"))=="enemy","targetKey":key,"seed":int(event.get("eventId",0)),"meta":event.duplicate()},5)

func _reward(event: Dictionary, point: Vector2) -> void:
	var reward: int = int(event.get("reward",0))
	if reward<=0 or not _valid(point): return
	# A single aggregated supply figure replaces a number above every corpse.
	for mark in marks:
		if str(mark.kind)=="reward":
			mark.amount = int(mark.amount)+reward
			mark.text = "+%d" % int(mark.amount)
			return
	_mark("reward",point,0.90,{"amount":reward,"text":"+%d" % reward,"meta":event.duplicate()},1)

func _skill_flag(value: Dictionary, key: String) -> bool:
	var flags: Variant = value.get("flags", value.get("skillMeta",{}).get("flags",{}))
	return bool(flags.get(key, false)) if flags is Dictionary else false

func _skill_level_allowed(value: Dictionary, minimum: int) -> bool:
	# The committed helper flag is authoritative when the event has no level.
	# Explicit level metadata can only narrow it, never invent an unlock.
	var meta: Dictionary=value.get("skillMeta",{})
	return int(value.get("campaignLevel",meta.get("campaignLevel",minimum)))>=minimum

func _effect_kind(value: Dictionary) -> String:
	return str(value.get("effectKind",value.get("skillMeta",{}).get("effectKind","")))

func _has_skill(value: Dictionary, skill_id: String) -> bool:
	if str(value.get("skillId", "")) == skill_id: return true
	var meta: Dictionary=value.get("skillMeta",{})
	if str(meta.get("skillId",""))==skill_id: return true
	var ids: Variant = value.get("skillIds",meta.get("skillIds",[]))
	return ids is Array and skill_id in ids

func _authorized(value: Dictionary, ids: Array, minimum: int) -> bool:
	if not _skill_level_allowed(value, minimum): return false
	for id in ids:
		if _has_skill(value, str(id)): return true
	return false

func _skill_feedback(event: Dictionary, action: String, point: Vector2, source: Vector2, extra: Dictionary) -> void:
	var effect: String = _effect_kind(event)
	var active_skill: String=str(event.get("skillId",event.get("skillMeta",{}).get("skillId","")))
	if active_skill=="samurai_parry" and effect=="parry" and action in ["skill_cast","skill","status","hit","skill_hit","parry"] and _authorized(event,["samurai_parry"],3):
		if _new_skill_impact(event,"parry"):
			var detail: Dictionary=extra.duplicate()
			detail["sourceActor"]=str(event.get("victimSide",""))!="friendly"
			_mark("parry",source if bool(detail.sourceActor) else point,.24,detail,3)
		return
	if active_skill=="monk_ward" and effect in ["ward","ward_grant","ward_consume","ward_absorb"] and action in ["skill_cast","skill","status","hit","skill_hit"] and _authorized(event,["monk_ward"],5):
		if _new_skill_impact(event,effect):
			_mark("ward_consume" if effect in ["ward_consume","ward_absorb"] else "ward_grant",point,.28,extra,3)
		return
	if active_skill=="spear_brace" and effect=="brace" and action in ["skill_cast","skill","status"] and _authorized(event,["spear_brace"],5):
		if _new_skill_impact(event,"brace"):
			_mark("brace_contact",point,.24,extra,2)
		return
	if active_skill=="commander_impact" and effect=="impact" and action in ["skill_cast","skill","status"] and _authorized(event,["commander_impact"],5):
		if float(event.get("duration",0))>0 and _new_skill_impact(event,"commander_impact"):
			_mark("impact_contact",point,.24,extra,3)
		return
	if active_skill=="commander_rally" and action in ["skill_cast","skill","status"] and _authorized(event,["commander_rally"],8):
		var targets: Variant=event.get("affectedIds",[])
		if targets is Array and not targets.is_empty() and _new_skill_impact(event,"rally"):
			_mark("rally",source,.36,extra,2)
		return
	if effect=="charge_plant" and _authorized(event,["ninja_timed_charge"],3):
		var charge_id: String=str(event.get("chargeId",""))
		if charge_id.is_empty(): return
		_remove_charge_mark(charge_id)
		var detail: Dictionary=extra.duplicate()
		detail.merge({"chargeId":charge_id,"targetId":int(event.get("targetId",event.get("victimId",-1))),"plantedAt":float(event.get("plantedAt",battle.elapsed)),"generation":int(battle.battle_generation)},true)
		_mark("ninja_charge_fuse",point,maxf(.05,float(event.get("fuseSeconds",.75))),detail,4)
		return
	if effect=="charge_explosion" and _authorized(event,["ninja_timed_charge"],3):
		_remove_charge_mark(str(event.get("chargeId","")))
		_mark("ninja_charge_burst",point,.38,extra,4)
		return
	if effect=="combo" and action in ["hit","skill_hit"] and _authorized(event,["ninja_opening_combo"],5):
		if float(event.get("damage",0))>0 and _new_skill_impact(event,"combo"):
			var detail: Dictionary=extra.duplicate()
			detail["hitIndex"]=clampi(int(event.get("hitIndex",0)),0,2)
			_mark("ninja_combo_cut",point,.16,detail,3)
		return
	if effect=="shrapnel" and action in ["hit","skill_hit"] and _authorized(event,["ninja_charge_shrapnel"],8):
		if float(event.get("damage",0))>0 and _new_skill_impact(event,"shrapnel"): _mark("ninja_shrapnel_contact",point,.20,extra,3)
		return
	if action == "heal":
		var amount: float = float(event.get("healAmount",event.get("healed",event.get("amount",0.0))))
		if not is_finite(amount) or amount <= 0.0 or not _valid(source) or not _valid(point): return
		if effect=="talisman_tick" and not _authorized(event,["monk_talisman"],3): return
		if effect=="victory_prayer" and not _authorized(event,["monk_victory_prayer"],8): return
		var active: int = 0
		for mark in marks:
			if str(mark.kind) == "heal": active += 1
		if active < MAX_HEAL_LINKS:
			var detail: Dictionary = extra.duplicate()
			detail["amount"] = amount
			_mark("heal",point,.62,detail,3)
		return
	if action == "shot":
		if str(event.get("weapon", "")) == "bow" and (_skill_flag(event,"fireArrow") or effect == "fire_arrow") and _authorized(event,["archer_fire"],3):
			_mark("fire_release",source,.16,extra,3)
		if active_skill=="gunner_braced_shot" and _authorized(event,["gunner_braced_shot"],8) and _new_skill_impact(event,"braced_release"):
			_mark("braced_release",source,.18,extra,2)
		return
	if action in ["hit", "skill_hit", "charge_impact"]:
		var damage: float = float(event.get("damage",0.0))
		if not is_finite(damage) or damage <= 0.0: return
		if (_skill_flag(event,"fireArrow") or effect == "fire_arrow") and _authorized(event,["archer_fire"],3):
			_mark("ember",point,.32,extra,3)
		if (_skill_flag(event,"pierce") or effect == "pierce") and _authorized(event,["spear_pierce","gunner_pierce"],3):
			_mark("pierce",point,.18,extra,3)
		if (_skill_flag(event,"armorWeakened") or effect == "armor_break") and _authorized(event,["gunner_armor_break"],5):
			_mark("armor_break",point,.36,extra,3)
		if effect == "sweep" and _authorized(event,["naginata_sweep"],3): _mark("sweep",point,.20,extra,3)
		if effect=="barrage" and _authorized(event,["archer_barrage"],5): _mark("barrage_contact",point,.20,extra,2)
		if active_skill=="samurai_counter_combo" and _authorized(event,["samurai_counter_combo"],5) and _new_skill_impact(event,"counter_cut"):
			var detail: Dictionary=extra.duplicate()
			detail["hitIndex"]=int(event.get("hitIndex",event.get("skillMeta",{}).get("hitIndex",0)))
			_mark("samurai_counter_cut",point,.18,detail,3)
		elif active_skill=="samurai_parry" and effect=="counter" and _authorized(event,["samurai_parry"],3) and _new_skill_impact(event,"counter_cut"):
			_mark("samurai_counter_cut",point,.18,extra,3)
		elif active_skill=="samurai_isshin" and _authorized(event,["samurai_isshin"],8) and _new_skill_impact(event,"isshin"):
			_mark("decisive_cut",point,.22,extra,3)
		if active_skill=="spear_brace" and _authorized(event,["spear_brace"],5) and _new_skill_impact(event,"brace_contact"):
			_mark("brace_contact",point,.20,extra,3)
		elif active_skill=="spear_rear_rank" and _authorized(event,["spear_rear_rank"],8) and _new_skill_impact(event,"rear_rank"):
			_mark("rear_rank_contact",point,.18,extra,3)
		if active_skill=="commander_impact" and _authorized(event,["commander_impact"],5) and _new_skill_impact(event,"commander_impact"):
			_mark("impact_contact",point,.24,extra,3)
		return
	if action in ["burn_tick", "status_tick"]:
		var burn: bool = action=="burn_tick" or effect=="burn_tick"
		var permitted: bool = burn and _authorized(event,["archer_fire"],3)
		if permitted and is_finite(float(event.get("damage",0.0))) and float(event.get("damage",0.0)) > 0.0:
			_mark("ember",point,.28,extra,2)
		return
	if action in ["skill_cast", "skill", "status"]:
		match effect:
			"armor_break":
				if _authorized(event,["gunner_armor_break"],5) and float(event.get("duration",0))>0: _mark("armor_break",point,.36,extra,3)
			"guard", "invulnerable":
				if _authorized(event,["naginata_charge_guard"],8): _mark("guard",source,.32,extra,2)
			"dash", "guard_charge":
				if _authorized(event,["naginata_guard_charge"],5): _mark("dash",source,.24,extra,1)
			"victory_prayer":
				var targets: Variant = event.get("affectedIds",[])
				if _authorized(event,["monk_victory_prayer"],8) and targets is Array and not targets.is_empty(): _mark("prayer",source,.40,extra,2)

func _new_skill_impact(event: Dictionary, kind: String) -> bool:
	var meta: Dictionary=event.get("skillMeta",{})
	var impact: String=str(meta.get("impactId",""))
	if impact.is_empty():
		var token: String=str(meta.get("motionToken",meta.get("attackId","")))
		if token.is_empty(): return true
		impact=token+":"+str(event.get("releaseIndex",meta.get("releaseIndex",0)))+":"+str(event.get("hitIndex",meta.get("hitIndex",-1)))
	var key: String=kind+":"+impact+":"+str(event.get("victimId",-1))
	if _skill_impact_receipts.has(key): return false
	if _skill_impact_receipts.size()>=512: _skill_impact_receipts.erase(_skill_impact_receipts.keys()[0])
	_skill_impact_receipts[key]=true
	return true

func _remove_charge_mark(charge_id: String) -> void:
	if charge_id.is_empty(): return
	marks=marks.filter(func(mark: Dictionary): return str(mark.kind)!="ninja_charge_fuse" or str(mark.get("chargeId",""))!=charge_id)

func _emplacement_damage_warning(event: Dictionary, point: Vector2) -> void:
	if not _valid(point) or str(event.get("victimSide", "")) != "friendly": return
	if str(event.get("victimType", "")) not in ["archer", "gunner", "monk", "naginata"]: return
	var damage: float = float(event.get("damage", 0.0))
	var before: float = float(event.get("hpBefore", 0.0))
	var after: float = float(event.get("hpAfter", before))
	if not is_finite(damage) or damage <= 0 or not is_finite(before) or not is_finite(after) or before <= after: return
	danger_clock = 0.45
	var key: String = str(event.get("victimId", -1))
	if feedback_clock - float(_emplacement_pulses.get(key, -100.0)) >= 0.8:
		if not _emplacement_pulses.has(key) and _emplacement_pulses.size() >= 128:
			_emplacement_pulses.erase(_emplacement_pulses.keys()[0])
		_emplacement_pulses[key] = feedback_clock
		_mark("emplacement_alert", point, 1.0, {"meta":event.duplicate()}, 4)
	if feedback_clock - last_emplacement_notice >= 6.0:
		last_emplacement_notice = feedback_clock
		banner = "진지가 공격받고 있습니다"
		banner_clock = 1.5
		emplacement_alerted.emit(event.duplicate(true))

func consume_event(event: Dictionary) -> void:
	if not _accept_event(event): return
	var action: String = str(event.get("action",event.get("type","")))
	event_counts[action] = int(event_counts.get(action,0))+1
	# Ordinary footsteps have no marks; preserve acceptance/count receipts
	# without preparing vectors or copying the event payload.
	if action=="footstep" and _effect_kind(event) not in ["charge_plant","charge_explosion"]: return
	_offset_frame=-1
	var point: Vector2 = _point(event.get("victimPosition",event.get("position",{})))
	var source: Vector2 = _point(event.get("sourcePosition",event.get("position",{})))
	var weapon: String = str(event.get("weapon",""))
	var extra: Dictionary = {"source":source,"target":point,"weapon":weapon,"seed":int(event.get("eventId",0)),"meta":event.duplicate()}
	if action in ["hit", "skill_hit", "charge_impact"]:
		_emplacement_damage_warning(event, point)
	_skill_feedback(event,action,point,source,extra)
	match action:
		"shot":
			if not _valid(source) or not _valid(point): return
			if str(event.get("unitType", "")) == "monk": return
			if weapon=="matchlock":
				_mark("muzzle",source,0.085,extra,4)
				_mark("smoke",source,0.52,extra,0)
			elif weapon=="bow":
				_mark("release",source,0.11,extra,2)
			elif weapon!="charge":
				_mark("thrust" if weapon in ["spear","staff"] else "cut",point,0.13,extra,2)
		"hit", "skill_hit":
			if not is_finite(float(event.get("damage",0))) or float(event.get("damage",0))<=0 or weapon=="charge": return
			_mark("steel" if float(event.get("armor",0))>=0.20 else "contact",point,0.17,extra,4)
			_damage_number(event,point)
		"charge_impact":
			if not is_finite(float(event.get("damage",0))) or float(event.get("damage",0))<=0: return
			_mark("charge",point,0.34,extra,3)
			_mark("steel" if str(event.get("victimType","")) in ["heavy","shield","commander"] else "contact",point,0.18,extra,4)
			_damage_number(event,point)
		"killed":
			if not bool(event.get("victimSailing",false)):
				_mark("fall",point,0.42,extra,0)
			_reward(event,point)
		"deploy", "placed", "tower_placed":
			_mark("deploy",_point(event.get("position",{})),0.30,extra,1)
		"objective_hit":
			if not _valid(point) or not is_finite(float(event.get("damage",0))) or float(event.get("damage",0))<=0: return
			danger_clock = 0.45
			_mark("objective",point,0.42,extra,3)
		"wavebegin", "wave":
			banner = "第 %02d 陣 · 敵襲\n제 %02d 공세 · 적군 습격" % [int(event.get("wave",1)),int(event.get("wave",1))]
			banner_clock = 2.4
		"waveend":
			banner = "陣を守り抜いた\n방어 성공"
			banner_clock = 2.0
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not is_instance_valid(battle): return
	var elapsed: float=_feedback_delta(delta)
	if not paused and not bool(battle.paused):
		feedback_clock += elapsed
		for mark in marks:
			if str(mark.kind)=="ninja_charge_fuse":
				# Display only a successfully installed charge. Detonation must
				# arrive as its real event; an expired visual never creates one.
				var target: Dictionary=battle._enemy(int(mark.get("targetId",-1)))
				if int(mark.get("generation",-1))!=int(battle.battle_generation) or battle.finished or battle.battle_closed or target.is_empty() or float(target.get("hp",0))<=0 or bool(target.get("escaped",false)):
					mark.age=mark.life
				else:
					mark.point=target.position
					mark.age=maxf(0.0,float(battle.elapsed)-float(mark.plantedAt))
				continue
			# A release on a long/3x frame must reach the GPU at least once.
			if bool(mark.newborn): mark.newborn=false
			else: mark.age = float(mark.age)+elapsed
		marks = marks.filter(func(mark): return float(mark.age)<float(mark.life))
		banner_clock = maxf(0,banner_clock-elapsed)
		danger_clock = maxf(0,danger_clock-elapsed)
	queue_redraw()

func _ground(point: Vector2) -> Vector2:
	return battle.view_point(point)*battle.field_rect.size

func _painted_actor_offset(meta: Dictionary, source: bool) -> Vector2:
	var id: int = int(meta.get("actorId",-1) if source else meta.get("victimId",-1))
	if id<0 or battle.three_d_enabled or not battle.painted_actors.is_ready(): return Vector2.ZERO
	var friendly: bool = str(meta.get("side","friendly") if source else meta.get("victimSide","enemy"))=="friendly"
	_ensure_painted_offsets()
	return _painted_offsets[friendly].get(id,Vector2.ZERO)

func _ensure_painted_offsets() -> void:
	var frame: int=Engine.get_process_frames()
	if _offset_frame==frame and _offset_generation==int(battle.battle_generation) and _offset_battle_id==battle.get_instance_id() and _offset_field==battle.field_rect: return
	_offset_frame=frame; _offset_generation=int(battle.battle_generation)
	_offset_battle_id=battle.get_instance_id(); _offset_field=battle.field_rect
	_painted_offsets[true].clear(); _painted_offsets[false].clear()
	var height: float = battle.painted_actors.body_height_screen*clampf(battle.field_rect.size.y/620.0,.65,1.5)
	for actor in battle.units: _painted_offsets[true][int(actor.id)]=battle.painted_actors.actor_visual_offset(actor,height)
	for actor in battle.enemies: _painted_offsets[false][int(actor.id)]=battle.painted_actors.actor_visual_offset(actor,height)

func _body(point: Vector2, meta: Dictionary = {}, source: bool = false) -> Vector2:
	var type_name: String = str(meta.get("unitType","") if source else meta.get("victimType",""))
	var friendly: bool = str(meta.get("side","friendly") if source else meta.get("victimSide","enemy"))=="friendly"
	var sailing: bool = bool(meta.get("sailing",false) if source else meta.get("victimSailing",false))
	if not battle.three_d_enabled and battle.painted_actors.is_ready():
		var painted_height: float = battle.painted_actors.body_height_screen*clampf(battle.field_rect.size.y/620.0,.65,1.5)
		return _ground(point)+_painted_actor_offset(meta,source)-Vector2(0,painted_height*.52)
	var height: float = 1.48 if (type_name=="commander" and friendly) or type_name=="enemy_cavalry" else 0.98
	if sailing: height=0.76
	if bool(battle.three_d_enabled) and is_instance_valid(troop_renderer) and troop_renderer.has_method("normalized_to_world"):
		var camera_value: Camera3D = troop_renderer.get("camera") as Camera3D
		var viewport_value: SubViewport = troop_renderer.get("viewport") as SubViewport
		if is_instance_valid(camera_value) and is_instance_valid(viewport_value) and camera_value.is_inside_tree():
			var scale_value: float = float(troop_renderer.actor_base_scale())*battle._depth_scale(point.y)
			if troop_renderer.has_method("render_scale_for"):
				scale_value = float(troop_renderer.render_scale_for(point,{"type":type_name,"friendly":friendly,"kind":type_name if not friendly else ""}))
			elif not friendly and type_name=="commander": scale_value*=1.10
			elif not friendly and type_name=="heavy": scale_value*=1.04
			var world: Vector3 = troop_renderer.normalized_to_world(point)+Vector3.UP*height*scale_value
			return troop_renderer.project_world_to_field(world)*battle.field_rect.size/troop_renderer.field_size
	var offset: float = battle.field_rect.size.x/22.0*height*battle._depth_scale(point.y)*battle.three_d_actor_scale*0.91 if battle.three_d_enabled else 18.0
	return _ground(point)-Vector2(0,offset)

func _size_scale(point: Vector2) -> float:
	return clampf(battle.field_rect.size.x/1100.0,0.78,1.35)*lerpf(0.90,1.10,point.y)

func _clip_point(point: Vector2, margin: float = 1.0) -> Vector2:
	return point.clamp(Vector2.ONE*margin,battle.field_rect.size-Vector2.ONE*margin)

func _line(start: Vector2, end: Vector2, colour: Color, width: float) -> void:
	draw_line(_clip_point(start),_clip_point(end),colour,maxf(0.55,width),true)

func _puff(point: Vector2, radius: Vector2, colour: Color) -> void:
	_prepare_texture()
	var rect: Rect2 = Rect2(point-radius,radius*2)
	var clipped: Rect2 = rect.intersection(Rect2(Vector2.ZERO,battle.field_rect.size))
	if not clipped.has_area(): return
	var region: Rect2 = Rect2((clipped.position-rect.position)/rect.size*32,clipped.size/rect.size*32)
	draw_texture_rect_region(_soft_texture,clipped,region,colour)

func annotated_text_layout(value: String, size_value: int, available_width: float = -1.0) -> Dictionary:
	var width: float = floorf(minf(520,battle.field_rect.size.x-16) if available_width<0 else maxf(48,available_width))
	var key: String=str([value,width,size_value])
	if not _banner_layouts.has(key):
		var ruby: Control=RubyText.new()
		ruby.font=GameFonts.body()
		ruby.reading_font=GameFonts.reading()
		ruby.wrap_japanese=true
		ruby.min_reading_size=16
		ruby.colour_reading_groups=true
		ruby.size.x=width
		ruby.set_text(value,size_value)
		if _banner_layouts.size()>=16: _banner_layouts.clear()
		_banner_layouts[key]=ruby.get_text_layout()
		ruby.free()
	return _banner_layouts[key]

func _annotated_bounds(layout: Dictionary) -> Rect2:
	var bounds: Rect2 = Rect2()
	var first: bool = true
	for run in layout.get("runs",[]):
		var run_bounds: Rect2 = run.bounds
		if first:
			bounds = run_bounds
			first = false
		else:
			bounds = bounds.merge(run_bounds)
	return bounds

func _clear_banner_regions(field: Rect2, occupied: Array[Rect2]) -> Array[Rect2]:
	var regions: Array[Rect2] = [field.grow(-BANNER_PADDING)]
	for obstacle in occupied:
		var remaining: Array[Rect2] = []
		for region in regions:
			var cut: Rect2 = region.intersection(obstacle.grow(BANNER_PADDING))
			if not cut.has_area():
				remaining.append(region)
				continue
			# Four disjoint pieces keep allocation bounded and outside the
			# complete visible panel rather than only its title or portrait.
			var pieces: Array[Rect2] = [
				Rect2(region.position,Vector2(region.size.x,cut.position.y-region.position.y)),
				Rect2(Vector2(region.position.x,cut.end.y),Vector2(region.size.x,region.end.y-cut.end.y)),
				Rect2(Vector2(region.position.x,cut.position.y),Vector2(cut.position.x-region.position.x,cut.size.y)),
				Rect2(Vector2(cut.end.x,cut.position.y),Vector2(region.end.x-cut.end.x,cut.size.y))
			]
			for piece in pieces:
				if piece.has_area(): remaining.append(piece)
		regions = remaining
	return regions

# Public presentation evidence for native captures: every body/reading run uses
# the returned origin, and the backdrop includes their complete measured bounds.
func banner_presentation() -> Dictionary:
	if banner.is_empty() or not is_instance_valid(battle): return {}
	var field: Rect2 = BattlefieldHUD.visible_field_rect(self,Rect2(Vector2.ZERO,battle.field_rect.size))
	var occupied: Array[Rect2] = BattlefieldHUD.visible_occupied_rects(self,field)
	var regions: Array[Rect2] = _clear_banner_regions(field,occupied)
	var preferred_x: float = field.get_center().x
	var chosen: Dictionary = {}
	var best_score: float = INF
	for region in regions:
		var width: float = minf(520,region.size.x-BANNER_PADDING*2)
		if width<48: continue
		var layout: Dictionary = annotated_text_layout(banner,19,width)
		var text_bounds: Rect2 = _annotated_bounds(layout)
		var box_size: Vector2 = text_bounds.size+Vector2.ONE*BANNER_PADDING*2
		if box_size.x>region.size.x or box_size.y>region.size.y: continue
		var left: float = clampf(preferred_x-box_size.x*.5,region.position.x,region.end.x-box_size.x)
		var rect: Rect2 = Rect2(Vector2(left,region.end.y-box_size.y),box_size)
		var score: float = (field.end.y-rect.end.y)*4+absf(rect.get_center().x-preferred_x)+text_bounds.size.y
		if score>=best_score: continue
		best_score = score
		chosen = {"rect":rect,"origin":rect.position+Vector2.ONE*BANNER_PADDING-text_bounds.position,"layout":layout,"field":field,"occupied":occupied,"fits":true}
	if not chosen.is_empty(): return chosen
	# If the caller covers the entire field, retain the complete message and
	# expose a failed allocation rather than hiding content or shrinking fonts.
	var fallback_layout: Dictionary = annotated_text_layout(banner,19,maxf(48,field.size.x-BANNER_PADDING*4))
	var fallback_bounds: Rect2 = _annotated_bounds(fallback_layout)
	var fallback_size: Vector2 = fallback_bounds.size+Vector2.ONE*BANNER_PADDING*2
	var fallback_rect: Rect2 = Rect2(Vector2(field.get_center().x-fallback_size.x*.5,field.end.y-fallback_size.y-BANNER_PADDING),fallback_size)
	return {"rect":fallback_rect,"origin":fallback_rect.position+Vector2.ONE*BANNER_PADDING-fallback_bounds.position,"layout":fallback_layout,"field":field,"occupied":occupied,"fits":false,"reason":"No clear region fits the complete annotated banner."}

func _draw_banner(alpha: float) -> void:
	var presentation: Dictionary = banner_presentation()
	if presentation.is_empty(): return
	for run in presentation.layout.runs:
		var face: Font = GameFonts.reading() if run.role=="reading" else GameFonts.body()
		var point: Vector2 = presentation.origin+run.position
		draw_string_outline(face,point,run.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size),3,Color(0.025,0.026,0.022,alpha*.95))
		var pigment: Color=run.get("color",Color(0.96,0.91,0.79))
		pigment.a*=alpha
		draw_string(face,point,run.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size),pigment)

func _ink(value: String, colour: Color, point: Vector2, size_value: int) -> void:
	if RubyReadings.contains_kanji(value):
		var width: float=minf(520,battle.field_rect.size.x-16)
		var layout: Dictionary=annotated_text_layout(value,size_value)
		var origin: Vector2=Vector2(clampf(point.x-width*.5,3,maxf(3,battle.field_rect.size.x-width-3)),3)
		for run in layout.runs:
			var face: Font=GameFonts.reading() if run.role=="reading" else GameFonts.body()
			draw_string_outline(face,origin+run.position,run.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size),1,Color(0.025,0.026,0.022,colour.a*.85))
			var pigment: Color=run.get("color",colour)
			pigment.a*=colour.a
			draw_string(face,origin+run.position,run.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size),pigment)
		return
	var face: Font = font if font!=null else ThemeDB.fallback_font
	var width: float = face.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_value).x
	point.x = clampf(point.x-width*0.5,3,maxf(3,battle.field_rect.size.x-width-3))
	point.y = clampf(point.y,face.get_ascent(size_value)+3,battle.field_rect.size.y-face.get_descent(size_value)-3)
	draw_string_outline(face,point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_value,1,Color(0.025,0.026,0.022,colour.a*0.85))
	draw_string(face,point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_value,colour)

func _direction(mark: Dictionary, point: Vector2) -> Vector2:
	var normalized_source: Vector2 = _point(mark.get("source",Vector2(-1,-1)))
	var source: Vector2 = _body(normalized_source,mark.get("meta",{}),true) if _valid(normalized_source) else point-Vector2(12,4)
	var result: Vector2 = (point-source).normalized()
	return result if result.length_squared()>0.1 else Vector2.RIGHT

func _draw_projectiles() -> void:
	for shot in battle.projectiles:
		if not _valid(shot.position) or not _valid(shot.targetPos): continue
		var hostile: bool = str(shot.get("victimSide", "enemy")) == "friendly"
		var info: Dictionary = {"unitType":str(shot.type),"side":"enemy" if hostile else "friendly","actorId":int(shot.get("sourceId",-1)),"victimId":int(shot.get("targetId",-1)),"victimSide":"friendly" if hostile else "enemy"}
		var point: Vector2
		var destination: Vector2
		if not battle.three_d_enabled and battle.painted_actors.is_ready():
			var source_offset: Vector2=_painted_actor_offset(info,true)
			var target_offset: Vector2=_painted_actor_offset(info,false)
			var body_offset: Vector2=Vector2(0,battle.painted_actors.body_height_screen*clampf(battle.field_rect.size.y/620.0,.65,1.5)*.52)
			point=_ground(shot.position)+source_offset-body_offset
			destination=_ground(shot.targetPos)+target_offset-body_offset
			var departure: Vector2 = shot.get("sourcePosition",shot.position)
			var length: float = departure.distance_to(shot.targetPos)
			var phase: float = clampf(departure.distance_to(shot.position)/maxf(.000001,length),0,1)
			point += (target_offset-source_offset)*phase
		else:
			point=_body(shot.position,info,true)
			destination=_body(shot.targetPos,info,false)
		var direction: Vector2 = (destination-point).normalized()
		var scale_value: float = _size_scale(shot.position)
		if str(shot.type) in ["gunner", "enemy_gunner"]:
			_line(point-direction*7*scale_value,point,Color(0.88,0.82,0.68,0.75),1.15)
		else:
			var tail: Vector2 = point-direction*11*scale_value
			_line(tail,point,Color(0.17,0.13,0.08,0.95),2.1*scale_value)
			_line(tail,point,Color(0.80,0.69,0.48,0.90),0.8*scale_value)
			_line(point-direction*2*scale_value,point,Color(0.86,0.87,0.81,0.9),1.5*scale_value)
			_line(tail-direction.orthogonal()*2*scale_value,tail+direction*3*scale_value,Color(0.88,0.86,0.76,0.78),0.9)
			_line(tail+direction.orthogonal()*2*scale_value,tail+direction*3*scale_value,Color(0.88,0.86,0.76,0.78),0.9)
			if (_skill_flag(shot,"fireArrow") or _effect_kind(shot)=="fire_arrow") and _authorized(shot,["archer_fire"],3):
				# Fire follows the actual arrow; this never invents a barrage.
				_puff(point,Vector2(3.3,2.0)*scale_value,Color(1.0,.47,.15,.57))
				_line(point-direction*3*scale_value,point+direction*1.2*scale_value,Color(1.0,.81,.38,.91),1.4*scale_value)

func _draw_mark(mark: Dictionary) -> void:
	var t: float = clampf(float(mark.age)/float(mark.life),0,1)
	var alpha: float = (1-t)*(1-t)
	var point: Vector2 = _body(mark.point,mark.get("meta",{}),bool(mark.get("sourceActor",str(mark.kind) in ["muzzle","smoke","release","fire_release","guard","dash","prayer","rally","braced_release"])))
	var scale_value: float = _size_scale(mark.point)
	var direction: Vector2 = _direction(mark,point)
	match str(mark.kind):
		"ninja_charge_fuse":
			# A small attached packet and shortening fuse, without a HUD panel.
			var packet: Vector2=point+Vector2(3,1)*scale_value
			_puff(packet,Vector2(3,2.5)*scale_value,Color(.18,.13,.08,.86))
			_line(packet+Vector2(-2,-1)*scale_value,packet+Vector2(2,1)*scale_value,Color(.66,.47,.24,.9),1.2*scale_value)
			var fuse: Vector2=packet+Vector2(1,-2)*scale_value
			var spark: Vector2=fuse+Vector2(2,-4*(1-t))*scale_value
			_line(fuse,spark,Color(.65,.48,.24,.9),.8*scale_value)
			_puff(spark,Vector2(1.5,1.5)*scale_value,Color(.97,.65,.24,.78))
		"ninja_charge_burst":
			_puff(point,Vector2(5+12*t,4+8*t)*scale_value,Color(.36,.29,.20,alpha*.75))
			_puff(point,Vector2(4+5*t,3+4*t)*scale_value,Color(.99,.69,.29,alpha*.65))
			for index in range(6):
				var ray: Vector2=Vector2.RIGHT.rotated(float(index)*TAU/6.0+.24)
				_line(point+ray*(2+4*t)*scale_value,point+ray*(6+11*t)*scale_value,Color(.90,.73,.43,alpha*.78),1.1*scale_value)
		"ninja_combo_cut", "samurai_counter_cut":
			var index: int=int(mark.get("hitIndex",0))
			var axis: Vector2=direction.rotated(-.65 if index==0 else .65 if index==1 else .0)
			_line(point-axis*(8-3*t)*scale_value,point+axis*(5+3*t)*scale_value,Color(.96,.92,.78,alpha*.86),1.3*scale_value)
			_line(point-axis*5*scale_value,point-axis*8*scale_value,Color(.31,.27,.21,alpha*.65),1.8*scale_value)
		"ninja_shrapnel_contact":
			for side in [-1.0,1.0]:
				var ray: Vector2=direction.rotated(side*.48)
				_line(point-ray*(4+4*t)*scale_value,point-ray*(1+3*t)*scale_value,Color(.86,.75,.55,alpha*.85),1.0*scale_value)
		"emplacement_alert":
			var ground: Vector2 = _ground(mark.point)
			for ring in range(2):
				var radius: float = (12.0 + t * 22.0 + ring * 6.0) * scale_value
				draw_arc(ground, radius, 0, TAU, 40, Color(.96,.24,.17,alpha*.85), 2.2*scale_value, true)
		"heal":
			var origin: Vector2 = _body(mark.source,mark.meta,true)
			var destination: Vector2 = _body(mark.point,mark.meta)
			var phase: float = smoothstep(0.0,.7,t)
			var paper: Vector2 = origin.lerp(destination,phase)+Vector2(0,-sin(phase*PI)*5*scale_value)
			# A quiet paper/cord link corresponds to one actual HP gain.
			_line(origin,paper,Color(.90,.85,.68,alpha*.46),.75*scale_value)
			var corners: PackedVector2Array = PackedVector2Array([paper+Vector2(-2.5,-4)*scale_value,paper+Vector2(2.5,-3)*scale_value,paper+Vector2(2,4)*scale_value,paper+Vector2(-2.2,3)*scale_value])
			for i in range(corners.size()): corners[i]=_clip_point(corners[i])
			draw_colored_polygon(corners,Color(.95,.91,.77,alpha*.88))
			_line(paper-Vector2(0,2)*scale_value,paper+Vector2(0,2)*scale_value,Color(.48,.32,.19,alpha*.8),.8)
			if t>.50:
				_line(destination-Vector2(0,3)*scale_value,destination+Vector2(0,3)*scale_value,Color(.96,.90,.67,alpha),1.0)
				_line(destination-Vector2(3,0)*scale_value,destination+Vector2(3,0)*scale_value,Color(.96,.90,.67,alpha),1.0)
		"fire_release", "ember":
			_puff(point,Vector2(3.4,2.2)*scale_value,Color(1.0,.53,.22,alpha*.48))
			for i in range(2):
				var ember: Vector2 = point+Vector2(float(i)*2-1,-t*(5+i*2))*scale_value
				_line(ember,ember+Vector2(.8,-1.3)*scale_value,Color(.98,.76,.39,alpha*.82),.9)
		"prayer", "rally":
			for side in [-1.0,1.0]:
				var paper: Vector2 = point+Vector2(side*4,-2-3*t)*scale_value
				_line(paper-Vector2(0,3)*scale_value,paper+Vector2(0,3)*scale_value,Color(.92,.87,.72,alpha*.87),2.0*scale_value)
		"barrage_contact":
			for side in [-1.0,1.0]:
				var edge: Vector2 = point+direction.orthogonal()*side*4*scale_value
				_line(edge-direction*3*scale_value,edge+direction*3*scale_value,Color(.83,.81,.68,alpha*.68),1.0)
		"pierce":
			_line(point-direction*8*scale_value,point+direction*7*scale_value,Color(.90,.89,.74,alpha*.80),1.1*scale_value)
			_line(point-direction*8*scale_value,point-direction*11*scale_value,Color(.20,.20,.16,alpha*.7),1.8*scale_value)
		"brace", "brace_contact", "rear_rank_contact", "braced_release":
			var axis: Vector2=direction.orthogonal()
			_line(point-direction*6*scale_value,point+direction*5*scale_value,Color(.90,.87,.71,alpha*.78),1.1*scale_value)
			_line(point-axis*3*scale_value,point+axis*3*scale_value,Color(.69,.66,.51,alpha*.72),1.2*scale_value)
		"parry":
			for side in [-1.0,1.0]:
				var axis: Vector2=direction.rotated(side*.65)
				_line(point-axis*4*scale_value,point+axis*4*scale_value,Color(.95,.91,.73,alpha*.86),1.2*scale_value)
		"ward_grant", "ward_consume":
			var spread: float=1.0+t*.45 if str(mark.kind)=="ward_consume" else 1.0
			for side in [-1.0,1.0]:
				var edge: Vector2=point+Vector2(side*4*spread,0)*scale_value
				_line(edge-Vector2(0,4)*scale_value,edge+Vector2(0,4)*scale_value,Color(.88,.88,.70,alpha*.78),1.4*scale_value)
		"impact_contact":
			for side in [-1.0,0.0,1.0]:
				var axis: Vector2=direction.rotated(side*.6)
				_line(point+axis*2*scale_value,point+axis*(8+4*t)*scale_value,Color(.91,.78,.55,alpha*.78),1.2*scale_value)
		"armor_break":
			var plate: PackedVector2Array = PackedVector2Array()
			for offset in [Vector2(-4,-3),Vector2(0,-4),Vector2(1,0),Vector2(-1,2),Vector2(3,4)]: plate.append(_clip_point(point+offset*scale_value))
			draw_polyline(plate,Color(.89,.77,.55,alpha*.92),1.3*scale_value,true)
		"sweep", "decisive_cut":
			var arc: PackedVector2Array = PackedVector2Array()
			var reach: float = 11.0 if str(mark.kind)=="decisive_cut" else 9.0
			for i in range(9):
				arc.append(_clip_point(point+direction.rotated(-.85+float(i)/8.0*1.55)*(reach-1.0*sin(float(i)/8.0*PI))*scale_value-direction*4*scale_value))
			draw_polyline(arc,Color(.96,.93,.79,alpha*.79),1.4*scale_value,true)
		"guard":
			var outline: PackedVector2Array = PackedVector2Array()
			for offset in [Vector2(-4,-3),Vector2(0,-5),Vector2(4,-3),Vector2(3,2),Vector2(0,5),Vector2(-3,2)]: outline.append(_clip_point(point+offset*scale_value))
			draw_polyline(outline,Color(.89,.86,.66,alpha*.70),1.0*scale_value,true)
		"dash":
			_line(point-direction*9*scale_value,point-direction*3*scale_value,Color(.67,.61,.46,alpha*.52),1.0)
		"muzzle":
			direction = (_body(mark.target,mark.meta)-point).normalized()
			var origin: Vector2 = point+direction*6*scale_value
			_puff(origin,Vector2(6,4)*scale_value,Color(0.99,0.74,0.32,alpha*0.68))
			_line(origin-direction*2,origin+direction*(7-3*t)*scale_value,Color(1,0.92,0.69,alpha),2.0*scale_value)
		"release":
			# A tiny string-release glint; the visible arrow carries the shot.
			direction = (_body(mark.target,mark.meta)-point).normalized()
			_line(point-direction.orthogonal()*3*scale_value,point+direction*3*scale_value,Color(0.85,0.84,0.73,alpha*0.42),0.8)
		"cut":
			var curve: PackedVector2Array = PackedVector2Array()
			for index in range(7):
				var phase: float = float(index)/6
				var offset: Vector2 = direction.rotated(-0.54+phase*0.85)*(5.5+sin(phase*PI)*2.5)*scale_value
				curve.append(_clip_point(point+offset-direction*4*scale_value))
			draw_polyline(curve,Color(0.80,0.82,0.75,alpha*0.48),1.1*scale_value,true)
		"thrust":
			_line(point-direction*7*scale_value,point+direction*3*scale_value,Color(0.77,0.79,0.72,alpha*0.40),1.0*scale_value)
		"steel":
			if t<0.3: _puff(point,Vector2(3,2)*scale_value,Color(1,0.90,0.67,alpha*0.70))
			for index in range(3):
				var ray: Vector2 = (-direction).rotated(-0.8+index*0.65+float(int(mark.seed)%5)*0.12)
				var start: Vector2 = point+ray*(1+t*7)*scale_value
				_line(start,start+ray*(3.5*(1-t))*scale_value,Color(0.94,0.78,0.50,alpha*0.85),0.85*scale_value)
		"contact":
			_puff(point+direction*t*3*scale_value,Vector2(3.4,2.1)*scale_value,Color(0.59,0.43,0.30,alpha*0.56))
			if t<0.35: _line(point-direction*2*scale_value,point+direction*2*scale_value,Color(0.86,0.79,0.64,alpha*0.64),1.15)
		"number":
			var offset_x: float = float(int(mark.seed)%3-1)*4
			_ink(str(mark.text),Color(0.96,0.86,0.69,1-t) if bool(mark.enemyVictim) else Color(0.94,0.48,0.38,1-t),point+Vector2(offset_x,-8-t*13),15)
		"reward":
			_ink(str(mark.text),Color(0.79,0.73,0.54,(1-t)*0.83),_ground(mark.point)+Vector2(13,-8-t*8),13)
		"smoke":
			direction = (_body(mark.target,mark.meta)-point).normalized()
			for index in range(3):
				var drift: Vector2 = direction*(5+index*2)+Vector2(1+t*(4+index),-t*(7+index*2))
				_puff(point+drift*scale_value,Vector2(3.5+t*5,2.6+t*4)*scale_value,Color(0.71,0.70,0.65,alpha*0.24))
		"deploy", "fall", "charge", "objective":
			var ground: Vector2 = _ground(mark.point)
			var charge: bool = str(mark.kind) in ["charge","objective"]
			for index in range(3 if charge else 2):
				var offset: Vector2 = Vector2((index-1 if charge else index-0.5)*(4+t*4),-1+t*0.8)
				_puff(ground+offset*scale_value,Vector2((5.5 if charge else 3.5)+t*3,2.0+t*1.2)*scale_value,Color(0.55,0.47,0.33,alpha*(0.38 if charge else 0.23)))

func _draw() -> void:
	if not is_instance_valid(battle) or battle.field_rect.size.x<=1: return
	# Lazily build offsets only when an actual mark/projectile needs them.
	_offset_frame=-1
	# Soil/smoke sit behind contacts; restrained text is always above them.
	for mark in marks:
		if str(mark.kind) in ["smoke","fall","deploy","charge","objective"]: _draw_mark(mark)
	_draw_projectiles()
	for mark in marks:
		if str(mark.kind) not in ["smoke","fall","deploy","charge","objective","number","reward"]: _draw_mark(mark)
	for mark in marks:
		if str(mark.kind) in ["number","reward"]: _draw_mark(mark)
	if danger_clock>0:
		var alpha: float = danger_clock/0.45
		draw_rect(Rect2(Vector2.ONE*2,battle.field_rect.size-Vector2.ONE*4),Color(0.70,0.18,0.12,alpha*0.34),false,2)
	if banner_clock>0:
		var alpha: float = minf(1,banner_clock*3)
		_draw_banner(alpha)

func diagnostics() -> Dictionary:
	var kinds: Dictionary = {}
	for mark in marks: kinds[str(mark.kind)] = int(kinds.get(str(mark.kind),0))+1
	return {"events":event_counts.duplicate(true),"emitted":emitted_counts.duplicate(true),"activeKinds":kinds,"activeMarks":marks.size(),"maxMarks":MAX_MARKS,"maxNumbers":MAX_NUMBERS,"duplicateEvents":duplicate_events,"droppedMarks":dropped_marks,"feedbackClock":feedback_clock,"dangerClock":danger_clock,"emplacementPulseTargets":_emplacement_pulses.size(),"projectiles":battle.projectiles.size() if is_instance_valid(battle) else 0,"paused":paused or (is_instance_valid(battle) and bool(battle.paused)),"rendererProjection":is_instance_valid(troop_renderer),"scope":"Committed release/actual HP loss only; weapon-specific contacts, bounded selected/large-hit numbers and one aggregated reward. Actual emplacement HP loss adds a bounded location pulse, edge danger and coalesced notice. Cosmetic clock follows battle speed and explicit pause. Combat, rewards and actor transforms are read-only."}
