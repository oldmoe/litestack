# frozen_string_literal: true

require_relative "helper"
require_relative "../lib/litestack/litescheduler"

describe Litescheduler do
  describe "#backend" do
    before do
      Litescheduler.instance_variable_set(:@backend, nil)
    end

    after do
      Litescheduler.instance_variable_set(:@backend, nil)
    end

    it "when Fiber.scheduler present, returns an instance of the Fiber adapter" do
      Scheduler = Class.new do # standard:disable Lint/ConstantDefinitionInBlock
        def block = nil

        def unblock = nil

        def kernel_sleep = nil

        def io_wait = nil
      end
      Fiber.set_scheduler Scheduler.new

      assert_equal :fiber, Litescheduler.backend

      Fiber.set_scheduler nil
    end

    it "when Polyphony defined, returns an instance of the Polyphony adapter" do
      Polyphony = Class.new # standard:disable Lint/ConstantDefinitionInBlock

      assert_equal :polyphony, Litescheduler.backend

      Object.send(:remove_const, :Polyphony)
    end

    it "when Iodine is defined, returns an instance of the Iodine adapter" do
      Iodine = Class.new # standard:disable Lint/ConstantDefinitionInBlock

      assert_equal :iodine, Litescheduler.backend

      Object.send(:remove_const, :Iodine)
    end

    it "when nothing is present, returns an instance of the Thread adapter" do
      assert_equal :threaded, Litescheduler.backend
    end
  end
end
