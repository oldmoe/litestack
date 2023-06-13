# Run `rails new my-app -m https://raw.githubusercontent.com/bradgessler/litestack/master/template.rb`
# to create a new Rails app with Litestack pre-installed.
gem "litestack", github: "bradgessler/litestack"

after_bundle do
  generate "litestack:install"
end
