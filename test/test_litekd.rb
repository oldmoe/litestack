require "minitest/autorun"
require_relative "../lib/litestack/litekd"
require 'active_support'
require 'active_support/core_ext'

Kredis = Litekd

Litekd.configure({path: ":memory:"})

class Person 

  include Litekd::Attributes
  
  litekd_list :names
  litekd_list :names_with_custom_key_via_lambda, key: ->(p) { "person:#{p.id}:names_customized" }
  litekd_list :names_with_custom_key_via_method, key: :generate_names_key
  litekd_unique_list :skills, limit: 2
  litekd_enum :morning, values: %w[ bright blue black ], default: "bright"
  litekd_counter :steps, expires_in: 0.01.seconds

  def id
    self.object_id
  end
  
  private

  def generate_names_key
    "key-generated-from-private-method"
  end

end


class TestLitekd < Minitest::Test

  def setup
  end

  def test_string
    string = Kredis.string "mystring"
    string.value = "hello world!"  # => SET mystring "hello world"
    assert_equal "hello world!", string.value # => GET mystring
  end

  def test_integer
    integer = Kredis.integer "myinteger"
    integer.value = 5  # => SET myinteger "5"
    assert_equal 5, integer.value # => GET myinteger
  end

  def test_decimal
    decimal = Kredis.decimal "mydecimal" # accuracy!
    decimal.value = "%.47f" % (1.0 / 10) # => SET mydecimal "0.10000000000000000555111512312578270211815834045"
    assert_equal BigDecimal("0.10000000000000000555111512312578270211815834045e0"), decimal.value # => GET mydecimal
  end

  def test_float
    float = Kredis.float "myfloat" # speed!
    float.value = 1.0 / 10 # => SET myfloat "0.1"
    assert_equal 0.1, float.value # => GET myfloat
  end

  def test_boolean
    boolean = Kredis.boolean "myboolean"
    boolean.value = true # => SET myboolean "t"
    assert_equal true, boolean.value # => GET myboolean
  end

  def test_datetime  
    datetime = Kredis.datetime "mydatetime"
    memoized_midnight = Time.now.midnight
    datetime.value = memoized_midnight # SET mydatetime "2021-07-27T00:00:00.000000000Z"
    assert_equal memoized_midnight, datetime.value # => GET mydatetime    datetime = Kredis.datetime "mydatetime"
  end

  def test_json
    json = Kredis.json "myjson"
    json.value = { "one" => 1, "two" => "2" }  # => SET myjson "{\"one\":1,\"two\":\"2\"}"
    assert_equal({ "one" => 1, "two" => "2" }, json.value)  # => GET myjson
  end

  def test_list
    list = Kredis.list "mylist"
    list << "hello world!"               # => RPUSH mylist "hello world!"
    assert_equal [ "hello world!" ], list.elements  # => LRANGE mylist 0, -1
  end

  def test_typed_list
    integer_list = Kredis.list "myintegerlist", typed: :integer, default: [ 1, 2, 3 ] # => EXISTS? myintegerlist, RPUSH myintegerlist "1" "2" "3"
    integer_list.append([ 4, 5, 6 ])                                                  # => RPUSH myintegerlist "4" "5" "6"
    integer_list << 7                                                                 # => RPUSH myintegerlist "7"
    assert_equal [ 1, 2, 3, 4, 5, 6, 7 ] , integer_list.elements                                  # => LRANGE myintegerlist 0 -1
  end
  
  def test_unique_list
    unique_list = Kredis.unique_list "myuniquelist"
    unique_list.append(%w[ 2 3 4 ])                # => LREM myuniquelist 0, "2" + LREM myuniquelist 0, "3" + LREM myuniquelist 0, "4"  + RPUSH myuniquelist "2", "3", "4"
    unique_list.prepend(%w[ 1 2 3 4 ])             # => LREM myuniquelist 0, "1"  + LREM myuniquelist 0, "2" + LREM myuniquelist 0, "3" + LREM myuniquelist 0, "4"  + LPUSH myuniquelist "1", "2", "3", "4"
    unique_list.append([])
    unique_list << "5"                             # => LREM myuniquelist 0, "5" + RPUSH myuniquelist "5"
    unique_list.remove(3)                          # => LREM myuniquelist 0, "3"
    assert_equal [ "4", "2", "1", "5" ] , unique_list.elements # => LRANGE myuniquelist 0, -1
  end
  
  def test_ordered_set
    ordered_set = Kredis.ordered_set "myorderedset"
    ordered_set.append(%w[ 2 3 4 ])                # => ZADD myorderedset 1646131025.4953232 2 1646131025.495326 3 1646131025.4953272 4
    ordered_set.prepend(%w[ 1 2 3 4 ])             # => ZADD myorderedset -1646131025.4957051 1 -1646131025.495707 2 -1646131025.4957082 3 -1646131025.4957092 4
    ordered_set.append([])
    ordered_set << "5"                             # => ZADD myorderedset 1646131025.4960442 5
    ordered_set.remove(3)                          # => ZREM myorderedset 3
    assert_equal [ "4", "2", "1", "5" ] , ordered_set.elements # => ZRANGE myorderedset 0 -1
  end
  
  def test_set
    set = Kredis.set "myset", typed: :datetime
    set.add(DateTime.tomorrow, DateTime.yesterday)           # => SADD myset "2021-02-03 00:00:00 +0100" "2021-02-01 00:00:00 +0100"
    set << DateTime.tomorrow   
    assert_equal 2, set.size                                            # => SCARD myset
    assert_equal [ DateTime.tomorrow, DateTime.yesterday ].sort, set.members.sort # => SMEMBERS myset
  end
  
  def test_hash
    hash = Kredis.hash "myhash"
    hash.update("key" => "value", "key2" => "value2")     # => HSET myhash "key", "value", "key2", "value2"
    assert_equal({ "key" => "value", "key2" => "value2" }, hash.to_h) # => HGETALL myhash
    assert_equal "value2", hash["key2"]                              # => HMGET myhash "key2"
    assert_equal %w[ key key2 ], hash.keys                           # => HKEYS myhash
    assert_equal %w[ value value2 ], hash.values                     # => HVALS myhash
    hash.remove                                           # => DEL myhash
  end
  
  def test_typed_hash
    high_scores = Kredis.hash "high_scores", typed: :integer
    high_scores.update(space_invaders: 100, pong: 42)             # HSET high_scores "space_invaders", "100", "pong", "42"
    assert_equal %w[ space_invaders pong ].sort, high_scores.keys.sort                 # HKEYS high_scores
    assert_equal [ 100, 42 ].sort, high_scores.values.sort                             # HVALS high_scores
    assert_equal({ "space_invaders" => 100, "pong" => 42 }, high_scores.to_h) # HGETALL high_scores
  end

  def test_counter
    head_count = Kredis.counter "headcount"
    assert_equal 0, head_count.value              # => GET "headcount"
    head_count.increment               # => SET headcount 0 NX + INCRBY headcount 1
    head_count.increment               # => SET headcount 0 NX + INCRBY headcount 1
    head_count.decrement               # => SET headcount 0 NX + DECRBY headcount 1
    assert_equal 1, head_count.value              # => GET "headcount"
  end
  
  def test_expiring_counter
    counter = Kredis.counter "mycounter", expires_in: 0.1
    counter.increment by: 2                    # => SET mycounter 0 EX 5 NX + INCRBY "mycounter" 2
    assert_equal 2, counter.value                 # => GET "mycounter"
    sleep 0.15
    assert_equal 0, counter.value                 # => GET "mycounter"
  end
  
  def test_cycle
    cycle = Kredis.cycle "mycycle", values: %i[ one two three ]
    assert_equal :one, cycle.value             # => GET mycycle
    cycle.next                      # => GET mycycle + SET mycycle 1
    assert_equal :two, cycle.value             # => GET mycycle
    cycle.next                      # => GET mycycle + SET mycycle 2
    assert_equal :three, cycle.value           # => GET mycycle
    cycle.next                      # => GET mycycle + SET mycycle 0
    assert_equal  :one, cycle.value             # => GET mycycle
  end
  
  def test_enum
    enum = Kredis.enum "myenum", values: %w[ one two three ], default: "one"
    assert_equal "one", enum.value             # => GET myenum
    assert_equal  true, enum.one?               # => GET myenum
    enum.value = "two"              # => SET myenum "two"
    assert_equal "two", enum.value             # => GET myenum
    enum.three!                     # => SET myenum "three"
    assert_equal "three", enum.value           # => GET myenum
    enum.value = "four"
    assert_equal "three", enum.value           # => GET myenum
    enum.reset                      # => DEL myenum
    assert_equal "one", enum.value             # => GET myenum
  end
  
  def test_slots
    slots = Kredis.slots "myslots", available: 3
    assert_equal true, slots.available?        # => GET myslots
    slots.reserve                   # => INCR myslots
    assert_equal true, slots.available?        # => GET myslots
    slots.reserve                   # => INCR myslots
    assert_equal true, slots.available?        # => GET myslots
    slots.reserve                   # => INCR myslots
    assert_equal false, slots.available?       # => GET myslots
    slots.reserve                   # => INCR myslots + DECR myslots
    assert_equal false, slots.available?       # => GET myslots
    slots.release                   # => DECR myslots
    assert_equal true, slots.available?        # => GET myslots
    slots.reset                     # => DEL myslots
  end
  
  def test_slot
    slot = Kredis.slot "myslot"
    assert_equal true, slot.available?        # => GET myslot
    slot.reserve                   # => INCR myslot
    assert_equal false, slot.available?        # => GET myslot
    slot.release                   # => DECR myslot
    assert_equal true, slot.available?        # => GET myslot
    slot.reset                     # => DEL myslot
  end
  
  def test_flag
    flag = Kredis.flag "myflag"
    assert_equal false, flag.marked?           # => EXISTS myflag
    flag.mark                                  # => SET myflag 1
    assert_equal true, flag.marked?            # => EXISTS myflag
    flag.remove                                # => DEL myflag
    assert_equal false, flag.marked?           # => EXISTS myflag
  end

  def test_flag_expiry
    flag = Kredis.flag "myflag"
    assert_equal true, flag.mark(expires_in: 0.01.second, force: false)    #=> SET myflag 1 EX 1 NX
    assert_equal false, flag.mark(expires_in: 10.seconds, force: false) #=> SET myflag 10 EX 1 NX
    assert_equal true, flag.marked?            #=> EXISTS myflag
    sleep 0.002.seconds
    assert_equal true, flag.marked?            #=> EXISTS myflag
    sleep 0.01.seconds
    assert_equal false, flag.marked?           #=> EXISTS myflag
  end
  
  def test_limiter
    limiter = Kredis.limiter "mylimit", limit: 3, expires_in: 0.02.seconds
    assert_equal 0, limiter.value              # => GET "limiter"
    limiter.poke                    # => SET limiter 0 NX + INCRBY limiter 1
    limiter.poke                    # => SET limiter 0 NX + INCRBY limiter 1
    limiter.poke                    # => SET limiter 0 NX + INCRBY limiter 1
    assert_equal false, limiter.exceeded?      # => GET "limiter"
    limiter.poke                    # => SET limiter 0 NX + INCRBY limiter 1
    assert_equal  true, limiter.exceeded?       # => GET "limiter"
    sleep 0.02
    limiter.poke                    # => SET limiter 0 NX + INCRBY limiter 1
    limiter.poke                    # => SET limiter 0 NX + INCRBY limiter 1
    limiter.poke                    # => SET limiter 0 NX + INCRBY limiter 1
    assert_equal false, limiter.exceeded?      # => GET "limiter"
  end
  
  def test_attributes
    person = Person.new
    person.names.append "David", "Heinemeier", "Hansson" # => RPUSH people:5:names "David" "Heinemeier" "Hansson"
    assert_equal true, person.morning.bright?                       # => GET people:5:morning
    person.morning.value = "blue"                        # => SET people:5:morning
    assert_equal true, person.morning.blue?                         # => GET people:5:morning  
    assert_equal "names-Person-#{person.id}", person.names.key
    assert_equal "morning-Person-#{person.id}", person.morning.key
    assert_equal "person:#{person.id}:names_customized", person.names_with_custom_key_via_lambda.key
    assert_equal "key-generated-from-private-method", person.names_with_custom_key_via_method.key
    assert_equal 0, person.steps.value
    person.steps.increment(by: 3)
    assert_equal 3, person.steps.value
    sleep 0.01
    assert_equal 0, person.steps.value    
  end

end
