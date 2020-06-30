# frozen_string_literals: true

require 'mechanize'
require 'json'
require '../other_ruby/maybe.rb'

BASE_URL = 'http://www.kanjidamage.com'
FIRST_KANJI = "#{BASE_URL}/kanji/1"
SAVE_FILE = 'data.json'

# interface PageData {
#   index: Integer;
#   character: Component;
#   translation: String;
#   components: Array<Component>;
#   onyomi: Maybe<String>;
#   mnemonic: String;
#   kunyomi: Array<Kunyomi>;
#   jukugo: Array<Jukugo>;
#   next_page: Maybe<URI::HTTP>;
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
#   components: Array<Component>;
# }
#
# interface KanjiComponent {
#   kind: 'kanji';
#   kanji: String;
# }
#
# interface RadicalComponent {
#   kind: 'radical';
#   radical: String;
# }
#
# type Component = KanjiComponent | RadicalComponent

# @param kanji [String]
# @return [KanjiComponent]
def kanji_component(kanji)
  { kind: 'kanji', kanji: kanji }
end

# @param radical [String]
# @return [RadicalComponent]
def radical_component(radical)
  { kind: 'radical', radical: radical }
end

# @param val - The thing to test
# @param msg [String] - message when the thing is not what you expect
# @param expected - what you expect, either a Class, or a specific thing
# @yield when there is no error, yield to an optional block
# @yieldreturn [Array<String>] - the block should return other error messages
# @return [Array<String>] - any error message
def obj_is(val, msg, expected)
  is_klass = expected.is_a?(Class)
  if is_klass ? val.is_a?(expected) : val == expected
    block_given? ? yield : []
  else
    ["Expected #{msg} but got #{val}"]
  end
end

def attr_is(hash, attr, thing)
  val = hash[attr]
  obj_is(val, "#{attr} to be #{thing}", thing).yield_self do |a|
    a.empty? && block_given? ? yield(val) : a
  end
end

def kanji_component_errors(comp)
  obj_is(comp, 'a kanji_component to be a Hash', Hash) do
    attr_is(comp, :kind, 'kanji') { attr_is(comp, :kanji, String) }
  end
end

def valid_kanji_component?(component)
  kanji_component_errors(component).empty?
end

def radical_component_errors(comp)
  obj_is(comp, 'a radical_component to be a Hash', Hash) do
    attr_is(comp, :kind, 'radical') { attr_is(comp, :radical, String) }
  end
end

def valid_radical_component?(component)
  radical_component_errors(component).empty?
end

def component_errors(component)
  return [] if valid_component?(component)

  kanji_component_errors(component) + radical_component_errors(component)
end

def valid_component?(component)
  valid_kanji_component?(component) || valid_radical_component?(component)
end

def jukugo_errors(jukugo)
  obj_is(jukugo, 'a jukugo to be a Hash', Hash) do
    attr_is(jukugo, :word, String) + attr_is(jukugo, :pronunciation, String) +
      attr_is(jukugo, :definition, String) +
      attr_is(jukugo, :components, Array) do |comps|
        comps.flat_map { |c| component_errors(c) }
      end
  end
end

def valid_jukugo?(jukugo)
  jukugo_errors(jukugo).empty?
end

def validate_jukugo(jukugo)
  return valid_jukugo?(jukugo)

  # If the jukugo structure is invalid here it's my fault, so raise an error
  raise "Invalid jukugo:\n" + jukugo_errors(jukugo).join("\n")
end

def kunyomi_errors(kunyomi)
  obj_is(kunyomi, 'a kunyomi to be a Hash', Hash) do
    attr_is(kunyomi, :word, String) + attr_is(kunyomi, :pronunciation, String) +
      attr_is(kunyomi, :definition, String)
  end
end

def valid_kunyomi?(kunyomi)
  kunyomi_errors(kunyomi).empty?
end

def validate_kunyomi(kunyomi)
  return if valid_kunyomi?(kunyomi)

  # If the kunyomi structure is invalid here it's my fault, so raise an error
  raise "Invalid kunyomi:\n" + kunyomi_errors(kunyomi).join("\n").inspect
end

def maybe_wraps_a(hash, attr, expected_klass)
  attr_is(hash, attr, May::Be) do |m|
    klass = m.map(&:class).get_or_else_value(expected_klass)
    if klass == expected_klass
      []
    else
      [
        "Expected #{attr} to be May::Be<#{expected_klass}> but got May::Be<#{klass}>"
      ]
    end
  end
end

def page_data_errors(data)
  obj_is(data, 'a page_data to be a Hash', Hash) do
    attr_is(data, :index, Integer) + component_errors(data[:character]) +
      attr_is(data, :translation, String) +
      attr_is(data, :mnemonic, String) +
      attr_is(data, :components, Array) do |comps|
        comps.flat_map { |c| component_errors(c) }
      end +
      maybe_wraps_a(data, :onyomi, String) +
      attr_is(data, :kunyomi, Array) do |kuns|
        kuns.flat_map { |k| kunyomi_errors(k) }
      end +
      attr_is(data, :jukugo, Array) do |juks|
        juks.flat_map { |j| jukugo_errors(j) }
      end +
      maybe_wraps_a(data, :next_page, URI::HTTP)
  end
end

def valid_page_data?(data)
  page_data_errors(data).empty?
end

def validate_page_data(data)
  # If the data is invalid here it's my fault, so raise an error
  unless valid_page_data?(data)
    raise "Invalid page data:\n" + page_data_errors(data).join("\n")
  end
end

# @param arr [Array<A>]
# @return [May::Be<A>]
def head(arr)
  arr.first ? May::Some.new(arr.first) : May::None.new
end

