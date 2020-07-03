# frozen_string_literal: true

# Create a JSON file of structured data from downloaded KanjiDamage pages
#
# Searches for pages in ./html/. Use the ./download_kanjidamage.rb script to
# populate that directory.
#
# Use a functional style for everything.

require 'nokogiri'
require 'parallel'
require 'json'

require_relative 'kd_anki.rb'
require_relative 'maybe.rb'

# interface PageData {
#   index: Integer;
#   character: String;
#   translation: String;
#   components: String;
#   onyomi: Maybe<String>;
#   translation_mnemonic: String;
#   onyomi_mnemonic: String;
#   kunyomi: Array<Kunyomi>;
#   jukugo: Array<Jukugo>;
# }
#
# interface Kunyomi {
#   word: String;
#   pronunciation: String;
#   definition: String;
# }
#
# interface Jukugo {
#   word: String;
#   pronunciation: String;
#   definition: String;
# }

# @param val [any] - The thing to test
# @param msg [String] - message when the thing is not what you expect
# @param expected [any] - what you expect, either a Class, or a specific thing
# @yield when there is no error, yield to an optional block
# @yieldreturn [Array<String>] - the block should return other error messages
# @return [Array<String>] - an array of error messages
def obj_is(val, msg, expected)
  is_klass = expected.is_a?(Class)

  if is_klass ? val.is_a?(expected) : val == expected
    block_given? ? yield : []
  else
    ["Expected #{msg} but got #{val}"]
  end
end

# @param hash [Hash] - The hash containing the thing to test
# @param attr [any] - The key to the thing to test
# @param thing [any] - what you expect @see `obj_is` param `expected`
# @yield [val] when there is no error, yield `hash[attr]` to an optional block
# @yieldreturn [Array<String>] - the block should return other error messages
# @return [Array<String>] - an array of error messages
def attr_is(hash, attr, thing)
  val = hash[attr]

  obj_is(val, "#{attr} to be #{thing}", thing).yield_self do |a|
    a.empty? && block_given? ? yield(val) : a
  end
end

# @param hash [Hash] - The hash containing the thing to test
# @param attr [any] - The key to the thing to test
# @param expected_klass [Class]
# @return [Array<String>]
def maybe_wraps_a(hash, attr, expected_klass)
  attr_is(hash, attr, May::Be) do |m|
    klass = m.map(&:class).get_or_else_value(expected_klass)

    if klass == expected_klass
      []
    else
      ["Expected #{attr} to be May::Be<#{expected_klass}> but got May::Be<#{klass}>"]
    end
  end
end

# @param hash [Hash] - The hash containing the array of things to test
# @param attr [any] - The key to the array of things to test
# @yield [any] yields for each thing to test
# @yieldreturn [Array<String>] - an array of error messages
def check_array_with(hash, attr, &block)
  attr_is(hash, attr, Array) { |comps| comps.flat_map(&block) }
end

# @param jukugo [any]
# @return [Array<String>]
def jukugo_errors(jukugo)
  obj_is(jukugo, 'a jukugo to be a Hash', Hash) do
    attr_is(jukugo, :word, String) +
      attr_is(jukugo, :pronunciation, String) +
      attr_is(jukugo, :definition, String)
  end
end

# @param kunyomi [any]
# @return [Array<String>]
def kunyomi_errors(kunyomi)
  obj_is(kunyomi, 'a kunyomi to be a Hash', Hash) do
    attr_is(kunyomi, :word, String) +
      attr_is(kunyomi, :pronunciation, String) +
      attr_is(kunyomi, :definition, String)
  end
end

# @param data [any]
# @return [Array<String>]
def page_data_errors(data)
  obj_is(data, 'a page_data to be a Hash', Hash) do
    attr_is(data, :index, Integer) +
      attr_is(data, :character, String) +
      attr_is(data, :translation, String) +
      attr_is(data, :onyomi_mnemonic, String) +
      attr_is(data, :translation_mnemonic, String) +
      attr_is(data, :components, String) +
      maybe_wraps_a(data, :onyomi, String) +
      check_array_with(data, :kunyomi) { |c| kunyomi_errors(c) } +
      check_array_with(data, :jukugo) { |c| jukugo_errors(c) }
  end
end

# @param jukugo [Jukugo]
# @raise if jukugo is not a valid Jukugo object
def validate_jukugo(jukugo)
  errs = jukugo_errors(jukugo)
  return if errs.empty?

  # If the jukugo structure is invalid here it's my fault, so raise an error
  raise "Invalid jukugo:\n" + errs.join("\n")
end

# @param kunyomi [Kunyomi]
# @raise if kunyomi is not a valid Kunyomi object
def validate_kunyomi(kunyomi)
  errs = kunyomi_errors(kunyomi)
  return if errs.empty?

  # If the kunyomi structure is invalid here it's my fault, so raise an error
  raise "Invalid kunyomi:\n" + errs.join("\n").inspect
