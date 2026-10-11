extends Node
## Short licensed Foley at actual battle events. This node owns only its SFX bus;
## it never changes the stage music, TTS, game state, save data or battle clock.

const SOURCES_PATH := "res://native/sfx_sources.json"
const BattlefieldPresentation = preload("res://native/battlefield_presentation.gd")
const POOL_SIZE := 12
const SAME_EFFECT_LIMIT := 3
const DEFAULT_VOLUME := 0.8
const DUCK_DB := -10.0
const SETTINGS := {
	"support_drum": {"clips":["taiko_march"],"gain":-8.0,"gap":1.0,"priority":4},
	"bow": {"clips":["bow_release_a","bow_release_b"],"gain":-8.0,"gap":0.040,"priority":2},
	"matchlock": {"clips":["matchlock_a","matchlock_b"],"gain":-13.0,"gap":0.080,"priority":3},
	"swing": {"clips":["sword_swing_a","sword_swing_b"],"gain":-14.0,"gap":0.050,"priority":1},
	"metal": {"clips":["metal_hit_a","metal_hit_b"],"gain":-8.0,"gap":0.050,"priority":2},
	"wood": {"clips":["wood_hit_a","wood_hit_b"],"gain":-10.0,"gap":0.050,"priority":2},
	"body": {"clips":["body_hit_a","body_hit_b"],"gain":-12.0,"gap":0.050,"priority":1},
	"footstep": {"clips":["footstep_a","footstep_b"],"gain":-23.0,"gap":0.150,"priority":0,"limit":2},
	"hoof": {"clips":["hoof_step"],"gain":-20.0,"gap":0.180,"priority":0,"limit":2},
	"charge": {"clips":["horse_charge"],"gain":-10.0,"gap":0.160,"priority":4},
	"recruit": {"clips":["recruit"],"gain":-6.0,"gap":0.070,"priority":7,"ui":true},
	"deploy": {"clips":["deploy"],"gain":-6.0,"gap":0.070,"priority":7,"ui":true},
	"click": {"clips":["ui_click"],"gain":-9.0,"gap":0.055,"priority":6,"ui":true},
	"kill": {"clips":["kill"],"gain":-13.0,"gap":0.090,"priority":3},
	"ally_down": {"clips":["ally_down"],"gain":-10.0,"gap":0.140,"priority":4},
	"objective": {"clips":["objective_hit"],"gain":-8.0,"gap":0.180,"priority":5},
	"wavebegin": {"clips":["wave_start"],"gain":-8.0,"gap":0.350,"priority":8,"ui":true},
	"waveend": {"clips":["wave_clear"],"gain":-9.0,"gap":0.350,"priority":8,"ui":true},
	"victory": {"clips":["victory"],"gain":-6.0,"gap":1.0,"priority":9,"ui":true},
	"defeat": {"clips":["defeat"],"gain":-6.0,"gap":1.0,"priority":9,"ui":true},
	"pain_voice": {"clips":["pain_reaction_a","pain_reaction_b"],"gain":-12.0,"gap":1.4,"priority":4,"limit":1},
	"death_voice": {"clips":["death_reaction_a","death_reaction_b"],"gain":-11.0,"gap":1.4,"priority":4,"limit":1},
}

var enabled := true
var volume := DEFAULT_VOLUME
var paused := false
var voice_active := false
var field_rect := Rect2()
var presentation_mirrored: bool = false
var is_ready := false
var players: Array[AudioStreamPlayer2D] = []
var streams: Dictionary = {}
var missing: Array[String] = []
var played := 0
var rejected := 0
var received := 0
var play_counts: Dictionary = {}
var last_play: Dictionary = {}
var slots: Array[Dictionary] = []
var last_effect := ""
var last_clip := ""
var last_position := Vector2.ZERO
var bus_name := ""
var bus_index := -1
var _duck := 0.0
var _clock := 0.0
var _cursor: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _terminal_token := ""
var _seen_ids: Dictionary = {}
var _seen_order: Array[String] = []
var _shutdown := false
var _voice_hit_count := 0
var _voice_death_count := 0
var _voice_issued := 0

func _ready() -> void:
	set_process(false)

