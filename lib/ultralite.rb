# frozen_string_literal: true

require 'sqlite3'

require_relative "ultralite/version"
require_relative "ultralite/db"
require_relative "ultralite/cache"
require_relative "ultralite/queue"
require_relative "ultralite/job"

module Ultralite
  class Error < StandardError; end
end
