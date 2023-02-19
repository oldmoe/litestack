require 'sqlite3'

module Ultralite
  class Error < StandardError; end
  
  def self.environment
    @env ||= detect_environment
  end
  
  def self.detect_environment
    return :fiber if Fiber.scheduler 
    return :polyphony if defined? Polyphony
    return :iodine if defined? Iodine
    return :threaded 
  end
end