func setup(initial_enabled: bool = true, initial_volume: float = DEFAULT_VOLUME) -> bool:
	if is_ready:
		set_enabled(initial_enabled)
		set_volume(initial_volume)
		return true
	if _shutdown or not is_inside_tree():
		return false
	missing.clear()
	var library = JSON.parse_string(FileAccess.get_file_as_string(SOURCES_PATH))
	if not library is Dictionary:
		missing.append(SOURCES_PATH)
		return false
	for clip in library.get("clips",[]):
		var path := str(clip.get("path",""))
		var resource = load(path) if ResourceLoader.exists(path) else null
		# Source tests can load the raw WAV before editor import. Exported builds
		# resolve imported AudioStreamWAV resources through the standard loader.
		if resource == null and FileAccess.file_exists(path):
			resource = AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes(path),{"compress/mode":0})
		if resource is AudioStreamWAV:
			resource.loop_mode = AudioStreamWAV.LOOP_DISABLED
			streams[str(clip.id)] = resource
		else:
			missing.append(path)
	for recipe in SETTINGS.values():
		for id in recipe.clips:
			if not streams.has(id) and not missing.has(str(id)):
				missing.append(str(id))
	if not missing.is_empty():
		return false
	_rng.randomize()
	bus_name = "BattleSFX_%d" % get_instance_id()
	AudioServer.add_bus()
	bus_index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index,bus_name)
	AudioServer.set_bus_send(bus_index,"Master")
	var limiter := AudioEffectLimiter.new()
	limiter.threshold_db = -4.0
	limiter.ceiling_db = -3.0
	AudioServer.add_bus_effect(bus_index,limiter)
	for index in POOL_SIZE:
		var player := AudioStreamPlayer2D.new()
		player.name = "BattleSound_%02d" % index
		player.bus = bus_name
		player.max_polyphony = 1
		player.max_distance = 100000.0
		player.attenuation = 0.0
		player.panning_strength = 0.65
		add_child(player)
		players.append(player)
		slots.append({})
		player.finished.connect(_on_finished.bind(index))
	is_ready = true
	set_enabled(initial_enabled)
	set_volume(initial_volume)
	set_process(true)
	return true

func set_field_rect(rect: Rect2) -> void:
	field_rect = rect

func set_presentation_mirrored(value: bool) -> void:
	presentation_mirrored=value

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		stop_all()
	_apply_bus_gain()

func set_volume(value: float) -> void:
	volume = clampf(value,0.0,1.0)
	_apply_bus_gain()

func set_paused(value: bool) -> void:
	paused = value
	for index in players.size():
		players[index].stream_paused = paused and not bool(slots[index].get("ui",false))

func set_voice_active(value: bool) -> void:
	if value and not voice_active:
		# A reaction that began one frame before an announcement must also stop.
		for index in players.size():
			if str(slots[index].get("effect","")) in ["pain_voice","death_voice"]:
				players[index].stop()
				players[index].stream = null
				slots[index] = {}
	voice_active = value

func consume_finish(result: Dictionary) -> bool:
	var event := result.duplicate()
	event["action"] = "victory" if bool(result.get("victory",result.get("won",false))) else "defeat"
	return consume_event(event)

func consume_event(event: Dictionary) -> bool:
	received += 1
	if not is_ready or _shutdown or not enabled or volume <= 0.0:
		return _reject()
	var action := str(event.get("action",event.get("type","")))
	var effect := _resolve_effect(action,event)
	if effect.is_empty():
		return _reject()
	var recipe: Dictionary = SETTINGS[effect]
	var is_ui := bool(recipe.get("ui",false))
	if paused and not is_ui:
		return _reject()
	# Event IDs are optional. They protect effects when a caller forwards the
	# same real event twice; bounded memory also makes a long battle safe.
	var event_id := str(event.get("eventId",""))
	if not event_id.is_empty() and _seen_ids.has(event_id):
		return _reject()
	var actor := str(event.get("actorId","system"))
	var actor_key := effect + ":" + actor
	var gap := float(recipe.gap)
	var actor_gap := maxf(gap,0.26 if effect in ["footstep","hoof"] else 0.085)
	if _clock - float(last_play.get(effect,-100.0)) < gap or _clock - float(last_play.get(actor_key,-100.0)) < actor_gap:
		return _reject()
	if effect in ["victory","defeat"]:
		var token := str(event.get("mapId","")) + ":" + str(event.get("battleId",event.get("time",""))) + ":" + effect
		if token == _terminal_token:
			return _reject()
		_terminal_token = token
	if effect == "wavebegin" and int(event.get("wave",0)) == 1:
		_terminal_token = ""
	var active_same := 0
	for index in players.size():
		if _slot_active(index) and str(slots[index].get("effect","")) == effect:
			active_same += 1
	if active_same >= int(recipe.get("limit",SAME_EFFECT_LIMIT)):
		return _reject()
	var priority := int(recipe.priority)
	var slot := _find_slot(priority)
	if slot < 0:
		return _reject()
	var variants: Array = recipe.clips
	var variant := int(_cursor.get(effect,0)) % variants.size()
	_cursor[effect] = variant + 1
	var clip_id := str(variants[variant])
	var point := _event_position(event,is_ui)
	var player := players[slot]
	player.stop()
	player.stream = streams[clip_id]
	player.position = point
	player.volume_db = float(recipe.gain)
	player.pitch_scale = 1.0 if is_ui else _rng.randf_range(0.96,1.04)
	player.stream_paused = false
	slots[slot] = {"effect":effect,"clip":clip_id,"ui":is_ui,"priority":priority,"started":_clock,"position":point}
	player.play()
	played += 1
	play_counts[effect] = int(play_counts.get(effect,0)) + 1
	last_play[effect] = _clock
	last_play[actor_key] = _clock
	last_effect = effect
	last_clip = clip_id
	last_position = point
	if not event_id.is_empty():
		_seen_ids[event_id] = true
		_seen_order.append(event_id)
		if _seen_order.size() > 256:
			_seen_ids.erase(_seen_order.pop_front())
	_maybe_voice(action,event)
	return true

