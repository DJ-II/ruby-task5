require 'json'

root = File.expand_path('..', __dir__)
source = File.join(root, 'config/videos.json')
destination = File.join(root, 'config/videos.local.json')
clips = JSON.parse(File.read(source, encoding: 'UTF-8'))
local = clips.filter_map do |clip|
  id = clip.fetch('id')
  video = File.join(root, 'public/clips', "#{id}.mp4")
  image = File.join(root, 'public/clips', "#{id}.jpg")
  next unless File.file?(video) && File.size(video) > 30_000 && File.file?(image)
  clip.merge('url' => "/clips/#{id}.mp4", 'poster' => "/clips/#{id}.jpg", 'source_id' => id)
end
abort "Only #{local.size} local clips are available. Need at least 3." if local.size < 3
File.write(destination, JSON.pretty_generate(local) + "\n")
puts "Local catalog created: #{local.size} of #{clips.size} real MP4 files."
puts 'Restart the app, run scripts/validate_footage.rb and commit local MP4 files to Git.'
