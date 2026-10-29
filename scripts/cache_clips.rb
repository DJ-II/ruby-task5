require 'json'
require 'fileutils'
require 'open3'

root = File.expand_path('..', __dir__)
manifest = JSON.parse(File.read(File.join(root, 'config/videos.json'), encoding: 'UTF-8'))
destination = File.join(root, 'public/clips')
FileUtils.mkdir_p(destination)
abort 'FFmpeg is required. Install with: winget install Gyan.FFmpeg' unless system('ffmpeg', '-version', out: File::NULL, err: File::NULL)

failures = []
manifest.each_with_index do |clip, index|
  name = clip.fetch('id')
  output = File.join(destination, "#{name}.mp4")
  poster = File.join(destination, "#{name}.jpg")
  puts "[#{index + 1}/#{manifest.length}] #{name}"
  unless File.file?(output) && File.size(output) > 40_000
    File.delete(output) if File.exist?(output)
    cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', '0.3', '-i', clip.fetch('url'), '-t', '3.5', '-vf', 'scale=960:-2,setsar=1', '-r', '24', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '26', '-pix_fmt', 'yuv420p', '-an', '-movflags', '+faststart', output]
    output_text, status = Open3.capture2e(*cmd)
    unless status.success? && File.file?(output) && File.size(output) > 40_000
      warn "Unable to retrieve #{name}: #{output_text.lines.last(3).join.strip}"
      File.delete(output) if File.exist?(output)
      failures << name
      next
    end
  end
  unless File.exist?(poster)
    system('ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', '0.6', '-i', output, '-frames:v', '1', '-q:v', '3', poster)
  end
end
puts "Cached #{manifest.length - failures.length} of #{manifest.length} videos."
puts "Unavailable: #{failures.join(', ')}" unless failures.empty?
puts "Next: git add config/videos.json public/clips && git commit -m 'Bundle stock footage'"
