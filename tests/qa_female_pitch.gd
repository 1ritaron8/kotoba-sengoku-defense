extends SceneTree
## Real Dummy-driver bus PCM, retained in memory only. No reusable audio export.
## Verifies production routing, female F0 reduction, duration and male isolation.

const Announcer = preload("res://native/battle_announcer.gd")
const Narrator = preload("res://native/battle_narrator.gd")
const Director = preload("res://native/voice_director.gd")
const EXPECTED_PITCH := .86
const DOWNSAMPLE := 4
const PITCH_WINDOW := 512

var checks := 0
var failures: Array[String] = []
var observations: Array = []
var pitch_ratios: Array[float] = []
var female: Node
var male: Node
var director: Node
var finish_time_us: int = -1
var finish_mixer_frames: int = -1
var current_capture: AudioEffectCapture

func on_player_finished() -> void:
	finish_time_us=Time.get_ticks_usec()
	finish_mixer_frames=current_capture.get_pushed_frames() if current_capture!=null else -1

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("FEMALE PITCH: "+description)

func median(values: Array[float]) -> float:
	if values.is_empty(): return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	var middle := ordered.size()/2
	return ordered[middle] if ordered.size()%2==1 else (ordered[middle-1]+ordered[middle])*.5

func pcm_metrics(frames: PackedVector2Array, sample_rate: float) -> Dictionary:
	var peak := 0.0
	var energy := 0.0
	var first := -1
	var last := -1
	var finite := true
	for index in frames.size():
		var frame: Vector2 = frames[index]
		finite = finite and is_finite(frame.x) and is_finite(frame.y)
		var amplitude := maxf(absf(frame.x),absf(frame.y))
		peak = maxf(peak,amplitude)
		energy += frame.length_squared()*.5
		if amplitude>.0025:
			if first<0: first=index
			last=index
	return {"frames":frames.size(),"peak":peak,"rms":sqrt(energy/maxi(1,frames.size())),"finite":finite,"firstActiveFrame":first,"lastActiveFrame":last,"activeSpanSeconds":float(last-first+1)/sample_rate if first>=0 else 0.0}

func measured_envelope_delay(before: PackedVector2Array, after: PackedVector2Array, sample_rate: float) -> int:
	# Find the observed envelope delay without assuming the FFT implementation.
	var block_size := 256
	var before_energy: Array[float] = []
	var after_energy: Array[float] = []
	for frames in [before,after]:
		var envelope: Array[float] = []
		for start in range(0,frames.size()-1024,block_size):
			var energy := 0.0
			for index in range(start,start+1024): energy += frames[index].length_squared()
			envelope.append(energy/1024.0)
		if before_energy.is_empty(): before_energy=envelope
		else: after_energy=envelope
	var best_lag := 0
	var best_score := -1.0
	for lag in range(ceili(sample_rate*.1/block_size)):
		var product := 0.0
		var energy_a := 0.0
		var energy_b := 0.0
		for index in mini(before_energy.size(),after_energy.size()-lag):
			product += before_energy[index]*after_energy[index+lag]
			energy_a += before_energy[index]*before_energy[index]
			energy_b += after_energy[index+lag]*after_energy[index+lag]
		var score := product/sqrt(energy_a*energy_b) if energy_a*energy_b>0.0 else 0.0
		if score>best_score:
			best_score=score
			best_lag=lag
	return best_lag*block_size

func voiced_pitch(frames: PackedVector2Array, sample_rate: float, delay_frames: int = 0) -> Dictionary:
	# Cumulative-normalized difference minima in 46 ms voiced windows. This
	# independently observes the waveform period, not the effect's setting.
	var samples := PackedFloat64Array()
	samples.resize(frames.size()/DOWNSAMPLE)
	for index in samples.size():
		var total := 0.0
		for offset in DOWNSAMPLE:
			var frame: Vector2 = frames[index*DOWNSAMPLE+offset]
			total += (frame.x+frame.y)*.5
		samples[index]=total/DOWNSAMPLE
	var rate := sample_rate/DOWNSAMPLE
	var min_lag := maxi(2,floori(rate/650.0))
	var max_lag := floori(rate/80.0)
	var hop := roundi(rate*.035)
	var frequencies: Array[float] = []
	var confidence: Array[float] = []
	var window_hz: Dictionary = {}
	var initial_sample := delay_frames/DOWNSAMPLE
	for start in range(initial_sample,maxi(0,samples.size()-PITCH_WINDOW-max_lag),hop):
		var energy := 0.0
		for index in PITCH_WINDOW: energy += samples[start+index]*samples[start+index]
		if energy/PITCH_WINDOW<.00004: continue
		var difference := PackedFloat64Array()
		difference.resize(max_lag+1)
		var cumulative := 0.0
		for lag in range(1,max_lag+1):
			var distance := 0.0
			for index in PITCH_WINDOW:
				var value := samples[start+index]-samples[start+index+lag]
				distance += value*value
			cumulative += distance
			difference[lag]=distance*lag/cumulative if cumulative>0.0 else 1.0
		var selected := -1
		for lag in range(min_lag,max_lag):
			if difference[lag]<.20:
				selected=lag
				while selected<max_lag-1 and difference[selected+1]<difference[selected]: selected+=1
				break
		if selected<0: continue
		var denominator: float = difference[selected-1]-2.0*difference[selected]+difference[selected+1]
		var adjustment := .5*(difference[selected-1]-difference[selected+1])/denominator if absf(denominator)>.000001 else 0.0
		var frequency := rate/(selected+clampf(adjustment,-.5,.5))
		frequencies.append(frequency)
		confidence.append(1.0-difference[selected])
		window_hz[(start-initial_sample)/hop]=frequency
	return {"medianHz":median(frequencies),"voicedWindows":frequencies.size(),"medianConfidence":median(confidence),"windowHz":window_hz,"method":"80–650 Hz cumulative-normalized difference; 46 ms windows every 35 ms; first local minimum below 0.20; matched voiced windows aligned by observed envelope correlation; octave/voicing errors remain possible"}

