# silero_vad

Voice Activity Detection for Ruby, using the [Silero VAD](https://github.com/snakers4/silero-vad) v5 ONNX model.

No Python. No PyTorch. Just ONNX Runtime and a faithful port of the reference implementation.

## Installation

Not yet on RubyGems. Install from GitHub:

```ruby
# Gemfile
gem "silero_vad", git: "https://github.com/thestarfarer/silero-vad-ruby"
```

Or clone locally:

```bash
git clone https://github.com/thestarfarer/silero-vad-ruby.git
```

```ruby
gem "silero_vad", path: "/path/to/silero-vad-ruby"
```

The ONNX model (~2.3MB) is bundled. The `onnxruntime` gem handles the native runtime.

## Usage

### Quick detection

```ruby
require "silero_vad"

segments = SileroVad.detect("recording.wav")
segments.each { |s| puts "#{s[:start]}s - #{s[:end]}s" }
```

### Full control

```ruby
model = SileroVad.load
samples = SileroVad::Audio.read_wav("recording.wav", target_sr: 16_000)

timestamps = SileroVad.speech_timestamps(
  samples, model,
  sampling_rate: 16_000,
  threshold: 0.5,
  min_speech_duration_ms: 250,
  min_silence_duration_ms: 100,
  speech_pad_ms: 30,
  return_seconds: true
)
```

### Streaming with VadIterator

```ruby
model = SileroVad.load
iter = SileroVad::VadIterator.new(model, sampling_rate: 16_000)

# Feed 512-sample chunks (32ms at 16kHz)
audio_chunks.each do |chunk|
  event = iter.call(chunk)
  puts "Speech started" if event&.key?(:start)
  puts "Speech ended"   if event&.key?(:end)
end
```

### Audio utilities

```ruby
# Read any PCM WAV (8/16/32-bit, mono or stereo, any sample rate)
samples = SileroVad::Audio.read_wav("input.wav", target_sr: 16_000)

# Extract only speech
speech = SileroVad::Audio.collect_chunks(timestamps, samples)
SileroVad::Audio.write_wav("speech_only.wav", speech)

# Extract only silence
non_speech = SileroVad::Audio.drop_chunks(timestamps, samples)
```

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `threshold` | 0.5 | Speech probability threshold |
| `neg_threshold` | threshold - 0.15 | Exit threshold (hysteresis) |
| `min_speech_duration_ms` | 250 | Discard segments shorter than this |
| `max_speech_duration_s` | ∞ | Force-split segments longer than this |
| `min_silence_duration_ms` | 100 | Silence required to end a segment |
| `speech_pad_ms` | 30 | Pad each segment on both sides |
| `return_seconds` | false | Return seconds instead of sample indices |

## Supported audio

The model accepts **8kHz** and **16kHz** sample rates (or multiples of 16kHz, which are downsampled automatically). The bundled WAV reader handles PCM 8/16/32-bit and IEEE float 32/64-bit, mono or multi-channel.

For other formats (MP3, FLAC, OGG), convert to WAV first with ffmpeg:

```sh
ffmpeg -i input.mp3 -ar 16000 -ac 1 -f wav output.wav
```

## Cross-validated

The gem's output has been verified to produce **identical timestamps** to the Python reference implementation on the same ONNX model and test audio. Same 19 speech segments, same boundaries to the tenth of a second.

## License

MIT — same as the Silero VAD model itself.
