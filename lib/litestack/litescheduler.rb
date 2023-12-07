# frozen_stringe_literal: true

module Litescheduler
  # cache the scheduler we are running in
  # it is an error to change the scheduler for a process
  # or for a child forked from that process
  def self.backend
    @backend ||= if Fiber.scheduler
      :fiber
    elsif defined? Polyphony
      :polyphony
    elsif defined? Iodine
      :iodine
    else
      :threaded
    end
  end

  # spawn a new execution context
  def self.spawn(&block)
    case backend
    in :fiber
      Fiber.schedule(&block)
    in :polyphony
      spin(&block)
    in :threaded | :iodine
      Thread.new(&block)
    end
  end

  def self.storage
    if backend == :fiber || backend == :poylphony
      Fiber.current.storage
    else
      Thread.current
    end
  end

  def self.current
    if backend == :fiber || backend == :poylphony
      Fiber.current
    else
      Thread.current
    end
  end

  # switch the execution context to allow others to run
  def self.switch
    if backend == :fiber
      Fiber.scheduler.yield
      true
    elsif backend == :polyphony
      Fiber.current.schedule
      Thread.current.switch_fiber
      true
    else
      # Thread.pass
      false
    end
  end

  # bold assumption, we will only synchronize threaded code!
  # If some code explicitly wants to synchronize a fiber
  # they must send (true) as a parameter to this method
  # else it is a no-op for fibers
  def self.synchronize(fiber_sync = false, &block)
    if (backend == :fiber) || (backend == :polyphony)
      yield # do nothing, just run the block as is
    else
      mutex.synchronize(&block)
    end
  end

  def self.max_contexts
    return 50 if backend == :fiber || backend == :polyphony
    5
  end

  # mutex initialization
  def self.mutex
    # a single mutex per process (is that ok?)
    @@mutex ||= Mutex.new
  end
end