func attach_captures(voice: Node) -> Array[AudioEffectCapture]:
	var index := AudioServer.get_bus_index(str(voice.bus_name))
	var before := AudioEffectCapture.new()
	var after := AudioEffectCapture.new()
	before.buffer_length=6.0
	after.buffer_length=6.0
	AudioServer.add_bus_effect(index,before,0)
	AudioServer.add_bus_effect(index,after)
	return [before,after]

func capture_clip(voice: Node, id: String, captures: Array[AudioEffectCapture]) -> Dictionary:
	director.stop()
	director._process(.25)
	voice.reset_battle()
	voice.set_volume(1.0)
	await create_timer(.12).timeout
	# Capture queues are cleared only while no recording is playing.
	AudioServer.lock()
	captures[0].clear_buffer()
	captures[1].clear_buffer()
	var start_mixer_frames := captures[0].get_pushed_frames()
	AudioServer.unlock()
	var discarded_before := captures[0].get_discarded_frames()+captures[1].get_discarded_frames()
	finish_time_us=-1
	finish_mixer_frames=-1
	current_capture=captures[0]
	var started_at := Time.get_ticks_usec()
	var duration: float = voice.streams[id].get_length()
	check(voice.play(id,{"eventId":"pcm-"+str(voice.voice_channel)+"-"+id}),"Actual native recording starts: "+id)
	var deadline := started_at+int((duration+1.0)*1000000.0)
	while finish_time_us<0 and Time.get_ticks_usec()<deadline:
		await create_timer(.02).timeout
	check(finish_time_us>started_at,"Real player finished signal observed: "+id)
	var playback_seconds := float(finish_time_us-started_at)/1000000.0 if finish_time_us>0 else -1.0
	# Dummy's worker has no hardware clock and wall time accumulates scheduler
	# overhead, including on the unmodified male voice. Observe mixer frames.
	var mixer_playback_seconds := float(finish_mixer_frames-start_mixer_frames)/AudioServer.get_mix_rate()
	check(absf(mixer_playback_seconds-duration)<.12,"Actual mixer-clock playback retains source duration within buffered completion latency: "+id)
	await create_timer(.12).timeout
	AudioServer.lock()
	var before_count := captures[0].get_frames_available()
	var after_count := captures[1].get_frames_available()
	var frame_count := mini(before_count,after_count)
	var before := captures[0].get_buffer(frame_count)
	var after := captures[1].get_buffer(frame_count)
	AudioServer.unlock()
	check(before_count==after_count,"Before/after effects produce the same mixer frame count: "+id)
	check(captures[0].get_discarded_frames()+captures[1].get_discarded_frames()==discarded_before,"No actual recording frames discarded: "+id)
	var rate := AudioServer.get_mix_rate()
	var before_metrics := pcm_metrics(before,rate)
	var after_metrics := pcm_metrics(after,rate)
	check(frame_count>rate*.5 and before_metrics.rms>.01 and after_metrics.rms>.01,"Both real PCM observations are audible: "+id)
	check(before_metrics.finite and after_metrics.finite,"Actual before/after PCM has finite values: "+id)
	check(float(after_metrics.peak)<=.75,"Real maximum-volume processed output retains peak headroom: "+id)
	check(absf(float(after_metrics.activeSpanSeconds)-float(before_metrics.activeSpanSeconds))<.08,"Audible waveform duration is retained within FFT transient latency: "+id)
	var envelope_delay := measured_envelope_delay(before,after,rate)
	var before_pitch := voiced_pitch(before,rate)
	var after_pitch := voiced_pitch(after,rate,envelope_delay)
	check(int(before_pitch.voicedWindows)>=3 and int(after_pitch.voicedWindows)>=3,"Independent pitch estimator observes several voiced windows: "+id)
	var matched_ratios: Array[float] = []
	for window in before_pitch.windowHz:
		if after_pitch.windowHz.has(window):
			matched_ratios.append(float(after_pitch.windowHz[window])/float(before_pitch.windowHz[window]))
	check(matched_ratios.size()>=3,"Several matching voiced windows permit independent before/after comparison: "+id)
	var ratio := median(matched_ratios)
	if str(voice.voice_channel)=="female":
		check(ratio>.78 and ratio<.95,"Actual female voiced F0 is lower by the configured approximate ratio: "+id)
		pitch_ratios.append(ratio)
	else:
		check(absf(ratio-1.0)<.02,"Actual male voiced F0 remains unchanged: "+id)
	before_pitch.erase("windowHz")
	after_pitch.erase("windowHz")
	var result := {"id":id,"channel":voice.voice_channel,"sourceSeconds":duration,"observedPlaybackSeconds":playback_seconds,"observedMixerPlaybackSeconds":mixer_playback_seconds,"wallTimeNote":"Dummy has no hardware clock; wall time is recorded without treating scheduling overhead as source time stretching.","before":before_metrics,"after":after_metrics,"beforePitch":before_pitch,"afterPitch":after_pitch,"matchedVoicedWindows":matched_ratios.size(),"observedEnvelopeDelaySeconds":float(envelope_delay)/rate,"f0Ratio":ratio,"semitoneChange":12.0*log(ratio)/log(2.0) if ratio>0.0 else 0.0,"sampleRate":rate,"playerPitchScale":voice.player.pitch_scale,"pcmExported":false}
	print("PITCH_PCM ",JSON.stringify(result))
	return result

