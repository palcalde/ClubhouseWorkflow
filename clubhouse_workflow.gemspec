# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'clubhouse_workflow/version'

Gem::Specification.new do |spec|
  spec.name          = "clubhouse_workflow"
  spec.version       = ClubhouseWorkflow::VERSION
  spec.authors       = ["Pablo Alcalde"]
  spec.email         = ["pablo.alcalde@cabify.com"]

  spec.summary       = %q{ Clubhouse workflow ruby script. It uses git to know when to moves cards to QA or Release. Tag them when releasing. }
  spec.homepage      = "https://github.com/palcalde/clubhouse_workflow"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "clubhouse_ruby", :git => 'https://github.com/PhilipCastiglione/clubhouse_ruby.git', :branch => 'master'
end
