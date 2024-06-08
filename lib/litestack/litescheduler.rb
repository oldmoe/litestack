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
    if backend == :fiber
      Fiber.schedule(&block)
    elsif backend == :polyphony
      spin(&block)
    elsif (backend == :threaded) || (backend == :iodine)
      Thread.new(&block)
    end
    # we should never reach here
  end

  def self.storage
    if fiber_backed?
      Fiber.current.storage
    else
      Thread.current
    end
  end

  def self.current
    if fiber_backed?
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

  def self.fiber_backed?
    backend == :fiber || backend == :polyphony
  end

  private_class_method :fiber_backed?

  class Mutex
    def initialize
      @mutex = Thread::Mutex.new
    end

    def synchronize(&block)
      if Litescheduler.backend == :threaded || Litescheduler.backend == :iodine
        @mutex.synchronize { block.call }
      else
        block.call
      end
    end
  end

  module ForkListener
    def self.listeners
      @listeners ||= []
    end

    def self.listen(&block)
      listeners << block
    end
  end

  module Forkable
    def _fork(*args)
      ppid = Process.pid
      result = super
      if Process.pid != ppid && [:threaded, :iodine].include?(Litescheduler.backend)
        ForkListener.listeners.each { |l| l.call }
      end
      result
    end
  end
end

Process.singleton_class.prepend(Litescheduler::Forkable)
