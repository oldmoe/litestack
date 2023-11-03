# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in litestack.gemspec
gemspec

def get_env(name)
  (ENV[name] && !ENV[name].empty?) ? ENV[name] : nil
end

gem 'rails', get_env("RAILS_VERSION")
