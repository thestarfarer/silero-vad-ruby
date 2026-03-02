Gem::Specification.new do |s|
  s.name        = "silero_vad"
  s.version     = "0.1.0"
  s.summary     = "Silero VAD for Ruby"
  s.description = "Voice Activity Detection using Silero VAD v5 ONNX model. " \
                  "No Python dependency — pure Ruby wrapper around ONNX Runtime."
  s.authors     = ["thestarfarer"]
  s.email       = "thestarfarer@users.noreply.github.com"
  s.homepage    = "https://github.com/thestarfarer/silero-vad-ruby"
  s.license     = "MIT"

  s.required_ruby_version = ">= 3.0"

  s.files         = Dir["lib/**/*", "LICENSE", "README.md"]
  s.bindir        = "bin"
  s.executables   = ["silero-vad"]
  s.require_paths = ["lib"]

  s.add_dependency "onnxruntime", ">= 0.7"

  s.metadata = {
    "source_code_uri"   => "https://github.com/thestarfarer/silero-vad-ruby",
    "bug_tracker_uri"   => "https://github.com/thestarfarer/silero-vad-ruby/issues",
    "silero_vad_version" => "5.1",
  }
end
