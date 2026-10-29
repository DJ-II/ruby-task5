require 'net/http'
require 'json'
require 'uri'

base = ARGV.fetch(0, 'http://localhost:4567').sub(%r{/\z}, '')
def read_json(base, path)
  uri = URI(base + path)
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 40) { |http| http.get(uri.request_uri) }
  raise "HTTP #{response.code} #{path}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body)
end

config = read_json(base, '/api/config')
raise 'Need at least two regions' if config.fetch('regions').size < 2
regions = config.fetch('regions').map { |item| item.fetch('code') }
seed = '1234567891234567'
regions.each do |region|
  args = URI.encode_www_form(seed: seed, region: region, page: 1, size: 10, reviews: 2)
  low = read_json(base, "/api/movies?#{args}&likes=0").fetch('movies')
  half = read_json(base, "/api/movies?#{args}&likes=0.5").fetch('movies')
  high = read_json(base, "/api/movies?#{args}&likes=5").fetch('movies')
  raise "Wrong indexes for #{region}" unless low.map { |item| item.fetch('index') } == (1..10).to_a
  raise "Wrong likes for #{region}" unless low.all? { |m| m['likes'] == 0 } && high.all? { |m| m['likes'] == 5 } && half.all? { |m| [0, 1].include?(m['likes']) }
  raise "Core data changed with likes for #{region}" unless low.zip(high).all? { |a, b| a.reject { |key, _| key == 'likes' } == b.reject { |key, _| key == 'likes' } }
  one = read_json(base, "/api/movie/1?#{args}&likes=5")
  two = read_json(base, "/api/movie/1?#{args}&likes=5")
  raise "Non-repeatable details #{region}" unless one == two
  raise "Missing video scenes #{region}" unless one.fetch('trailer').fetch('scenes').size == 3
  puts "#{region}: pagination, likes independence, seed and trailers OK"
end
media = read_json(base, '/api/media-status')
puts "Local MP4 clips: #{media.fetch('local')}/#{media.fetch('total')}"
puts 'HTTP smoke test passed.'
