require "minitest/autorun"
require_relative "../lib/silero_vad"

class TestSileroVad < Minitest::Test
  def setup
    @model = SileroVad.load
  end

  def test_model_loads
    assert_instance_of SileroVad::Model, @model
  end

  def test_single_chunk_silence
    # 512 zeros should have very low speech probability
    silence = Array.new(512, 0.0)
    prob = @model.call(silence, 16_000)
    assert_kind_of Float, prob
    assert prob < 0.3, "Silence should have low speech probability, got #{prob}"
  end

  def test_single_chunk_returns_probability
    # Random noise — should return a probability in [0, 1]
    noise = Array.new(512) { rand * 2 - 1 }
    prob = @model.call(noise, 16_000)
    assert prob >= 0.0 && prob <= 1.0, "Probability should be in [0,1], got #{prob}"
  end

  def test_reset_states
    noise = Array.new(512) { rand * 2 - 1 }
    @model.call(noise, 16_000)
    @model.reset_states
    # Should not raise after reset
    prob = @model.call(noise, 16_000)
    assert_kind_of Float, prob
  end

  def test_read_wav
    wav_path = File.join(__dir__, "en_example.wav")
    skip "No test WAV file" unless File.exist?(wav_path)

    samples = SileroVad::Audio.read_wav(wav_path, target_sr: 16_000)
    assert_kind_of Array, samples
    assert samples.length > 16_000, "Should have more than 1 second of audio"
    assert samples.all? { |s| s.is_a?(Float) || s.is_a?(Integer) }

    # Check normalization
    max_val = samples.map(&:abs).max
    assert max_val <= 1.01, "Samples should be normalized, max=#{max_val}"
  end

  def test_speech_timestamps_on_wav
    wav_path = File.join(__dir__, "en_example.wav")
    skip "No test WAV file" unless File.exist?(wav_path)

    samples = SileroVad::Audio.read_wav(wav_path, target_sr: 16_000)
    timestamps = SileroVad.speech_timestamps(samples, @model, sampling_rate: 16_000)

    assert_kind_of Array, timestamps
    assert timestamps.length > 0, "Should detect speech in the example audio"

    timestamps.each do |ts|
      assert ts.key?(:start), "Timestamp must have :start"
      assert ts.key?(:end), "Timestamp must have :end"
      assert ts[:end] > ts[:start], "End must be after start"
    end
  end

  def test_speech_timestamps_seconds
    wav_path = File.join(__dir__, "en_example.wav")
    skip "No test WAV file" unless File.exist?(wav_path)

    samples = SileroVad::Audio.read_wav(wav_path, target_sr: 16_000)
    timestamps = SileroVad.speech_timestamps(samples, @model,
                                             sampling_rate: 16_000,
                                             return_seconds: true)

    assert timestamps.length > 0
    timestamps.each do |ts|
      assert ts[:start].is_a?(Numeric)
      assert ts[:end].is_a?(Numeric)
      assert ts[:start] >= 0
    end
  end

  def test_detect_convenience
    wav_path = File.join(__dir__, "en_example.wav")
    skip "No test WAV file" unless File.exist?(wav_path)

    segments = SileroVad.detect(wav_path)
    assert segments.length > 0, "Should detect speech"
    puts "\n  Detected #{segments.length} speech segments:"
    segments.each { |s| puts "    #{s[:start]}s - #{s[:end]}s" }
  end

  def test_audio_forward
    wav_path = File.join(__dir__, "en_example.wav")
    skip "No test WAV file" unless File.exist?(wav_path)

    samples = SileroVad::Audio.read_wav(wav_path, target_sr: 16_000)
    probs = @model.audio_forward(samples, 16_000)

    assert probs.length > 0
    assert probs.all? { |p| p >= 0.0 && p <= 1.0 }

    speech_frames = probs.count { |p| p > 0.5 }
    puts "\n  #{probs.length} frames, #{speech_frames} speech (#{(100.0 * speech_frames / probs.length).round(1)}%)"
  end

  def test_vad_iterator
    wav_path = File.join(__dir__, "en_example.wav")
    skip "No test WAV file" unless File.exist?(wav_path)

    samples = SileroVad::Audio.read_wav(wav_path, target_sr: 16_000)
    iter = SileroVad::VadIterator.new(@model, sampling_rate: 16_000)

    events = []
    window = 512
    (0...samples.length).step(window) do |i|
      chunk = samples[i, window] || []
      next if chunk.length < window
      event = iter.call(chunk)
      events << event if event
    end

    starts = events.select { |e| e.key?(:start) }
    ends = events.select { |e| e.key?(:end) }

    assert starts.length > 0, "Should detect speech starts"
    puts "\n  Iterator: #{starts.length} starts, #{ends.length} ends"
  end

  def test_collect_chunks
    audio = (0..999).to_a.map(&:to_f)
    timestamps = [{ start: 100, end: 200 }, { start: 500, end: 600 }]
    collected = SileroVad::Audio.collect_chunks(timestamps, audio)
    assert_equal 200, collected.length
    assert_equal 100.0, collected.first
    assert_equal 500.0, collected[100]
  end

  def test_write_and_read_wav
    samples = Array.new(16_000) { Math.sin(2 * Math::PI * 440 * _1 / 16_000.0) * 0.5 }
    path = "/tmp/silero_test_out.wav"
    SileroVad::Audio.write_wav(path, samples, sample_rate: 16_000)
    assert File.exist?(path)

    read_back = SileroVad::Audio.read_wav(path, target_sr: 16_000)
    assert_in_delta samples.length, read_back.length, 1
    # PCM16 roundtrip won't be exact
    assert_in_delta samples[100], read_back[100], 0.001
    File.delete(path)
  end
end
