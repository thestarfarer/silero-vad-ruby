# frozen_string_literal: true

require "onnxruntime"

module SileroVad
  # Ruby wrapper around the Silero VAD v5 ONNX model.
  #
  # Maintains internal state (LSTM hidden/cell) and context between calls,
  # exactly mirroring the Python OnnxWrapper from utils_vad.py.
  class Model
    SAMPLE_RATES = [8_000, 16_000].freeze

    attr_reader :sample_rates

    def initialize(path: SileroVad::MODEL_PATH, force_cpu: true)
      opts = {
        inter_op_num_threads: 1,
        intra_op_num_threads: 1
      }
      opts[:providers] = ["CPUExecutionProvider"] if force_cpu

      @session = OnnxRuntime::InferenceSession.new(path, **opts)
      @sample_rates = if path.include?("16k")
                        [16_000]
                      else
                        SAMPLE_RATES.dup
                      end
      reset_states
    end

    # Reset LSTM state and context. Call between independent audio files.
    def reset_states(batch_size = 1)
      @state = zeros_3d(2, batch_size, 128)
      @context = nil
      @last_sr = 0
      @last_batch_size = 0
    end

    # Run a single audio chunk through the model.
    #
    # @param samples [Array<Float>] audio samples, length must be 512 (16kHz) or 256 (8kHz)
    # @param sr [Integer] sample rate (8000 or 16000)
    # @return [Float] speech probability 0.0..1.0
    def call(samples, sr)
      samples = validate_input(samples, sr)
      num_samples = sr == 16_000 ? 512 : 256

      unless samples.length == num_samples
        raise Error, "Expected #{num_samples} samples for #{sr}Hz, got #{samples.length}"
      end

      context_size = sr == 16_000 ? 64 : 32
      batch_size = 1

      if @last_batch_size.zero?
        reset_states(batch_size)
      end
      if @last_sr != 0 && @last_sr != sr
        reset_states(batch_size)
      end

      @context ||= Array.new(context_size, 0.0)

      # Concatenate context + samples -> [1, context_size + num_samples]
      input = [@context + samples]

      ort_inputs = {
        "input" => input,
        "state" => @state,
        "sr"    => [sr]
      }

      out, state = @session.run(nil, ort_inputs)
      @state = state
      @context = samples[-context_size..]
      @last_sr = sr
      @last_batch_size = batch_size

      # out is [[prob]] — extract the scalar
      prob = out.is_a?(Array) ? out.flatten.first : out
      prob.to_f
    end

    # Process an entire audio array, returning per-chunk probabilities.
    def audio_forward(samples, sr)
      reset_states
      num_samples = sr == 16_000 ? 512 : 256

      # Pad to multiple of window size
      remainder = samples.length % num_samples
      if remainder > 0
        samples = samples + Array.new(num_samples - remainder, 0.0)
      end

      probs = []
      (0...samples.length).step(num_samples) do |i|
        chunk = samples[i, num_samples]
        probs << call(chunk, sr)
      end
      probs
    end

    private

    def validate_input(samples, sr)
      unless @sample_rates.include?(sr) || (sr > 16_000 && (sr % 16_000).zero?)
        raise Error, "Unsupported sample rate: #{sr}. Supported: #{@sample_rates} (or multiples of 16000)"
      end

      # Downsample multiples of 16kHz
      if sr != 16_000 && sr != 8_000 && (sr % 16_000).zero?
        step = sr / 16_000
        samples = samples.each_slice(step).map(&:first)
      end

      samples.map(&:to_f)
    end

    def zeros_3d(d1, d2, d3)
      Array.new(d1) { Array.new(d2) { Array.new(d3, 0.0) } }
    end
  end
end
