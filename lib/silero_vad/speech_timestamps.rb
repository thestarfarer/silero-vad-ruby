# frozen_string_literal: true

module SileroVad
  # Port of get_speech_timestamps from silero-vad utils_vad.py.
  #
  # Splits audio into speech segments using the Silero VAD model,
  # with hysteresis thresholding, minimum duration filtering,
  # and speech padding.
  module SpeechTimestamps
    module_function

    # @param audio [Array<Float>] mono audio samples, normalized to [-1, 1]
    # @param model [SileroVad::Model] loaded Silero VAD model
    # @param threshold [Float] speech probability threshold (default 0.5)
    # @param sampling_rate [Integer] 8000 or 16000
    # @param min_speech_duration_ms [Integer] discard segments shorter than this
    # @param max_speech_duration_s [Float] force-split segments longer than this
    # @param min_silence_duration_ms [Integer] silence required to end a segment
    # @param speech_pad_ms [Integer] pad each segment by this on both sides
    # @param return_seconds [Boolean] return timestamps in seconds (vs samples)
    # @param time_resolution [Integer] decimal places for second-based timestamps
    # @param neg_threshold [Float, nil] exit threshold (default: threshold - 0.15)
    # @param min_silence_at_max_speech [Integer] ms — avoid cuts in very short silence
    # @param use_max_poss_sil_at_max_speech [Boolean] use longest silence when splitting
    # @return [Array<Hash>] list of {start:, end:} hashes
    def get(audio, model,
            threshold: 0.5,
            sampling_rate: 16_000,
            min_speech_duration_ms: 250,
            max_speech_duration_s: Float::INFINITY,
            min_silence_duration_ms: 100,
            speech_pad_ms: 30,
            return_seconds: false,
            time_resolution: 1,
            neg_threshold: nil,
            min_silence_at_max_speech: 98,
            use_max_poss_sil_at_max_speech: true,
            progress_callback: nil)

      audio = Array(audio).map(&:to_f)

      # Handle multiples of 16kHz
      step = 1
      if sampling_rate > 16_000 && (sampling_rate % 16_000).zero?
        step = sampling_rate / 16_000
        sampling_rate = 16_000
        audio = audio.each_slice(step).map(&:first)
      end

      unless [8_000, 16_000].include?(sampling_rate)
        raise Error, "Supported sample rates: 8000, 16000 (or multiples of 16000)"
      end

      window_size = sampling_rate == 16_000 ? 512 : 256

      model.reset_states
      min_speech_samples   = sampling_rate * min_speech_duration_ms / 1000.0
      speech_pad_samples   = sampling_rate * speech_pad_ms / 1000.0
      max_speech_samples   = sampling_rate * max_speech_duration_s - window_size - 2 * speech_pad_samples
      min_silence_samples  = sampling_rate * min_silence_duration_ms / 1000.0
      min_sil_at_max       = sampling_rate * min_silence_at_max_speech / 1000.0

      audio_length = audio.length

      # Compute per-chunk speech probabilities
      speech_probs = []
      (0...audio_length).step(window_size) do |start|
        chunk = audio[start, window_size] || []
        if chunk.length < window_size
          chunk = chunk + Array.new(window_size - chunk.length, 0.0)
        end
        prob = model.call(chunk, sampling_rate)
        speech_probs << prob

        if progress_callback
          progress = [start + window_size, audio_length].min
          progress_callback.call(progress.to_f / audio_length * 100)
        end
      end

      # State machine: threshold with hysteresis
      neg_threshold ||= [threshold - 0.15, 0.01].max
      triggered = false
      speeches = []
      current_speech = {}
      temp_end = 0
      prev_end = 0
      next_start = 0
      possible_ends = []

      speech_probs.each_with_index do |prob, i|
        cur_sample = window_size * i

        # Speech returns after temp_end — record candidate silence
        if prob >= threshold && temp_end > 0
          sil_dur = cur_sample - temp_end
          if sil_dur > min_sil_at_max
            possible_ends << [temp_end, sil_dur]
          end
          temp_end = 0
          next_start = cur_sample if next_start < prev_end
        end

        # Start of speech
        if prob >= threshold && !triggered
          triggered = true
          current_speech[:start] = cur_sample
          next
        end

        # Max speech length reached
        if triggered && (cur_sample - current_speech[:start]) > max_speech_samples
          if use_max_poss_sil_at_max_speech && !possible_ends.empty?
            pe, dur = possible_ends.max_by { |_, d| d }
            current_speech[:end] = pe
            speeches << current_speech
            current_speech = {}
            next_start = pe + dur

            if next_start < pe + cur_sample
              current_speech[:start] = next_start
            else
              triggered = false
            end
            prev_end = 0
            next_start = 0
            temp_end = 0
            possible_ends = []
          else
            if prev_end > 0
              current_speech[:end] = prev_end
              speeches << current_speech
              current_speech = {}
              if next_start < prev_end
                triggered = false
              else
                current_speech[:start] = next_start
              end
              prev_end = 0
              next_start = 0
              temp_end = 0
              possible_ends = []
            else
              current_speech[:end] = cur_sample
              speeches << current_speech
              current_speech = {}
              prev_end = 0
              next_start = 0
              temp_end = 0
              triggered = false
              possible_ends = []
              next
            end
          end
        end

        # Silence detection while in speech
        if prob < neg_threshold && triggered
          temp_end = cur_sample if temp_end.zero?
          sil_dur_now = cur_sample - temp_end

          if !use_max_poss_sil_at_max_speech && sil_dur_now > min_sil_at_max
            prev_end = temp_end
          end

          if sil_dur_now < min_silence_samples
            next
          else
            current_speech[:end] = temp_end
            if (current_speech[:end] - current_speech[:start]) > min_speech_samples
              speeches << current_speech
            end
            current_speech = {}
            prev_end = 0
            next_start = 0
            temp_end = 0
            triggered = false
            possible_ends = []
            next
          end
        end
      end

      # Handle trailing speech
      if current_speech.key?(:start) && (audio_length - current_speech[:start]) > min_speech_samples
        current_speech[:end] = audio_length
        speeches << current_speech
      end

      # Apply padding
      speeches.each_with_index do |speech, i|
        if i.zero?
          speech[:start] = [0, speech[:start] - speech_pad_samples].max.to_i
        end

        if i < speeches.length - 1
          silence_duration = speeches[i + 1][:start] - speech[:end]
          if silence_duration < 2 * speech_pad_samples
            speech[:end] = (speech[:end] + silence_duration / 2).to_i
            speeches[i + 1][:start] = [0, speeches[i + 1][:start] - silence_duration / 2].max.to_i
          else
            speech[:end] = [audio_length, speech[:end] + speech_pad_samples].min.to_i
            speeches[i + 1][:start] = [0, speeches[i + 1][:start] - speech_pad_samples].max.to_i
          end
        else
          speech[:end] = [audio_length, speech[:end] + speech_pad_samples].min.to_i
        end
      end

      # Convert to seconds if requested
      if return_seconds
        audio_length_seconds = audio_length.to_f / sampling_rate
        speeches.each do |s|
          s[:start] = [s[:start].to_f / sampling_rate, 0].max.round(time_resolution)
          s[:end]   = [s[:end].to_f / sampling_rate, audio_length_seconds].min.round(time_resolution)
        end
      elsif step > 1
        speeches.each do |s|
          s[:start] *= step
          s[:end]   *= step
        end
      end

      speeches
    end
  end
end
