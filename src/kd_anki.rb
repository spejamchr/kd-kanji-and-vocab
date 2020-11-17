# frozen_string_literal: true

module KDAnki
  ROOT_DIR = File.dirname(__dir__).freeze
  CACHE_DIR = File.join(ROOT_DIR, 'cache').freeze
  DATA_CACHE_PATH = File.join(CACHE_DIR, 'data.json').freeze
  HTML_CACHE_DIR = File.join(CACHE_DIR, 'html').freeze
  MEANINGS_CSV_PATH = File.join(CACHE_DIR, 'meanings.csv').freeze
  ONYOMIS_CSV_PATH = File.join(CACHE_DIR, 'onyomis.csv').freeze
  VOCABS_CSV_PATH = File.join(CACHE_DIR, 'vocabs.csv').freeze
  CORE6K_PATH = File.join(CACHE_DIR, 'core6k.txt').freeze
  CORE_CSV_PATH = File.join(CACHE_DIR, 'core6k.csv').freeze

  HIRAGANA = ("\u3041".."\u3093").map(&:freeze).freeze
  KATAKANA = ("\u30A1".."\u30F6").map(&:freeze).freeze
  ASCII = ("\u0000".."\u007F").map(&:freeze).freeze
  PUNCTUATION = (
    ("\uff01".."\uff19").to_a +
    ("\uff1a".."\uff3a").to_a +
    ["　", "ー"]
  ).map(&:freeze).freeze
  NON_KANJI = (HIRAGANA + KATAKANA + ASCII + PUNCTUATION).freeze
end