end

# @param data [PageData]
# @raise if data is not a valid PageData object
def validate_page_data(data)
  errs = page_data_errors(data)
  return if errs.empty?

  # If the data is invalid here it's my fault, so raise an error
  raise "Invalid page data:\n" + errs.join("\n")
end

# @param html [Nokogiri::HTML::Document]
# @param location [String]
# @return [May:Be<String>]
def text_at(html, location)
  s = html.search(location)
  s = yield(s) if block_given?
  s = s.text.strip.gsub("\r", '')

  s.empty? ? May.none : May.some(s)
end

# @param arr [Array<A>]
# @return [May::Be<A>]
def head(arr)
  arr.first ? May.some(arr.first) : May.none
end

# @param str [String]
# @return [May::Be<Integer>]
def str_to_int(str)
  str == str.to_i.to_s ? May.some(str.to_i) : May.none
end

# @param html [Nokogiri::HTML::Document]
# @return [May::Be<Integer>]
def get_page_index(html)
  text_at(html, '.navigation-header > .text-centered')
    .map { |str| str.match(/Number\s+(\d+)/m).to_a.reverse }
    .and_then { |arr| head(arr) }
    .and_then { |str| str_to_int(str) }
end

# @param html [Nokogiri::HTML::Document]
# @return [String]
def get_kanji_components(html)
  prefix = head(html.search('h1')).map(&:text).get_or_else_value('').strip.gsub(/\s+/, ' ')

  text_at(html, '.row.navigation-header + .row > .span8')
    .map { |text| text.gsub(/\s+/, ' ').delete_prefix(prefix).strip }
    .get_or_else_value('')
end

# @param node [Nokogiri::XML::Node]
# @return [May::Be<Nokogiri::XML::Node>]
def maybe_next(node)
  sibling = node.next_sibling
  sibling ? May.some(sibling) : May.none
end

# @param html [Nokogiri::HTML::Document]
# @param heading [String]
# @return [May::Be<Nokogiri::XML::Element>]
def table_under_heading(html, heading)
  head(html.search('h2')
    .select { |h2| h2.text == heading })
    .and_then { |n| maybe_next(n) }
    .and_then { |n| maybe_next(n) }
    .and_then { |el| el.name == 'table' ? May.some(el) : May.none }
end

# @param html [Nokogiri::HTML::Document]
# @return [May::Be<String>]
def get_onyomi(html)
  table_under_heading(html, 'Onyomi').and_then { |t| text_at(t, 'td', &:first) }
end

# @param html [Nokogiri::HTML::Document]
# @param heading [String]
# @return [May::Be<String>]
def mnemonic_at_heading(html, heading)
  table_under_heading(html, heading).and_then { |t| text_at(t, 'td + td') }
end

# @param html [Nokogiri::HTML::Document]
# @return [String]
def get_translation_mnemonic(html)
  mnemonic_at_heading(html, 'Mnemonic')
    .or_else { mnemonic_at_heading(html, 'Onyomi') }
    .or_else { text_at(html, '.description') }
    .get_or_else_value('')
end

# @param html [Nokogiri::HTML::Document]
# @return [String]
def get_onyomi_mnemonic(html)
  mnemonic_at_heading(html, 'Onyomi')
    .or_else { mnemonic_at_heading(html, 'Mnemonic') }
    .or_else { text_at(html, '.description') }
    .get_or_else_value('')
end

# @param str [String]
# @return [String]
def jparens(str)
  str.empty? ? str : "（#{str}）"
end

# @param str [String]
# @return [String]
def sub_jparens(str)
  str.gsub('(', '（').gsub(')', '）')
end

# @param spans [Nokogiri::XML::NodeSet]
# @return [String]
def prefix_in(spans)
  spans.first&.attr(:class) == 'particles' ? spans.first.text : ''
end

# @param spans [Nokogiri::XML::NodeSet]
# @return [String]
def suffix_in(spans)
  spans.last&.attr(:class) == 'particles' ? spans.last.text : ''
end

# @param spans [Nokogiri::XML::NodeSet]
# @return [String]
def kanji_in(spans)
  text_at(spans, '.kanji_character').get_or_else_value('')
end

# @param spans [Nokogiri::XML::NodeSet]
# @return [String]
def tail_in(spans)
  parts = kanji_in(spans).split(/[*＊]/)
  parts.count == 2 ? parts.last : ''
end

# @param kanji [String]
# @param table_row [Nokogiri::XML::Element]
# @return May::Be<String>
def kunyomi_word(kanji, table_row)
  head(table_row.search('td')).map { |td| td.search('span') }.map do |spans|
    jparens(prefix_in(spans)) + kanji + tail_in(spans) + jparens(suffix_in(spans))
  end
