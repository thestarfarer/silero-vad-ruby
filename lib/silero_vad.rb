# frozen_string_literal: true

require_relative "silero_vad/version"
require_relative "silero_vad/model"
require_relative "silero_vad/speech_timestamps"
require_relative "silero_vad/vad_iterator"
require_relative "silero_vad/audio"

module SileroVad
  class Error < StandardError; end

  MODEL_PATH = File.join(__dir__, "silero_vad", "data", "silero_vad.onnx")

  # Load the default model. Returns an OnnxModel instance.
  #
  #   model = SileroVad.load
  #   timestamps = SileroVad.speech_timestamps(audio, model)
  #
  def self.load(path: MODEL_PATH, force_cpu: true)
    Model.new(path: path, force_cpu: force_cpu)
  end

  # Convenience: read audio, load model, return speech timestamps.
  #
  #   segments = SileroVad.detect("recording.wav")
  #   segments.each { |s| puts "#{s[:start]}..#{s[:end]}" }
  #
  def self.detect(audio_path, sample_rate: 16_000, return_seconds: true, **opts)
    model = load
    samples = Audio.read_wav(audio_path, target_sr: sample_rate)
    speech_timestamps(samples, model, sampling_rate: sample_rate,
                      return_seconds: return_seconds, **opts)
  end

  # Full-featured speech timestamp extraction. Direct port of
  # silero-vad's get_speech_timestamps.
  def self.speech_timestamps(audio, model, **opts)
    SpeechTimestamps.get(audio, model, **opts)
  end
end
