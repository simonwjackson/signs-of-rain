extends SceneTree
const FrameTimes = preload("res://game/frame_times.gd")
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func _initialize() -> void:
	var timing = FrameTimes.new()
	for frame in range(100):
		timing.record(.01)
	timing.record(.04)
	var report: Dictionary = timing.report()
	check(report.frames == 101, "every frame contributes to the counter")
	check(report.over_60hz_budget == 1, "a 40ms frame exceeds the 60Hz budget")
	check(is_equal_approx(report.p95_ms, 10), "95th percentile uses measured intervals")
	check(is_equal_approx(report.max_ms, 40), "a spike remains visible")
	for frame in range(FrameTimes.LIMIT + 1):
		timing.record(.02)
	report = timing.report()
	check(report.window_frames == FrameTimes.LIMIT, "sample storage remains bounded")
	check(is_equal_approx(report.p50_ms, 20), "percentiles track the current sample window")
	check(report.frames > FrameTimes.LIMIT, "total counters survive window replacement")
	print("FRAME TIMES: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