func _maybe_voice(action: String, event: Dictionary) -> void:
	# Human recordings are occasional reactions, not dialogue or a generated
	# voice. The educational Japanese voice always takes precedence.
	if voice_active or action not in ["hit","killed"]:
		return
	var effect := ""
	if action == "hit" and float(event.get("damage",0.0)) >= 12.0:
		_voice_hit_count += 1
		if _voice_hit_count % 5 == 0: effect = "pain_voice"
	elif action == "killed":
		_voice_death_count += 1
		if _voice_death_count % 3 == 0: effect = "death_voice"
	if effect.is_empty() or _clock - float(last_play.get("human_reaction",-100.0)) < 1.4:
		return
	for index in players.size():
		if _slot_active(index) and str(slots[index].get("effect","")) in ["pain_voice","death_voice"]:
			return
	var recipe: Dictionary = SETTINGS[effect]
	var slot := _find_slot(int(recipe.priority))
	if slot < 0: return
	var variant: int = int(_cursor.get(effect,0)) % recipe.clips.size()
	_cursor[effect] = variant + 1
	var clip_id := str(recipe.clips[variant])
	var player := players[slot]
	player.stop()
	player.stream = streams[clip_id]
	player.position = _event_position({"position":event.get("victimPosition",event.get("position",{}))},false)
	player.volume_db = float(recipe.gain)
	player.pitch_scale = 1.0 # preserve the real performer's voice
	player.stream_paused = false
	slots[slot] = {"effect":effect,"clip":clip_id,"ui":false,"priority":int(recipe.priority),"started":_clock,"position":player.position}
	player.play()
	played += 1
	_voice_issued += 1
	play_counts[effect] = int(play_counts.get(effect,0)) + 1
	last_play["human_reaction"] = _clock

func _resolve_effect(action: String, event: Dictionary) -> String:
	var weapon := str(event.get("weapon",""))
	var unit_type := str(event.get("unitType",""))
	match action:
		"shot":
			if weapon == "bow" or (weapon.is_empty() and unit_type == "archer"): return "bow"
			if weapon == "matchlock" or (weapon.is_empty() and unit_type == "gunner"): return "matchlock"
			if weapon == "charge" or (weapon.is_empty() and unit_type == "commander"): return ""
			return "swing"
		"hit":
			if weapon == "charge": return "" # charge_impact already supplies the actual collision
			if float(event.get("damage",0.0)) <= 0.0: return ""
			var victim_type := str(event.get("victimType",event.get("enemyKind","")))
			if victim_type in ["shield","heavy","commander","enemy_heavy","armored"]: return "metal"
			if weapon in ["spear","staff"]: return "wood"
			if weapon in ["katana","naginata"]: return "metal"
			return "body"
		"charge_impact": return "charge" if float(event.get("damage",0.0)) > 0.0 else ""
		"footstep": return "hoof" if unit_type == "commander" and str(event.get("side","friendly")) != "enemy" else "footstep"
		"killed": return "ally_down" if str(event.get("victimSide","enemy")) == "friendly" else "kill"
		"objective_hit": return "objective" if float(event.get("damage",0.0)) > 0.0 else ""
		"recruit", "recruited": return "recruit"
		"deploy", "placed", "tower_placed": return "deploy"
		"wavebegin", "wave": return "wavebegin"
		"waveend": return "waveend"
		"victory": return "victory"
		"defeat": return "defeat"
		"learning-support": return "support_drum" if str(event.get("supportKind",""))=="march_drum" else ""
		"ui_click", "ui_select": return "click"
	return ""

