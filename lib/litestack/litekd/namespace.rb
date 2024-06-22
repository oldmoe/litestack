# frozen_string_literal: true

module Litekd::Namespace
  def namespace=(namespace)
    Thread.current[:litekd_namespace] = namespace
  end

  def namespace
    Thread.current[:litekd_namespace]
  end

  def namespaced_key(key)
    namespace ? "#{namespace}:#{key}" : key
  end
end
