extends RefCounted
## Opt-in bounded frame-interval evidence. This is not a GPU timer.
const LIMIT := 3600
var samples: Array[float] = []
var frames := 0
var elapsed := 0.0
var over_budget := 0
var peak_ms := 0.0
var next_sample := 0


func record(delta: float) -> void:
	var milliseconds := delta * 1000
	frames += 1
	elapsed += delta
	peak_ms = maxf(peak_ms, milliseconds)
	if milliseconds > 1000.0 / 60.0:
		over_budget += 1
	if samples.size() < LIMIT:
		samples.append(milliseconds)
	else:
		samples[next_sample] = milliseconds
		next_sample = (next_sample + 1) % LIMIT


func report() -> Dictionary:
	var ordered := samples.duplicate()
	ordered.sort()
	var result := {
		"frames": frames,
		"seconds": elapsed,
		"over_60hz_budget": over_budget,
		"max_ms": peak_ms,
		"window_frames": ordered.size(),
		"interval_source": "Godot process delta, not hardware presentation or GPU time",
	}
	if not ordered.is_empty():
		for entry in [["p50_ms", .50], ["p95_ms", .95], ["p99_ms", .99]]:
			result[entry[0]] = ordered[mini(
				ordered.size() - 1, ceili(ordered.size() * entry[1]) - 1
			)]
	return result