func _event_position(event: Dictionary, centered: bool) -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	if centered:
		return viewport_size * 0.5
	var raw = event.get("position",event.get("victimPosition",{}))
	var normalized := Vector2(0.5,0.5)
	if raw is Vector2:
		normalized = raw
	elif raw is Dictionary and raw.has("x") and raw.has("y"):
		normalized = Vector2(float(raw.x),float(raw.y))
	var rect := field_rect if field_rect.size.x > 0 and field_rect.size.y > 0 else Rect2(Vector2.ZERO,viewport_size)
	normalized = normalized.clamp(Vector2.ZERO,Vector2.ONE)
	normalized = BattlefieldPresentation.to_view(normalized,presentation_mirrored)
	return rect.position + rect.size * normalized

func _find_slot(priority: int) -> int:
	for index in players.size():
		if not _slot_active(index):
			return index
	var candidate := -1
	var oldest := INF
	for index in players.size():
		var old_priority := int(slots[index].get("priority",0))
		if old_priority <= priority and float(slots[index].get("started",0.0)) < oldest:
			oldest = float(slots[index].get("started",0.0))
			candidate = index
	return candidate

func _slot_active(index: int) -> bool:
	return players[index].playing or (players[index].stream_paused and players[index].stream != null)

func _reject() -> bool:
	rejected += 1
	return false

func _on_finished(index: int) -> void:
	if index < players.size():
		players[index].stream = null
		slots[index] = {}

func _process(delta: float) -> void:
	_clock += maxf(delta,0.0)
	var target := DUCK_DB if voice_active else 0.0
	var speed := 90.0 if voice_active else 26.0
	_duck = move_toward(_duck,target,speed * delta)
	_apply_bus_gain()
	# Only a bounded history is needed for each active actor; clean a long-run
	# cooldown map rather than retaining every past enemy forever.
	if last_play.size() > 512:
		for key in last_play.keys():
			if _clock - float(last_play[key]) > 3.0:
				last_play.erase(key)

func _apply_bus_gain() -> void:
	bus_index = AudioServer.get_bus_index(bus_name) if not bus_name.is_empty() else -1
	if bus_index < 0:
		return
	var db := linear_to_db(maxf(volume,0.00001)) + _duck
	AudioServer.set_bus_volume_db(bus_index,db)
	AudioServer.set_bus_mute(bus_index,not enabled or volume <= 0.0)

func stop_all() -> void:
	for index in players.size():
		players[index].stop()
		players[index].stream = null
		players[index].stream_paused = false
		slots[index] = {}
	last_play.clear()
	_terminal_token = ""
	_seen_ids.clear()
	_seen_order.clear()
	_voice_hit_count = 0
	_voice_death_count = 0

func shutdown() -> void:
	stop_all()
	_shutdown = true
	is_ready = false
	set_process(false)
	streams.clear()
	_seen_ids.clear()
	_seen_order.clear()

func _exit_tree() -> void:
	shutdown()
	var owned_bus := AudioServer.get_bus_index(bus_name)
	if owned_bus > 0:
		AudioServer.remove_bus(owned_bus)
	bus_index = -1

func diagnostics() -> Dictionary:
	bus_index = AudioServer.get_bus_index(bus_name) if not bus_name.is_empty() else -1
	var active_players := 0
	var combat_paused := 0
	var playing_clips: Array = []
	for index in players.size():
		if _slot_active(index):
			active_players += 1
			if players[index].stream_paused: combat_paused += 1
			playing_clips.append(slots[index].duplicate())
	return {"ready":is_ready,"enabled":enabled,"volume":volume,"paused":paused,"voiceActive":voice_active,"humanReactions":_voice_issued,"duckDb":_duck,"busName":bus_name,"busIndex":bus_index,"busDb":AudioServer.get_bus_volume_db(bus_index) if bus_index >= 0 else -80.0,"clips":streams.size(),"missing":missing.duplicate(),"poolSize":players.size(),"activePlayers":active_players,"pausedPlayers":combat_paused,"received":received,"played":played,"rejected":rejected,"playCounts":play_counts.duplicate(),"lastEffect":last_effect,"lastClip":last_clip,"lastPosition":last_position,"playingClips":playing_clips,"eventMemory":_seen_ids.size(),"cooldownMemory":last_play.size(),"shutdown":_shutdown}
