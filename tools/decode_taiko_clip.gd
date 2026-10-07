extends SceneTree
## Decode an existing licensed MP3; only downmix, trim, level and fades.
func _initialize() -> void:
	var source: String="res://tools/sfx/source/taiko-drumloop-xinematix-491278.mp3"
	var mp3: AudioStreamMP3=AudioStreamMP3.new()
	mp3.data=FileAccess.get_file_as_bytes(source)
	var playback: AudioStreamPlayback=mp3.instantiate_playback()
	playback.start()
	var rate: int=int(AudioServer.get_mix_rate())
	var frames: PackedVector2Array=playback.mix_audio(1.0,int(rate*2.0))
	playback.stop()
	if frames.size()<rate: push_error("MP3 decode incomplete");quit(1);return
	var samples: PackedFloat32Array=[]
	var peak: float=0.0
	for frame in frames:
		var value: float=(frame.x+frame.y)*.5
		samples.append(value)
		peak=maxf(peak,absf(value))
	if peak<.001: push_error("Silent MP3 decode");quit(1);return
	var pcm: PackedByteArray=[]
	pcm.resize(samples.size()*2)
	var power: float=0.0
	var nonzero: int=0
	var output_peak: float=0.0
	for index in range(samples.size()):
		var fade: float=minf(1.0,float(index)/float(rate*.012))*minf(1.0,float(samples.size()-1-index)/float(rate*.080))
		var value: float=samples[index]*.78/peak*fade
		var integer: int=clampi(roundi(value*32767.0),-32768,32767)
		pcm.encode_s16(index*2,integer)
		power+=value*value
		output_peak=maxf(output_peak,absf(value))
		if integer!=0: nonzero+=1
	var wav: AudioStreamWAV=AudioStreamWAV.new()
	wav.format=AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate=rate
	wav.stereo=false
	wav.data=pcm
	var result: int=wav.save_to_wav("res://assets/sfx/taiko_march.wav")
	var report: Dictionary={"result":result,"seconds":float(samples.size())/rate,"sampleRate":rate,"channels":1,"bits":16,"peak":output_peak,"rms":sqrt(power/samples.size()),"nonzeroSamples":nonzero,"sha256":FileAccess.get_sha256("res://assets/sfx/taiko_march.wav")}
	var output: FileAccess=FileAccess.open("res://tools/sfx/taiko-edit-audit.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	quit(0 if result==OK else 1)
