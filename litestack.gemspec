# frozen_string_literal: true

require_relative "lib/litestack/version"

Gem::Specification.new do |spec|
  spec.name = "litestack"
  spec.version = Litestack::VERSION
  spec.authors = ["Mohamed Hassan"]
  spec.email = ["oldmoe@gmail.com"]

  spec.summary = "A SQLite based, lightning fast, super efficient and dead simple to setup and use database, cache and job queue for Ruby and Rails applications!"
  spec.homepage = "https://github.com/oldmoe/litestack"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/oldmoe/litestack/CHANEGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "bin"
  # spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.executables = ["liteboard"]
  spec.require_paths = ["lib", "lib/litestack"]

  spec.add_dependency "sqlite3"
  spec.add_dependency "oj"
  spec.add_dependency "rack"
  spec.add_dependency "hanami-router"
  spec.add_dependency "tilt"
  spec.add_dependency "erubi"
  
  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rack", "~> 3.0"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "standard"
  spec.add_development_dependency "sequel"
end