end

# @param table_row [Nokogiri::XML::Element]
# @return May::Be<String>
def kunyomi_pronunciation(table_row)
  head(table_row.search('td')).map { |td| td.search('span') }.map do |spans|
    jparens(prefix_in(spans)) + kanji_in(spans) + jparens(suffix_in(spans))
  end
end

# @param table_row [Nokogiri::XML::Element]
# @param character [String]
# @return [May::Be<Kunyomi>]
def kunyomi_from_tr(table_row, character)
  May.some({})
    .assign(:word) { kunyomi_word(character, table_row) }
    .assign(:pronunciation) { kunyomi_pronunciation(table_row) }
    .assign(:definition) { text_at(table_row, 'td + td') }
end

# @param html [Nokogiri::HTML::Document]
# @param character [String]
# @return [Array<Kunyomi>]
def get_kunyomi(html, character)
  table_under_heading(html, 'Kunyomi')
    .map { |t| t.search('tr').to_a }
    .get_or_else_value([])
    .map { |tr| kunyomi_from_tr(tr, character).get_or_else_value(nil) }
    .compact
    .each { |o| validate_kunyomi(o) }
end

# @param spans [Nokogiri::XML::NodeSet]
# @return [String]
def jukugo_kanji_in(spans)
  kanji_in(spans).gsub(/\(.+/, '')
end

# @param spans [Nokogiri::XML::NodeSet]
# @return [String]
def jukugo_pronunciation_in(spans)
  kanji_in(spans).gsub(/.+\(/, '').gsub(')', '')
end

# @param kanji [String]
# @param table_row [Nokogiri::XML::Element]
# @return [May::Be<String>]
def jukugo_word(table_row)
  head(table_row.search('td')).map { |td| td.search('span') }.map do |spans|
    jparens(prefix_in(spans)) + jukugo_kanji_in(spans) + jparens(suffix_in(spans))
  end
end

# @param table_row [Nokogiri::XML::Element]
# @return [May::Be<String>]
def jukugo_pronunciation(table_row)
  head(table_row.search('td')).map { |td| td.search('span') }.map do |spans|
    jparens(prefix_in(spans)) + jukugo_pronunciation_in(spans) + jparens(suffix_in(spans))
  end
end

# @param table_row [Nokogiri::XML::Element]
# @return [May::Be<Jukugo>]
def jukugo_from_tr(table_row)
  May.some({})
    .assign(:word) { jukugo_word(table_row) }
    .assign(:pronunciation) { jukugo_pronunciation(table_row) }
    .assign(:definition) { text_at(table_row, 'td + td') }
end

# @param html [Nokogiri::HTML::Document]
# @return [Array<Jukugo>]
def get_jukugo(html)
  table_under_heading(html, 'Jukugo')
    .map { |t| t.search('tr').to_a }
    .get_or_else_value([])
    .map { |tr| jukugo_from_tr(tr).get_or_else_value(nil) }
    .compact
    .each { |o| validate_jukugo(o) }
end

# @param html [Nokogiri::HTML::Document]
# @return [May::Be<PageData>]
def get_page_data(html)
  May.some({})
    .assign(:index) { get_page_index(html) }
    .assign(:translation) { text_at(html, 'h1 > .translation') }
    .assign(:character) { text_at(html, 'h1 > .kanji_character') }
    .map { |d| d.merge(components: get_kanji_components(html)) }
    .map { |d| d.merge(onyomi: get_onyomi(html)) }
    .map { |d| d.merge(onyomi_mnemonic: get_onyomi_mnemonic(html)) }
    .map { |d| d.merge(translation_mnemonic: get_translation_mnemonic(html)) }
    .map { |d| d.merge(kunyomi: get_kunyomi(html, d[:character])) }
    .map { |d| d.merge(jukugo: get_jukugo(html)) }
    .effect { |d| validate_page_data(d) }
end

# @param filepath [String]
# @return Nokogiri::HTML::Document
def get_html(filepath)
  Nokogiri.HTML(File.read(filepath))
end

# @param filepath [String]
# @return [May::Be<PageData>]
def data_at(filepath)
  puts "visiting #{filepath}".ljust(100) + "at #{Time.now.to_f}s".rjust(20)
  get_page_data(get_html(filepath))
end

# @return [Array<String>] - The paths of html files with all the data
def paths
  Dir[File.join(KDAnki::HTML_CACHE_DIR, '*')]
end

# @return [Array<PageData>]
def all_pages
  Parallel
    .map(paths) { |path| data_at(path).get_or_else_value(nil) }
    .compact
    .sort_by { |data| data[:index] }
end

# Create a JSON file of all the data
File.write(KDAnki::DATA_CACHE_PATH, all_pages.to_json)
