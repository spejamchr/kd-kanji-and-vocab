# frozen_string_literal: true

module KDAnki
  ROOT_DIR = File.dirname(__dir__).freeze
  CACHE_DIR = File.join(ROOT_DIR, 'cache').freeze
  DATA_CACHE_PATH = File.join(CACHE_DIR, 'data.json').freeze
  HTML_CACHE_DIR = File.join(CACHE_DIR, 'html').freeze
end