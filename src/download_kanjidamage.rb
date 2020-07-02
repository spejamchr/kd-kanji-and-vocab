# frozen_string_literal: true

# Visit http://www.kanjidamage.com/kanji and download the linked kanji pages
#
# Store the pages in ./html/, and only download missing pages. To redownload
# all the pages, delete all files in the directory before running this script.

require 'mechanize'

BASE_URI = 'http://www.kanjidamage.com'
INDEX_URI = "#{BASE_URI}/kanji"
SAVE_DIR = File.join(File.dirname(__dir__), 'cache', 'html')

def adjusted_name(name)
  name
    .split('-')
    .yield_self { |a| [a.first.rjust(4, '0'), *a[1..-1]].join('-') }
    .split('-%')
    .first
    .yield_self { |n| n.chomp('.html') + '.html' }
end

saved_paths = Dir
  .children(SAVE_DIR)
  .map { |p| File.basename(p, File.extname(p)).chomp('.html') }
  .map { |f| f.split('-').first.to_i.to_s }
  .map { |i| "/kanji/#{i}" }

uris = Mechanize.new.get(INDEX_URI)
  .search('table')
  .first
  .search('a[href]')
  .map { |a| a[:href] }
  .map { |href| href.scan(%r{\/kanji\/\d+}).first }
  .compact
  .yield_self { |hrefs| hrefs - saved_paths }
  .map { |href| URI.parse(BASE_URI + href) }
  .tap { |us| puts "Downloading #{us.count} pages..." }

uris.each do |uri|
  sleep 0.1 # Don't overload the website
  puts "Visiting #{uri} at #{Time.now.to_f}"
  page = Mechanize.new.get(uri)
  File.write(File.join(SAVE_DIR, adjusted_name(page.filename)), page.body)
end
