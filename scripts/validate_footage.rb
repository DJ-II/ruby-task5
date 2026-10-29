require 'json'
require 'open3'

root = File.expand_path('..', __dir__)
path = File.join(root, 'config/videos.local.json')
abort 'No local video manifest. Run scripts/import_local_footage.rb or scripts/cache_clips.rb.' unless File.file?(path)
clips = JSON.parse(File.read(path, encoding: 'UTF-8'))
source_ids = clips.map { |clip| clip.fetch('source_id', clip.fetch('id')) }.uniq
bad = []
clips.each do |clip|
  file = File.join(root, 'public', clip.fetch('url').sub(%r{\A/}, ''))
  poster = File.join(root, 'public', clip.fetch('poster').sub(%r{\A/}, ''))
  if !File.file?(file) || !File.file?(poster)
    bad << "#{clip.fetch('id')}: MP4 or JPEG missing"
    next
  end
  output, status = Open3.capture2e('ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=codec_name,width,height', '-of', 'json', file)
  stream = status.success? ? JSON.parse(output).fetch('streams', []).first : nil
  unless stream && stream['codec_name'] == 'h264' && stream['width'] >= 640 && stream['height'] >= 360
    bad << "#{clip.fetch('id')}: missing or unsupported H.264 video"
  end
end
puts "Video fragments: #{clips.length}, different source videos: #{source_ids.length}, invalid: #{bad.length}"
puts bad.join("\n") unless bad.empty?
abort 'Footage validation failed.' unless bad.empty?
warn 'More real source videos will improve trailer variety.' if source_ids.length < 50
