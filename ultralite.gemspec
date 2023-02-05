# frozen_string_literal: true

require_relative "lib/ultralite/version"

Gem::Specification.new do |spec|
  spec.name = "ultralite"
  spec.version = Ultralite::VERSION
  spec.authors = ["Mohamed Ali"]
  spec.email = ["mohamed@hey.com"]

  spec.summary = "It's a database, it's a cache, it's a queue!"
  spec.homepage = "http://www.test.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "http://source.com"
  spec.metadata["changelog_uri"] = "http://log.com"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "bin"
  #spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib", "lib/ultralite"]

  spec.add_dependency "sqlite3"
  spec.add_dependency "oj"
end
