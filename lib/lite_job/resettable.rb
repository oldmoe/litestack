require "litestack/litedb"

# A convenience class for use during testing
module LiteJob
  def self.reset!
    reset_configuration!
    kill
  end
end

