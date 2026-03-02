# frozen_string_literal: true

module SileroVad
  # Minimal WAV reader. No external dependencies.
  #
  # Handles PCM 16-bit WAV files, converts to mono, resamples to target rate.
  module Audio
    module_function

    # Read a WAV file and return normalized float samples.
    #
    # @param path [String] path to .wav file
    # @param target_sr [Integer] target sample rate (default 16000)
    # @return [Array<Float>] normalized samples in [-1.0, 1.0]
    def read_wav(path, target_sr: 16_000)
      data = File.binread(path)
      raise Error, "Not a RIFF file" unless data[0, 4] == "RIFF"
      raise Error, "Not a WAVE file" unless data[8, 4] == "WAVE"

      fmt = find_chunk(data, "fmt ")
      raise Error, "No fmt chunk" unless fmt

      audio_format = fmt[0, 2].unpack1("v")
      channels     = fmt[2, 2].unpack1("v")
      sample_rate  = fmt[4, 4].unpack1("V")
      bits_per_sample = fmt[14, 2].unpack1("v")

      # We support PCM (1) and IEEE float (3)
      unless [1, 3].include?(audio_format)
        raise Error, "Unsupported audio format: #{audio_format} (need PCM=1 or Float=3)"
      end

      raw = find_chunk(data, "data")
      raise Error, "No data chunk" unless raw

      # Decode samples
      samples = case audio_format
                when 1 # PCM
                  case bits_per_sample
                  when 16
                    raw.unpack("s<*").map { |s| s / 32768.0 }
                  when 32
                    raw.unpack("l<*").map { |s| s / 2147483648.0 }
                  when 8
                    raw.unpack("C*").map { |s| (s - 128) / 128.0 }
                  else
                    raise Error, "Unsupported bit depth: #{bits_per_sample}"
                  end
                when 3 # IEEE float
                  case bits_per_sample
                  when 32
                    raw.unpack("e*")
                  when 64
                    raw.unpack("E*")
                  else
                    raise Error, "Unsupported float bit depth: #{bits_per_sample}"
                  end
                end

      # Mix to mono
      if channels > 1
        mono = []
        samples.each_slice(channels) do |frame|
          mono << frame.sum / channels.to_f
        end
        samples = mono
      end

      # Resample if needed (simple linear interpolation)
      if sample_rate != target_sr
        samples = resample(samples, sample_rate, target_sr)
      end

      samples
    end

    # Write samples to a PCM 16-bit WAV file.
    #
    # @param path [String] output path
    # @param samples [Array<Float>] normalized samples
    # @param sample_rate [Integer]
    def write_wav(path, samples, sample_rate: 16_000)
      pcm = samples.map { |s| (s.clamp(-1.0, 1.0) * 32767).round }.pack("s<*")
      channels = 1
      bits = 16
      byte_rate = sample_rate * channels * bits / 8
      block_align = channels * bits / 8
      data_size = pcm.bytesize

      header = "RIFF"
      header += [36 + data_size].pack("V")
      header += "WAVE"
      header += "fmt "
      header += [16].pack("V")           # chunk size
      header += [1].pack("v")            # PCM
      header += [channels].pack("v")
      header += [sample_rate].pack("V")
      header += [byte_rate].pack("V")
      header += [block_align].pack("v")
      header += [bits].pack("v")
      header += "data"
      header += [data_size].pack("V")

      File.binwrite(path, header + pcm)
    end

    # Collect speech segments from audio based on timestamps.
    #
    # @param timestamps [Array<Hash>] from speech_timestamps (sample-based)
    # @param audio [Array<Float>]
    # @return [Array<Float>] concatenated speech segments
    def collect_chunks(timestamps, audio)
      timestamps.flat_map { |ts| audio[ts[:start]...ts[:end]] }
    end

    # Drop speech segments, keeping only non-speech.
    def drop_chunks(timestamps, audio)
      result = []
      cur = 0
      timestamps.each do |ts|
        result.concat(audio[cur...ts[:start]])
        cur = ts[:end]
      end
      result.concat(audio[cur..])
      result
    end

    # Simple linear interpolation resampler.
    def resample(samples, from_sr, to_sr)
      return samples if from_sr == to_sr

      ratio = from_sr.to_f / to_sr
      out_len = (samples.length / ratio).ceil
      Array.new(out_len) do |i|
        src = i * ratio
        idx = src.floor
        frac = src - idx
        s0 = samples[idx] || 0.0
        s1 = samples[idx + 1] || s0
        s0 + frac * (s1 - s0)
      end
    end

    private_class_method :resample

    # Find a RIFF chunk by its 4-byte ID and return its data.
    def find_chunk(data, id)
      pos = 12 # skip RIFF header
      while pos < data.bytesize - 8
        chunk_id = data[pos, 4]
        chunk_size = data[pos + 4, 4].unpack1("V")
        if chunk_id == id
          return data[pos + 8, chunk_size]
        end
        pos += 8 + chunk_size
        pos += 1 if chunk_size.odd? # RIFF chunks are word-aligned
      end
      nil
    end

    private_class_method :find_chunk
  end
end
