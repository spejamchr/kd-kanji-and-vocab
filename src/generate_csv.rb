# frozen_string_literal: true

# Create a CSV file of flashcards for importing to Anki
#
# Searches for data at ../cache/data.json. Use the ./anki_from_kanjidamage.rb
# script to generate that data.
#
# This script shouldn't filter data. For example, it shouldn't try to make
# decisions about which characters are kanji and deserve to be made into cards
# and which are just radicals and don't need carding. All those types of
# decisions happen in ./anki_from_kanjidamage.rb.
#
# This script's smarts are in sorting the given data into a decent learning order.

require_relative 'kd_anki.rb'
require 'json'
require 'csv'

# There are several types of flashcards to consider:
#
#   - Kanji meanings: Learn a basic meaning of a kanji
#   - Kanji onyomi: Learn a basic pronunciation for a kanji
#   - Vocabulary: Learn a word using one or more kanji. This can further be
#     broken into Kunyomi and Jukugo vocab.
#
# Anki supports "Notes", which can generate one or more flashcard per node.
# However, to have full control over the sorting of the cards, each note should
# have a single card. The order of the cards' entries is important.
#
# interface KanjiMeaningNote {
#   kanji: String;
#   index: Integer;
#   meaning: String;
#   components: String;
#   mnemonic: String;
# }
#
# interface KanjiOnyomiNote {
#   kanji: String;
#   index: Integer;
#   meaning: String;
#   components: String;
#   onyomi: String;
#   mnemonic: String;
# }
#
# interface VocabularyNote {
#   word: String;
#   index: Integer;
#   pronunciation: String;
#   definition: String;
# }

# Separate meaning cars from onyomi cards, and onyomi cards from vocab cards,
# so that onyomi only come once the meanings are learned, and vocab comes after
# onyomi are learned.
SEPARATION = 20

# @param data [PageData]
# @param kanjis [Array<String>]
def kanji_meaning_from_page_data(data, kanjis)
  {
    kanji: data.fetch(:character),
    index: kanjis.index(data.fetch(:character)) - SEPARATION,
    meaning: data.fetch(:translation),
    components: data.fetch(:components),
    mnemonic: data.fetch(:translation_mnemonic),
  }
end

# @param data [PageData]
# @param kanjis [Array<String>]
def kanji_onyomi_from_page_data(data, kanjis)
  # HACK: Raise an error if the index isn't found by subtracting 0
  {
    kanji: data.fetch(:character),
    index: kanjis.index(data.fetch(:character)) - 0,
    meaning: data.fetch(:translation),
    components: data.fetch(:components),
    onyomi: data.fetch(:onyomi).fetch(:value),
    mnemonic: data.fetch(:onyomi_mnemonic),
  }
end

# @param kunyomi [Kunyomi]
# @param data [PageData]
# @param kanjis [Array<String>]
def vocab_from_kunyomi(kunyomi, data, kanjis)
  {
    word: kunyomi.fetch(:word),
    index: kanjis.index(data.fetch(:character)) + SEPARATION,
    pronunciation: kunyomi.fetch(:pronunciation),
    definition: kunyomi.fetch(:definition),
  }
end

# @param jukugo [Jukugo]
# @param kanjis [Array<String>]
def vocab_from_jukugo(jukugo, kanjis)
  index = jukugo.fetch(:word).split(//).map { |k| kanjis.index(k) }.compact.max + SEPARATION

  {
    word: jukugo.fetch(:word),
    index: index,
    pronunciation: jukugo.fetch(:pronunciation),
    definition: jukugo.fetch(:definition),
  }
end

# @param data [PageData]
# @param kanjis [Array<String>]
def vocabs_from_page_data(data, kanjis)
  data.fetch(:kunyomi).map { |k| vocab_from_kunyomi(k, data, kanjis) } +
    data.fetch(:jukugo).map { |j| vocab_from_jukugo(j, kanjis) }
end

# @param filepath [String]
# @param hashes [Array<Hash>]
def hashes_to_csv(filepath, hashes)
  File.write(filepath, '') unless File.exist?(filepath)
  CSV.open(filepath, 'w') do |csv|
    keys = hashes.first.keys
    hashes.each do |h|
      csv << h.fetch_values(*keys)
    end
  end
end

data = JSON.parse(File.read(KDAnki::DATA_CACHE_PATH), symbolize_names: true)

kanjis = data.map { |e| e.fetch(:character) }.uniq

meanings = data.map { |e| kanji_meaning_from_page_data(e, kanjis) }.uniq { |m| m[:kanji] }

onyomis = data
  .reject { |e| e.dig(:onyomi, :kind) == 'none' }
  .map { |e| kanji_onyomi_from_page_data(e, kanjis) }
  .uniq { |o| o[:kanji] }

vocabs = data.flat_map { |e| vocabs_from_page_data(e, kanjis) }.uniq { |v| v[:word] }

# Ruby's sort methods are unstable. Use #with_index to make this a stable sort.
# @see https://stackoverflow.com/a/15442966
ordered = (meanings + onyomis + vocabs).sort_by.with_index { |v, i| [v.fetch(:index), i] }

# Straighten out the indices
ordered.each_with_index { |entry, index| entry[:index] = index }

# The indices are uniq now, so no need for special stable sorting
meanings.sort_by! { |m| m.fetch(:index) }
onyomis.sort_by! { |o| o.fetch(:index) }
vocabs.sort_by! { |v| v.fetch(:index) }

hashes_to_csv(KDAnki::MEANINGS_CSV_PATH, meanings)
hashes_to_csv(KDAnki::ONYOMIS_CSV_PATH, onyomis)
hashes_to_csv(KDAnki::VOCABS_CSV_PATH, vocabs)
