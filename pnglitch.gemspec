# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'pnglitch'

Gem::Specification.new do |spec|
  spec.name          = "pnglitch"
  spec.version       = PNGlitch::VERSION
  spec.authors       = ["ucnv"]
  spec.email         = ["ucnvvv@gmail.com"]
  spec.summary       = %q{A Ruby library to glitch PNG images.}
  spec.description   = <<-EOL.gsub(/^\s*/, '')
    PNGlitch is a Ruby library to destroy your PNG images.
    With normal data-bending technique, a glitch against PNG will easily fail
    because of the checksum function. We provide a fail-proof destruction for it.
    Using this library you will see beautiful and various PNG artifacts.
  EOL
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
end
