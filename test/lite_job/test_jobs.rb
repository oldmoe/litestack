require "litestack/litejob"

class TestJob
  include Litejob

  def perform
    Performance.performed!
  end
end

class FibonacciJob
  def perform(n)
    Performance.performed!
    fibonacci(n)
  end

  def fibonacci(n)
    return n if n <= 1
    fibonacci(n - 1) + fibonacci(n - 2)
  end
end

class TestMultipleParameterJob
  def perform(a, b)
    Performance.performed!
    Performance.processed!([a, b])
  end
end

class FailingJob
  def perform
    raise "I failed"
  end
end