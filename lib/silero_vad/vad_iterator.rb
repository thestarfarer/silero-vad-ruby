# frozen_string_literal: true

module SileroVad
  # Streaming VAD iterator. Port of VADIterator from utils_vad.py.
  #
  # Feed audio chunks one at a time; returns speech start/end events.
  #
  #   model = SileroVad.load
  #   iter = SileroVad::VadIterator.new(model, sampling_rate: 16_000)
  #
  #   audio_chunks.each do |chunk|
  #     event = iter.call(chunk)
  #     puts "Speech started at #{event[:start]}" if event&.key?(:start)
  #     puts "Speech ended at #{event[:end]}"     if event&.key?(:end)
  #   end
  #
  class VadIterator
    def initialize(model, threshold: 0.5, sampling_rate: 16_000,
                   min_silence_duration_ms: 100, speech_pad_ms: 30)
      unless [8_000, 16_000].include?(sampling_rate)
        raise Error, "VADIterator supports only 8000 and 16000 sample rates"
      end

      @model = model
      @threshold = threshold
      @sampling_rate = sampling_rate
      @min_silence_samples = sampling_rate * min_silence_duration_ms / 1000.0
      @speech_pad_samples  = sampling_rate * speech_pad_ms / 1000.0
      reset
    end

    def reset
      @model.reset_states
      @triggered = false
      @temp_end = 0
      @current_sample = 0
    end

    # Process one audio chunk. Returns nil, {start:}, or {end:}.
    #
    # @param chunk [Array<Float>] audio samples (512 for 16kHz, 256 for 8kHz)
    # @param return_seconds [Boolean]
    # @param time_resolution [Integer]
    # @return [Hash, nil]
    def call(chunk, return_seconds: false, time_resolution: 1)
      window_size = chunk.length
      @current_sample += window_size

      prob = @model.call(chunk, @sampling_rate)

      # Speech resumes — clear temp_end
      if prob >= @threshold && @temp_end > 0
        @temp_end = 0
      end

      # Speech starts
      if prob >= @threshold && !@triggered
        @triggered = true
        speech_start = [0, @current_sample - @speech_pad_samples - window_size].max
        val = return_seconds ? (speech_start / @sampling_rate.to_f).round(time_resolution) : speech_start.to_i
        return { start: val }
      end

      # Below negative threshold while in speech
      if prob < (@threshold - 0.15) && @triggered
        @temp_end = @current_sample if @temp_end.zero?
        if @current_sample - @temp_end < @min_silence_samples
          return nil
        else
          speech_end = @temp_end + @speech_pad_samples - window_size
          @temp_end = 0
          @triggered = false
          val = return_seconds ? (speech_end / @sampling_rate.to_f).round(time_resolution) : speech_end.to_i
          return { end: val }
        end
      end

      nil
    end
  end
end