func run() -> void:
	var profile := ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/battle-announcer/").to_lower()):
		quit(2)
		return
	check(DisplayServer.get_name()=="headless","CPU-only headless display")
	check(AudioServer.get_driver_name()=="Dummy","Observed native Dummy driver; no audio hardware")
	check(AudioServer.playback_speed_scale==1.0,"Actual global mixer playback speed remains 1.0")
	var initial_bus_count := AudioServer.bus_count
	director=Director.new()
	female=Announcer.new()
	male=Narrator.new()
	root.add_child(director)
	root.add_child(female)
	root.add_child(male)
	female.bind_director(director,"female")
	male.bind_director(director,"male")
	check(female.setup() and male.setup(),"Production female and male library setup succeeds")
	director.set_process(false)
	female.player.finished.connect(on_player_finished)
	male.player.finished.connect(on_player_finished)
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/announcements/manifest.json"))
	var male_library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/narration/manifest.json"))
	for clip in library.clips:
		check(FileAccess.get_sha256(str(clip.path)).to_upper()==str(clip.sha256),"Original female MP3 hash before capture: "+str(clip.id))
	for clip in male_library.clips:
		check(FileAccess.get_sha256(str(clip.path)).to_lower()==str(clip.sha256).to_lower(),"Original male WAV hash before capture: "+str(clip.id))
	check(female.player.pitch_scale==1.0 and male.player.pitch_scale==1.0,"Production players retain speed 1.0")
	var female_captures := attach_captures(female)
	var male_captures := attach_captures(male)
	for clip in library.clips:
		observations.append(await capture_clip(female,str(clip.id),female_captures))
	observations.append(await capture_clip(male,"honor",male_captures))
	var measured_ratio := median(pitch_ratios)
	check(pitch_ratios.size()==8 and absf(measured_ratio-EXPECTED_PITCH)<.035,"Aggregate independently measured female F0 ratio matches 0.86")
	for clip in library.clips:
		check(FileAccess.get_sha256(str(clip.path)).to_upper()==str(clip.sha256),"Original female MP3 hash after real processing: "+str(clip.id))
	for clip in male_library.clips:
		check(FileAccess.get_sha256(str(clip.path)).to_lower()==str(clip.sha256).to_lower(),"Original male WAV hash after female processing: "+str(clip.id))
	director.stop()
	female.queue_free()
	male.queue_free()
	director.queue_free()
	await process_frame
	await create_timer(.12).timeout
	check(AudioServer.bus_count==initial_bus_count,"Temporary capture and production buses release normally")
	var report := {"checks":checks,"failures":failures,"medianFemaleF0Ratio":measured_ratio,"medianFemaleSemitoneChange":12.0*log(measured_ratio)/log(2.0) if measured_ratio>0.0 else 0.0,"observations":observations,"scope":"Actual production AudioStreamPlayers and Dummy mixer; capture immediately before and after the production bus effects. Numeric measurements only, no PCM export, hardware, OS speech dispatch, GPU or campaign save. F0 estimates are objective signal observations, not an artistic auditory review."}
	var output := FileAccess.open("user://qa_female_pitch.json",FileAccess.WRITE)
	check(output!=null,"Isolated numerical report opens")
	report.checks=checks
	if output!=null:
		output.store_string(JSON.stringify(report,"  "))
		output.close()
	print("FEMALE_PITCH_QA ",JSON.stringify({"checks":checks,"failures":failures,"medianFemaleF0Ratio":measured_ratio}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
