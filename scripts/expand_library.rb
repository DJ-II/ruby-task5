require 'net/http'
require 'json'
require 'uri'

key = ENV.fetch('PEXELS_API_KEY', '').strip
abort 'Set PEXELS_API_KEY before running this script.' if key.empty?
root = File.expand_path('..', __dir__)
config = File.join(root, 'config/videos.json')
clips = JSON.parse(File.read(config, encoding: 'UTF-8'))
queries = JSON.parse(File.read(File.join(root, 'config/stock_queries.json'), encoding: 'UTF-8'))
known = clips.map { |clip| clip.fetch('id') }

queries.each do |mood, phrases|
  phrases.each do |phrase|
    uri = URI('https://api.pexels.com/v1/videos/search')
    uri.query = URI.encode_www_form(query: phrase, per_page: 36, orientation: 'landscape', size: 'medium')
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = key
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 25) { |http| http.request(request) }
    unless response.is_a?(Net::HTTPSuccess)
      warn "Skipping #{phrase}: HTTP #{response.code}"
      next
    end
    data = JSON.parse(response.body)
    added = 0
    data.fetch('videos', []).each do |item|
      break if added >= 8
      id = "pexels-#{item.fetch('id')}"
      next if known.include?(id)
      next if item.fetch('width', 0).to_i <= item.fetch('height', 0).to_i
      video_files = item.fetch('video_files', []).select do |file|
        file['file_type'] == 'video/mp4' && file['width'].to_i.between?(800, 1920) && file['height'].to_i >= 450
      end
      file = video_files.min_by { |candidate| (candidate.fetch('width').to_i - 1280).abs }
      next unless file && file['link']
      clips << {
        'id' => id,
        'mood' => mood,
        'url' => file.fetch('link'),
        'poster' => item.fetch('image'),
        'source' => item.fetch('url'),
        'description' => phrase
      }
      known << id
      added += 1
    end
    puts "#{mood} / #{phrase}: +#{added}"
  rescue JSON::ParserError, IOError, SystemCallError, Timeout::Error => error
    warn "Skipped #{phrase}: #{error.message}"
  end
end
File.write(config, JSON.pretty_generate(clips) + "\n")
puts "Catalog updated: #{clips.length} source clips."
puts 'Run ruby scripts/cache_clips.rb to prepare short local MP4 files.'
