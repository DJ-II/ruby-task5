require 'json'
require 'fileutils'
require 'digest'
require 'open3'

root = File.expand_path('..', __dir__)
queries = JSON.parse(File.read(File.join(root, 'config/stock_queries.json'), encoding: 'UTF-8'))
source_root = File.join(root, 'footage_sources')
destination = File.join(root, 'public/clips')
manifest_path = File.join(root, 'config/videos.local.json')
FileUtils.mkdir_p(destination)
abort 'FFmpeg and FFprobe are required.' unless system('ffmpeg', '-version', out: File::NULL, err: File::NULL) && system('ffprobe', '-version', out: File::NULL, err: File::NULL)

manifest = []
source_count = 0
queries.keys.sort.each do |mood|
  sources = Dir.glob(File.join(source_root, mood, '*')).select { |file| File.file?(file) && file.match?(/\.(mp4|mov|mkv|webm)\z/i) }.sort
  sources.each do |source|
    raw, status = Open3.capture2e('ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=nw=1:nk=1', source)
    duration = status.success? ? raw.to_f : 0
    if duration < 4.0
      warn "Skipping #{File.basename(source)}: footage must be at least 4 seconds long."
      next
    end
    source_count += 1
    segments = duration >= 15 ? 3 : duration >= 9 ? 2 : 1
    safe = File.basename(source, File.extname(source)).downcase.gsub(/[^a-z0-9]+/, '-')
    safe = safe.gsub(/\A-|\-\z/, '')[0, 35]
    prefix = "#{mood}-#{safe}-#{Digest::SHA256.hexdigest(File.basename(source))[0, 8]}"
    segments.times do |part|
      position = [0.2 + (duration - 4.0) * (part.to_f / segments), duration - 3.8].min
      id = "#{prefix}-#{part + 1}"
      video = File.join(destination, "#{id}.mp4")
      poster = File.join(destination, "#{id}.jpg")
      unless File.file?(video) && File.size(video) > 30_000
        command = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', position.to_s, '-i', source, '-t', '3.6', '-vf', 'scale=960:540:force_original_aspect_ratio=increase,crop=960:540,setsar=1', '-r', '24', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '27', '-pix_fmt', 'yuv420p', '-an', '-movflags', '+faststart', video]
        log, success = Open3.capture2e(*command)
        unless success.success? && File.file?(video) && File.size(video) > 30_000
          warn "Could not convert #{id}: #{log.lines.last(2).join}"
          File.delete(video) if File.exist?(video)
          next
        end
      end
      unless File.file?(poster)
        system('ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', '0.6', '-i', video, '-frames:v', '1', '-q:v', '3', poster)
      end
      manifest << { id: id, source_id: prefix, mood: mood, url: "/clips/#{id}.mp4", poster: "/clips/#{id}.jpg", description: File.basename(source), source: 'locally provided footage' }
      puts "#{id} ready"
    end
  end
end

if manifest.size < 3
  abort "Only #{manifest.size} clips prepared. Add at least three source videos to footage_sources/<mood> and run again."
end

File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")
puts "Prepared #{manifest.size} unique segments from #{source_count} source videos."
warn 'For a strong grade, add at least 50 different source videos across all moods.' if source_count < 50
puts 'Restart the app. Commit config/videos.local.json and public/clips/ for Render.'
