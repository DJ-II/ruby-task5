require 'json'
require 'digest'
require 'securerandom'
require 'thread'
require 'faker'

class MovieGenerator
  class InvalidParameter < StandardError; end

  MAX_SEED = (2**64) - 1
  DEFAULT_SEED = '7812394521098139'
  ROOT = File.expand_path('..', __dir__)
  REGIONS = Dir[File.join(ROOT, 'config/regions/*.json')].to_h do |file|
    data = JSON.parse(File.read(file, encoding: 'UTF-8'))
    [data.fetch('code'), data.freeze]
  end.freeze
  UI_TRANSLATIONS = Dir[File.join(ROOT, 'config/ui/*.json')].to_h do |file|
    [File.basename(file, '.json'), JSON.parse(File.read(file, encoding: 'UTF-8'))]
  end.freeze
  MEDIA = JSON.parse(File.read(File.join(ROOT, 'config/media.json'), encoding: 'UTF-8')).freeze
  LOCAL_MANIFEST = File.join(ROOT, 'config/videos.local.json')
  VIDEO_MANIFEST = File.file?(LOCAL_MANIFEST) && JSON.parse(File.read(LOCAL_MANIFEST, encoding: 'UTF-8')).any? ? LOCAL_MANIFEST : File.join(ROOT, 'config/videos.json')
  CLIPS = JSON.parse(File.read(VIDEO_MANIFEST, encoding: 'UTF-8')).freeze
  FAKER_MUTEX = Mutex.new
  AUDIO_LIBRARY = Dir[File.join(ROOT, 'public/audio/*.mp3')].sort.group_by { |path| File.basename(path).split('-').first }.transform_values { |paths| paths.map { |path| "/audio/#{File.basename(path)}" }.freeze }.freeze

  def self.random_seed
    SecureRandom.random_number(MAX_SEED + 1).to_s
  end

  def self.validate_seed(value)
    string = value.to_s
    raise InvalidParameter, 'Seed must be an unsigned 64-bit integer.' unless string.match?(/\A\d{1,20}\z/) && string.to_i <= MAX_SEED
    string.to_i.to_s
  end

  def self.validate_region(value)
    raise InvalidParameter, 'Unsupported language or region.' unless REGIONS.key?(value)
    value
  end

  def self.validate_average(value)
    numeric = Float(value)
    raise InvalidParameter, 'Likes and reviews must be between 0 and 10.' unless numeric.finite? && numeric.between?(0.0, 10.0)
    numeric
  rescue ArgumentError, TypeError
    raise InvalidParameter, 'Likes and reviews must be numbers between 0 and 10.'
  end

  def self.validate_positive(value, name)
    string = value.to_s
    raise InvalidParameter, "Invalid #{name}." unless string.match?(/\A[1-9]\d*\z/)
    string.to_i
  end

  def initialize(seed:, region:)
    @seed = self.class.validate_seed(seed)
    @region = self.class.validate_region(region)
    @data = REGIONS.fetch(@region)
  end

  def self.regions
    REGIONS.values.sort_by { |r| [r['default'] ? 0 : 1, r.fetch('code')] }.map do |r|
      { code: r.fetch('code'), label: r.fetch('label'), html_lang: r.fetch('html_lang') }
    end
  end

  def self.default_region
    regions.first.fetch(:code)
  end

  def self.media_status
    { total: CLIPS.size, local: CLIPS.count { |clip| File.file?(File.join(ROOT, 'public/clips', "#{clip.fetch('id')}.mp4")) }, manifest: File.basename(VIDEO_MANIFEST) }
  end

  def self.ui_translations
    UI_TRANSLATIONS
  end

  def movies(page:, size:, likes:, reviews:)
    page = self.class.validate_positive(page, 'page')
    size = self.class.validate_positive(size, 'page size')
    raise InvalidParameter, 'Page size must be 1–24.' if size > 24
    likes = self.class.validate_average(likes)
    reviews = self.class.validate_average(reviews)
    first = (page - 1) * size + 1
    {
      seed: @seed,
      region: @region,
      page: page,
      page_size: size,
      movies: Array.new(size) { |n| movie(index: first + n, likes: likes, reviews: reviews) }
    }
  end

  def movie(index:, likes:, reviews:)
    index = self.class.validate_positive(index, 'movie index')
    likes = self.class.validate_average(likes)
    reviews = self.class.validate_average(reviews)
    core(index).merge(
      likes: count_for(index, 'likes', likes),
      review_count: count_for(index, 'reviews', reviews)
    )
  end

  def details(index:, likes:, reviews:)
    base = movie(index: index, likes: likes, reviews: reviews)
    count = base.fetch(:review_count)
    texts = @data.fetch('reviews')
    review_items = Array.new(count) do |n|
      rng = rng_for(index, "review-#{n}")
      {
        author: faker_name(index, "review-author-#{n}"),
        rating: rng.rand(2..5),
        text: texts.fetch(rng.rand(texts.size))
      }
    end
    base.merge(reviews: review_items, trailer: trailer(index: index), seasons: series_seasons(index, base))
  end

  def series_seasons(index, base)
    return [] unless base.fetch(:format) == 'series'
    count = base.fetch(:season_count)
    Array.new(count) do |season_index|
      number = season_index + 1
      episodes_count = rng_for(index, "season-count-#{number}").rand(4..9)
      {
        number: number,
        year: base.fetch(:year) + season_index,
        episodes: Array.new(episodes_count) do |episode_index|
          episode = episode_index + 1
          { number: episode, title: title_for(index, base.fetch(:mood), domain: "episode-#{number}-#{episode}"), duration_minutes: rng_for(index, "episode-duration-#{number}-#{episode}").rand(28..62) }
        end
      }
    end
  end

  def trailer(index:)
    index = self.class.validate_positive(index, 'movie index')
    base = core(index)
    rng = rng_for(index, 'trailer')
    mood = base.fetch(:mood)
    pool = CLIPS.group_by { |clip| clip.fetch('source_id', clip.fetch('id')) }.values.map { |variants| variants.sample(random: rng) }
    relevant = pool.select { |clip| clip.fetch('mood') == mood }
    remaining = pool.reject { |clip| clip.fetch('mood') == mood }
    clips = relevant.sample([3, relevant.size].min, random: rng)
    clips += remaining.sample(3 - clips.length, random: rng)
    clips += (CLIPS - clips).sample(3 - clips.length, random: rng) if clips.length < 3
    clips.shuffle!(random: rng)
    captions = @data.fetch('mood_trailer_cards').fetch(mood)
    scenes = clips.each_with_index.map do |clip, n|
      local = File.join(ROOT, 'public/clips', "#{clip.fetch('id')}.mp4")
      poster_local = File.join(ROOT, 'public/clips', "#{clip.fetch('id')}.jpg")
      {
        clip_id: clip.fetch('id'),
        url: File.file?(local) ? "/clips/#{clip.fetch('id')}.mp4" : clip.fetch('url'),
        poster: File.file?(poster_local) ? "/clips/#{clip.fetch('id')}.jpg" : clip.fetch('poster'),
        caption: n == 2 ? base.fetch(:title) : (n == 1 ? @data.fetch('trailer_cast_card').gsub('{actor}', base.fetch(:actors).first) : captions.fetch(rng.rand(captions.size))),
        start: n * 2.8,
        duration: 2.8,
        speed: [0.85, 0.95, 1.0, 1.1, 1.2].sample(random: rng),
        zoom: rng.rand(102..118) / 100.0,
        shift: rng.rand(-6..6),
        hue: rng.rand(-8..8),
        transition: %w[fade wipe flash].sample(random: rng),
        caption_style: %w[center cinematic bottom].sample(random: rng)
      }
    end
    tracks = AUDIO_LIBRARY.fetch(mood, [])
    audio_url = tracks.empty? ? nil : tracks.fetch(rng_for(index, 'music').rand(tracks.length))
    { title: base.fetch(:title), tagline: base.fetch(:tagline), mood: mood, audio_url: audio_url, duration: 8.4, scenes: scenes }
  end

  private

  def seed_for(index, domain)
    Digest::SHA256.hexdigest([@seed, @region, index, domain].join(':'))[0, 16].to_i(16)
  end

  def rng_for(index, domain)
    Random.new(seed_for(index, domain))
  end

  def faker_name(index, domain)
    FAKER_MUTEX.synchronize do
      Faker::Config.locale = @data.fetch('faker_locale')
      Faker::Config.random = Random.new(seed_for(index, domain))
      Faker::Name.name
    end
  end

  def count_for(index, domain, average)
    whole = average.floor
    whole + (rng_for(index, domain).rand < average - whole ? 1 : 0)
  end

  def title_for(index, mood, domain: 'title')
    rng = rng_for(index, domain)
    data = @data.fetch('locale_title')
    mood_terms = @data.fetch('mood_terms').fetch(mood, {})
    pattern = data.fetch('patterns').sample(random: rng)
    substitutions = data.reject { |key, _| key == 'patterns' }.transform_values do |terms|
      terms.sample(random: rng)
    end
    mood_terms.each { |key, terms| substitutions[key] = terms.sample(random: rng) }
    substitutions['year'] = (rng.rand(1945..2035)).to_s
    pattern.gsub(/\{(\w+)\}/) { substitutions.fetch(Regexp.last_match(1)) }
  end

  def core(index)
    rng = rng_for(index, 'identity')
    genre_id = rng.rand(@data.fetch('genres').size)
    mood = @data.fetch('genre_moods').fetch(genre_id)
    clip = CLIPS.select { |c| c.fetch('mood') == mood }.sample(random: rng) || CLIPS.sample(random: rng)
    actors = Array.new(2 + rng.rand(3)) { |n| faker_name(index, "actor-#{n}") }
    poster_local = File.join(ROOT, 'public/clips', "#{clip.fetch('id')}.jpg")
    format = rng_for(index, 'format').rand(5).zero? ? 'series' : 'movie'
    season_count = format == 'series' ? rng_for(index, 'season-count').rand(1..5) : nil
    {
      index: index,
      format: format,
      season_count: season_count,
      title: title_for(index, mood),
      actors: actors,
      year: rng.rand(1980..2026),
      genre: @data.fetch('genres').fetch(genre_id),
      mood: mood,
      tagline: @data.fetch('taglines').sample(random: rng),
      poster: File.file?(poster_local) ? "/clips/#{clip.fetch('id')}.jpg" : clip.fetch('poster'),
      accent: MEDIA.fetch('palettes').sample(random: rng),
      duration_minutes: rng.rand(81..175)
    }
  end
end
