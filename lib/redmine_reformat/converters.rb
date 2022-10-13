# frozen_string_literal: true

require 'json'
require_relative 'converters/configured_converters'

module RedmineReformat
  module Converters
    class << self
      def from_json(json)
        cfg = JSON.parse(json, symbolize_names: true)
        ConfiguredConverters.new(cfg) if cfg
      end
    end
  end
end
