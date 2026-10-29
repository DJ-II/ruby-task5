require 'fileutils'
require 'open3'
require 'tmpdir'
require 'zip'

class TrailerExporter
  class ExportError < StandardError; end

  def self.available?
    system('ffmpeg', '-version', out: File::NULL, err: File::NULL)
  end

  def initialize(seed:, region:, page:, likes:, reviews:)
    @generator = MovieGenerator.new(seed: seed, region: region)
    @page = MovieGenerator.validate_positive(page, 'page')
    @likes = MovieGenerator.validate_average(likes)
    @reviews = MovieGenerator.validate_average(reviews)
  end

  def entries
    @entries ||= @generator.movies(page: @page, size: 10, likes: @likes, reviews: @reviews).fetch(:movies).map do |movie|
      movie.merge(trailer: @generator.trailer(index: movie.fetch(:index)))
    end
  end

  def validate!
    raise ExportError, 'FFmpeg is required for video export.' unless self.class.available?
    entries.each do |movie|
      movie.fetch(:trailer).fetch(:scenes).each do |scene|
        path = video_path(scene)
        raise ExportError, "Missing local MP4 for #{scene.fetch(:clip_id)}. Import footage first." unless File.file?(path)
      end
    end
  end

  def perform
    validate!
    directory = Dir.mktmpdir('moviegenerator-export-')
    zip_path = File.join(directory, "MovieGenerator-page-#{@page}.zip")
    names = {}
    Zip::File.open(zip_path, create: true) do |zip|
      entries.each_with_index do |movie, i|
        safe_title = movie.fetch(:title).unicode_normalize(:nfc).gsub(/[\\\/:*?"<>|\x00-\x1f]/, ' ').gsub(/\s+/, ' ').strip[0, 85].gsub(/[. ]+\z/, '')
        safe_title = 'Movie' if safe_title.empty?
        key = safe_title.downcase
        names[key] = names.fetch(key, 0) + 1
        suffix = names[key] > 1 ? " (#{movie.fetch(:index)})" : ''
        filename = "#{safe_title}#{suffix}.mp4"
        target = File.join(directory, "movie-#{movie.fetch(:index)}.mp4")
        render_trailer(movie.fetch(:trailer), target, directory)
        zip.add(filename, target)
        yield(i + 1, entries.size) if block_given?
      end
    end
    [zip_path, directory]
  rescue StandardError
    FileUtils.remove_entry(directory) if directory && Dir.exist?(directory)
    raise
  end

  private

  def video_path(scene)
    id = scene.fetch(:clip_id)
    raise ExportError, 'Invalid clip id.' unless id.match?(/\A[a-zA-Z0-9_-]+\z/)
    File.join(MovieGenerator::ROOT, 'public', 'clips', "#{id}.mp4")
  end

  def soundtrack_path(story)
    name = File.basename(story.fetch(:audio_url, '').to_s)
    return nil unless name.match?(/\A[a-z0-9-]+\.mp3\z/)
    path = File.join(MovieGenerator::ROOT, 'public', 'audio', name)
    File.file?(path) ? path : nil
  end

  def escape_filter_path(path)
    path.tr('\\', '/').gsub(':', '\\\\:').gsub("'", "\\\\'").gsub(',', '\\\\,')
  end

  def font_option
    candidates = [ENV['TRAILER_FONT_FILE'], 'C:/Windows/Fonts/arialbd.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', '/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf']
    found = candidates.compact.find { |path| File.file?(path) }
    found ? "fontfile='#{escape_filter_path(found)}'" : "font='Sans'"
  end

  def render_trailer(story, output, directory)
    scenes = story.fetch(:scenes)
    width = Integer(ENV.fetch('EXPORT_WIDTH', '960'))
    width = 960 unless [640, 960, 1280].include?(width)
    height = width * 9 / 16
    inputs = scenes.flat_map { |scene| ['-i', video_path(scene)] }
    total_duration = scenes.sum { |scene| scene.fetch(:duration).to_f }
    filters = scenes.map.with_index do |scene, index|
      duration = scene.fetch(:duration).to_f
      speed = scene.fetch(:speed).to_f
      caption_path = File.join(directory, "caption-#{index}.txt")
      File.write(caption_path, scene.fetch(:caption).to_s, encoding: 'UTF-8')
      zoom = [[scene.fetch(:zoom).to_f, 1.0].max, 1.2].min
      width_scaled = (width * zoom).ceil / 2 * 2 + 4
      height_scaled = (height * zoom).ceil / 2 * 2 + 4
      fade_out_at = (duration - 0.24).round(2)
      brightness = [0.0, ((scene.fetch(:hue).to_i % 5) - 2) * 0.008].max
      fade_in = index == 0 ? '0.05' : '0.15'
      "[#{index}:v]trim=duration=#{(duration * speed + 0.05).round(3)},setpts=(PTS-STARTPTS)/#{speed},fps=24,scale=#{width_scaled}:#{height_scaled}:force_original_aspect_ratio=increase,crop=#{width}:#{height},setsar=1,eq=brightness=#{brightness}:saturation=0.90,drawtext=#{font_option}:textfile='#{escape_filter_path(caption_path)}':fontcolor=white:fontsize=#{(width * 0.047).round}:box=1:boxcolor=black@0.40:boxborderw=18:x=(w-text_w)/2:y=(h-text_h)/2:fix_bounds=1,fade=t=in:st=0:d=#{fade_in},fade=t=out:st=#{fade_out_at}:d=0.20,trim=duration=#{duration},setpts=PTS-STARTPTS[v#{index}]"
    end
    filters << scenes.each_index.map { |i| "[v#{i}]" }.join + "concat=n=#{scenes.size}:v=1:a=0[outv]"
    command = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-nostdin', '-y', *inputs]
    soundtrack = soundtrack_path(story)
    if soundtrack
      command += ['-stream_loop', '-1', '-i', soundtrack]
    end
    command += ['-filter_complex', filters.join(';'), '-map', '[outv]']
    if soundtrack
      command += ['-map', "#{scenes.size}:a:0", '-af', "volume=0.24,afade=t=in:st=0:d=0.3,afade=t=out:st=#{(total_duration-0.7).round(2)}:d=0.7", '-c:a', 'aac', '-b:a', '128k', '-shortest']
    else
      command += ['-an']
    end
    command += ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '25', '-pix_fmt', 'yuv420p', '-r', '24', '-threads', '2', '-movflags', '+faststart', '-t', total_duration.to_s, output]
    log, status = Open3.capture2e(*command)
    raise ExportError, "FFmpeg failed: #{log.lines.last(7).join.strip[0, 600]}" unless status.success? && File.file?(output) && File.size(output) > 5000
  end
end
