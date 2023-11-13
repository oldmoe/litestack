# frozen_stringe_literal: true
##
# Litejob is a Ruby module that enables seamless integration of the Litejobqueue job queueing system into Ruby applications. By including the Litejob module in a class and implementing the #perform method, developers can easily enqueue and process jobs asynchronously.
#
# When a job is enqueued, Litejob creates a new instance of the class and passes it any necessary arguments. The class's #perform method is then called asynchronously to process the job. This allows the application to continue running without waiting for the job to finish, improving overall performance and responsiveness.
#
# One of the main benefits of using Litejob is its simplicity. Because it integrates directly with Litejobqueue, developers do not need to worry about managing job queues or processing logic themselves. Instead, they can focus on implementing the #perform method to handle the specific job tasks.
#
# Litejob also provides a number of useful features, including the ability to set job priorities, retry failed jobs, and limit the number of retries. These features can be configured using simple configuration options in the class that includes the Litejob module.
#
# Overall, Litejob is a powerful and flexible module that allows developers to easily integrate Litejobqueue job queueing into their Ruby applications. By enabling asynchronous job processing, Litejob can help improve application performance and scalability, while simplifying the development and management of background job processing logic.
#  class EasyJob
#    include ::Litejob
#
#    def perform(params)
#      # do stuff
#    end
#  end
#
# Then later you can perform a job asynchronously:
#
#  EasyJob.perform_async(params) # perform a job synchronously
# Or perform it at a specific time:
#  EasyJob.perform_at(time, params) # perform a job at a specific time
# Or perform it after a certain delay:
#  EasyJob.perform_in(delay, params) # perform a job after a certain delay
# You can also specify a specific queue to be used
#  class EasyJob
#    include ::Litejob
#
#    self.queue = :urgent
#
#    def perform(params)
#      # do stuff
#    end
#  end
#
module Litejob
  def self.included(klass)
    klass.extend(ClassMethods)
  end

  module ClassMethods
    def perform_async(*params)
      job = LiteJob.enqueue(self, params, 0, queue)
      return [job.id, job.queue]
    end

    def perform_at(time, *params)
      delay = time.to_i - Time.now.to_i
      job = LiteJob.enqueue(self, params, delay, queue)
      return [job.id, job.queue]
    end

    def perform_in(delay, *params)
      job = LiteJob.enqueue(self, params, delay, queue)
      return [job.id, job.queue]
    end

    def perform_after(delay, *params)
      perform_in(delay, *params)
    end

    def process_jobs
      LiteJob.run
    end

    def delete(id)
      LiteJob::Job.destroy(id)
    end

    def queue
      @queue_name ||= "default"
    end

    def queue=(queue_name)
      @queue_name = queue_name
    end

    def considered_dead_after(seconds)
      @lite_job_considered_dead_after = seconds
    end

    def lite_job_considered_dead_after
      @lite_job_considered_dead_after ||= LiteJob.configuration.considered_dead_after
    end
  end
end