def get_page_index(html)
  text_at(html, '.navigation-header > .text-centered').and_then do |str|
    head(str.match(/Number\s+(\d+)/m).to_a.reverse)
  end
    .and_then { |str| str_to_int(str) }
end

def get_character(html)
  text_at(html, 'h1 > .kanji_character').map { |k| kanji_component(k) }
    .or_else do
    head(html.search('h1 > .kanji_character > img[alt]')).map do |img|
      radical_component(img[:alt])
    end
  end
end

# @param html [Mechanize::Page]
# @return [Array<Component>]
def get_kanji_components(html)
  # TODO: Will this always work?
  html.search('.span8 > .component').map do |c|
    if c.text.empty?
      radical_component(c.search('[alt]').first['alt'])
    else
      kanji_component(c.text)
    end
  end
end

# @param html [Mechanize::Page]
# @return [May::Be<String>]
def get_onyami(html)
  table_under_heading(html, 'Onyomi').and_then { |t| text_at(t, 'td', &:first) }
end

# @param html [Mechanize::Page]
# @param heading [String]
# @return [May::Be<Nokogiri::XML::Element>]
def table_under_heading(html, heading)
  head(html.search('h2').select { |h2| h2.text == heading }).map(&:next_sibling)
    .map(&:next_sibling)
    .and_then { |el| el.name == 'table' ? May::Some.new(el) : May::None.new }
end

# @param html [Mechanize::Page]
# @param location [String]
# @return [May:Be<String>]
def text_at(html, location)
  s = html.search(location)
  s = yield(s) if block_given?
  s = s.text.strip.gsub("\r", '')
  s.empty? ? May::None.new : May::Some.new(s)
end

# @param html [Mechanize::Page]
# @return [String]
def get_mnemonic(html)
  str =
    %w[Onyomi Mnemonic].map do |heading|
      table_under_heading(html, heading).and_then { |t| text_at(t, 'td + td') }
        .get_or_else_value(nil)
    end
      .compact
      .join("\n\n")

  str.empty? ? text_at(html, '.description').get_or_else_value('') : str
end

# @param html [Mechanize::Page]
# @return [Array<Kunyomi>]
def get_kunyomi(html, character)
  return [] unless character[:kind] == 'kanji'

  kanji = character[:kanji]

  table_under_heading(html, 'Kunyomi').map do |t|
    t.search('tr').map do |tr|
      pronunciation = text_at(tr, 'td', &:first)

      May::Some.new({}).assign(:word) do
        pronunciation.map { |p| kanji + p.gsub(/^.*\*/, '') }
      end
        .assign(:pronunciation) { pronunciation }
        .assign(:definition) { text_at(tr, 'td', &:last) }
        .effect { |o| validate_kunyomi(o) }
        .get_or_else_value(nil)
    end
      .compact
  end
    .get_or_else_value([])
end

# @param html [Mechanize::Page]
# @return [Array<Jukugo>]
def get_jukugo(html)
  table_under_heading(html, 'Jukugo').map do |t|
    t.search('tr').map do |tr|
      children = tr.search('td > p').children
      components =
        children.search('.component').map { |c| kanji_component(c.text) }

      text_at(tr, 'td', &:first).map do |w|
        {
          word: w.gsub(/\((.*)\)/, '').strip.split("\n").first,
          pronunciation: $1
        }
      end
        .assign(:definition) { head(children).map(&:text).map(&:strip) }
        .map { |h| h.merge(components: components) }
        .effect { |h| validate_jukugo(h) }
        .get_or_else_value(nil)
    end
      .compact
  end
    .get_or_else_value([])
end

# @param html [Mechanize::Page]
# @return [May::Be<Mechanize::Page::Link>]
def get_next_page_link(html)
  next_page = html.links.find { |l| l.text.match?(/Next/) }
  next_page ? May::Some.new(next_page.resolved_uri) : May::None.new
end

def str_to_int(str)
  str == str.to_i.to_s ? May::Some.new(str.to_i) : May::None.new
end

# @param html [Mechanize::Page]
# @return [May::Be<PageData>]
def get_page_data(html)
  May::Some.new({}).assign(:translation) { text_at(html, 'h1 > .translation') }
    .assign(:index) { get_page_index(html) }
    .assign(:character) { get_character(html) }
    .map { |d| d.merge(components: get_kanji_components(html)) }
    .map { |d| d.merge(onyomi: get_onyami(html)) }
    .map { |d| d.merge(mnemonic: get_mnemonic(html)) }
    .map { |d| d.merge(kunyomi: get_kunyomi(html, d[:character])) }
    .map { |d| d.merge(jukugo: get_jukugo(html)) }
    .map { |d| d.merge(next_page: get_next_page_link(html)) }
    .effect { |d| validate_page_data(d) }
end

# @param agent [Mechanize]
# @param uri [String]
# @return [May::Be<Mechanize::Page>]
def visit(agent, uri)
  May::Some.new(agent.get(uri))
rescue StandardError
  May::None.new
end

# @param agent [Mechanize]
# @param uri [String | URI::HTTP]
# @return [May::Be<Mechanize::Page>]
def data_at(agent, uri)
  puts "visiting #{uri}".ljust(100) + "at #{Time.now.to_f}s".rjust(20)
  visit(agent, uri).and_then { |page| get_page_data(page) }
end

def fill_pages(agent, pages)
  return pages if pages.empty?

  pages.last[:next_page].and_then { |uri| data_at(agent, uri) }.map do |data|
    fill_pages(agent, pages + [data])
  end
    .get_or_else_value(pages)
end

def main
  agent = Mechanize.new

  pages =
    data_at(agent, FIRST_KANJI).map { |data| [data] }.get_or_else_value([])

  pages = fill_pages(agent, pages)

  pages_json = JSON.pretty_generate(pages)

  File.write(SAVE_FILE, pages_json)
end

main
