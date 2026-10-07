extends "res://native/battle_narrator.gd"
## Original Japanese human recordings for fixed learning/notification messages.
## Uses the narrator's single-player queue and the shared male/female/TTS gate.
## This library does not read arbitrary words or the 120 stage-specific reports.

const NOTIFICATION_PITCH := 1.0

func _init() -> void:
	manifest_path = "res://assets/announcements/manifest.json"
	voice_channel = "female"

func _configure_voice_bus(_index: int) -> void:
	# Use the new performer's original recorded voice. The inherited output
	# limiter remains; no pitch/formant processing or time stretching is added.
	pass

func _voice_pitch_scale() -> float:
	return NOTIFICATION_PITCH
