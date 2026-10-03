extends Node
## Authored wave files. Presentation audio never advances simulation randomness.
const RAIN = preload("res://assets/audio/rain.wav")
const FOOD = preload("res://assets/audio/food.wav")
const TOUCH = preload("res://assets/audio/touch.wav")
var ambience: AudioStreamPlayer
var enabled := true
var voices: Array[AudioStreamPlayer] = []


func _ready() -> void:
	ambience = AudioStreamPlayer.new()
	var stream: AudioStreamWAV = preload("res://assets/audio/ambience.wav").duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	ambience.stream = stream
	ambience.volume_db = -5
	add_child(ambience)
	for i in range(6):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -5
		add_child(voice)
		voices.append(voice)


func play(kind: String) -> void:
	if not enabled:
		return
	for voice in voices:
		if not voice.playing:
			voice.stream = RAIN if kind == "rain" else FOOD if kind == "food" else TOUCH
			voice.play()
			return


func _exit_tree() -> void:
	ambience.stop()
	ambience.stream = null
	for voice in voices:
		voice.stop()
		voice.stream = null
	voices.clear()


func set_enabled(value: bool) -> void:
	enabled = value
	if enabled:
		if not ambience.playing:
			ambience.play()
	else:
		ambience.stop()
		for voice in voices:
			voice.stop()
