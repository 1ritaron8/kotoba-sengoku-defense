extends SceneTree
## Tiny isolated audio lifetime probe. No main scene, battle or persistence.
## Usage: -- mp3|ogg play-stop|load-only|switch|rapid|paused-stop|main-quit wait_seconds

var player: AudioStreamPlayer
var watched: Array = []
var mode: String = "play-stop"
var wait_seconds: float = 0.1
var format_name: String = "mp3"
var initial_objects: int = 0

func _initialize() -> void:
	call_deferred("run")

func observe_stream() -> void:
	var entry: Dictionary = {"resource":weakref(player.stream),"path":player.stream.resource_path}
	if player.has_stream_playback():
		entry["playback"] = weakref(player.get_stream_playback())
	watched.append(entry)

func run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size()>0: format_name=arguments[0]
	if arguments.size()>1: mode=arguments[1]
	if arguments.size()>2: wait_seconds=float(arguments[2])
	if mode=="main-quit":
		await test_main_quit()
		return
	var mp3: String = "res://assets/music/stages/basic-forest-yuruyakanakaze.mp3"
	var ogg: String = "res://assets/music/stages/basic-farm-otogi4.ogg"
	var path: String = mp3 if format_name=="mp3" else ogg
	initial_objects=int(Performance.get_monitor(Performance.OBJECT_COUNT))
	player=AudioStreamPlayer.new()
	player.volume_db=-80
	root.add_child(player)
	player.stream=load(path)
	player.stream.loop=true
	if mode!="load-only":
		player.play()
	observe_stream()
	if mode!="rapid":
		await create_timer(.1).timeout
	if mode=="paused-stop":
		player.stream_paused=true
	if mode in ["switch","rapid"]:
		player.stop()
		player.stream=load(ogg if format_name=="mp3" else mp3)
		player.play()
		observe_stream()
		if mode!="rapid": await create_timer(.1).timeout
	player.stop()
	player.stream=null
	if wait_seconds>0:
		await create_timer(wait_seconds).timeout
	player.queue_free()
	player=null
	await process_frame
	await process_frame
	var retained: Array = []
	for entry in watched:
		var stream_alive: bool = entry.resource.get_ref()!=null
		var playback_alive: bool = entry.has("playback") and entry.playback.get_ref()!=null
		retained.append({"path":entry.path,"resourceAlive":stream_alive,"playbackAlive":playback_alive})
	print("AUDIO_TEARDOWN ",JSON.stringify({"format":format_name,"mode":mode,"wait":wait_seconds,"timeSinceMix":AudioServer.get_time_since_last_mix(),"remaining":retained,"objectDelta":int(Performance.get_monitor(Performance.OBJECT_COUNT))-initial_objects}))
	quit(0)

func test_main_quit() -> void:
	var main: Node = load("res://native/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(.1).timeout
	player=main.player
	observe_stream()
	# Root owns this method. This probe calls the real close path without
	# overriding its wait or adding references to the music stream/playback.
	var started: int = Time.get_ticks_msec()
	await main._quit_game()
	print("MAIN_QUIT requested_close_ms=",Time.get_ticks_msec()-started," playing=",player.playing," stream_null=",player.stream==null)
