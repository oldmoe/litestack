# frozen_stringe_literal: true

# all components should require the support module
require_relative "litesupport"
require 'oj'
require 'bigdecimal'
  
module Litekd
  
  DEFAULT_OPTIONS = {
    path: Litesupport.root.join("kd.sqlite3"),
    sync: 1,
    mmap_size: 32 * 1024 * 1024, # 32MB
  }
  
  def self.connection()
    # configuration should be loaded here
    @@connection ||= Litekd::Connection.new(DEFAULT_OPTIONS.merge(options))
  end
  
  def self.options
    @@options ||= {}
  end
  
  def self.configure(options = {})
    @@options = options
  end
  
  # scalars
  def self.string(key, **args) = Scalar.new(key, typed: :string, **args)
  def self.integer(key, **args) = Scalar.new(key, typed: :integer, **args)
  def self.decimal(key, **args) = Scalar.new(key, typed: :decimal, **args)
  def self.float(key, **args) = Scalar.new(key, typed: :float, **args)
  def self.boolean(key, **args) = Scalar.new(key, typed: :boolean, **args)
  def self.datetime(key, **args) = Scalar.new(key, typed: :datetime, **args)
  def self.json(key, **args) = Scalar.new(key, typed: :json, **args)
  def self.counter(key, **args) = Counter.new(key, **args)
  def self.cycle(key, **args) = Cycle.new(key, **args)
  def self.enum(key, **args) = Enum.new(key, **args)
  def self.slots(key, **args) = Slots.new(key, **args)
  def self.slot(key, **args) = Slots.new(key, available: 1, **args)
  def self.flag(key, **args) = Flag.new(key, **args)
  def self.limiter(key, **args) = Limiter.new(key, **args)
  # composites
  def self.list(key, **args) = List.new(key, **args)
  def self.unique_list(key, **args) = UniqueList.new(key, **args)
  def self.set(key, **args) = Set.new(key, **args)
  def self.ordered_set(key, **args) = OrderedSet.new(key, **args)
  def self.hash(key, **args) = Hash.new(key, **args)
      
end 

require_relative './litekd/type_serializer'
require_relative './litekd/callbacks'
require_relative './litekd/connection'
require_relative './litekd/scalar'
require_relative './litekd/counter'
require_relative './litekd/cycle'
require_relative './litekd/enum'
require_relative './litekd/slots'
require_relative './litekd/flag'
require_relative './litekd/limiter'
require_relative './litekd/composite'
require_relative './litekd/list'
require_relative './litekd/unique_list'
require_relative './litekd/set'
require_relative './litekd/ordered_set'
require_relative './litekd/hash'
require_relative './litekd/attributes'


