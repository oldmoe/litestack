# Run `rails new my-app -m https://raw.githubusercontent.com/oldmoe/litestack/master/template.rb`
# to create a new Rails app with Litestack pre-installed.
gem "litestack", github: "litestack"

after_bundle do
  generate "litestack:install"
end
