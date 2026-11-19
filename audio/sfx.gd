class_name Sfx
extends RefCounted

const MIX_RATE: int = 22050

static var _cache: Dictionary = {}
static var _rng: RandomNumberGenerator


## Cached wrapper so a given sound is generated at most once per run.
## Generating a WAV is cheap in absolute terms but it happens per spawn /
## per node, and that shows up as a hitch when a wave appears.
static func cached_tone(start_freq: float, end_freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var key: String = "tone:%.1f:%.1f:%.3f:%.1f" % [start_freq, end_freq, duration, volume]
	var stream: AudioStreamWAV = _cache.get(key) as AudioStreamWAV
	if stream == null:
		stream = make_tone(start_freq, end_freq, duration, volume)
		_cache[key] = stream
	return stream


static func cached_noise(duration: float, volume: float) -> AudioStreamWAV:
	var key: String = "noise:%.3f:%.1f" % [duration, volume]
	var stream: AudioStreamWAV = _cache.get(key) as AudioStreamWAV
	if stream == null:
		stream = make_noise(duration, volume)
		_cache[key] = stream
	return stream


## Random pitch multiplier so repeated sounds do not machine-gun.
static func varied_pitch(amount: float = 0.08) -> float:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return 1.0 + _rng.randf_range(-amount, amount)


static func make_tone(start_freq: float, end_freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_count: int = maxi(int(float(MIX_RATE) * duration), 1)
	var samples := PackedByteArray()
	samples.resize(sample_count * 2)

	var phase: float = 0.0
	for i in range(sample_count):
		var t: float = float(i) / float(sample_count)
		var freq: float = lerpf(start_freq, end_freq, t)
		var env: float = (1.0 - t) * (1.0 - t)
		phase = fmod(phase + TAU * freq / float(MIX_RATE), TAU)
		var sample: int = int(sin(phase) * env * volume)
		var offset: int = i * 2
		samples[offset] = sample & 0xFF
		samples[offset + 1] = (sample >> 8) & 0xFF

	return _build_stream(samples)


static func make_noise(duration: float, volume: float) -> AudioStreamWAV:
	var sample_count: int = maxi(int(float(MIX_RATE) * duration), 1)
	var samples := PackedByteArray()
	samples.resize(sample_count * 2)

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(sample_count):
		var t: float = float(i) / float(sample_count)
		var env: float = (1.0 - t) * (1.0 - t)
		var sample: int = int(rng.randf_range(-1.0, 1.0) * env * volume)
		var offset: int = i * 2
		samples[offset] = sample & 0xFF
		samples[offset + 1] = (sample >> 8) & 0xFF

	return _build_stream(samples)


static func _build_stream(samples: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = samples
	return stream
