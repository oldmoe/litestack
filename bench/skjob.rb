require "sidekiq"

class SidekiqJob
  include Sidekiq::Job
  @@count = 0
  def perform(count, time, sleep_interval = nil)
    sleep sleep_interval if sleep_interval
    @@count += 1
    if @@count == count
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      warn "Sidekiq finished in #{now - time} seconds (#{count / (now - time)} jps)"
      @@count = 0
    end
  end
end
