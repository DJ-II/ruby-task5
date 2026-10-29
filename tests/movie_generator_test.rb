require 'minitest/autorun'
require_relative '../lib/movie_generator'

class MovieGeneratorTest < Minitest::Test
  def setup
    @generator = MovieGenerator.new(seed: '1234567891234567', region: 'en-US')
  end

  def test_repeatability_across_instances
    one = @generator.details(index: 25, likes: 0.5, reviews: 2.5)
    two = MovieGenerator.new(seed: '1234567891234567', region: 'en-US').details(index: 25, likes: 0.5, reviews: 2.5)
    assert_equal one, two
  end

  def test_likes_do_not_change_any_other_data
    low = @generator.details(index: 12, likes: 0, reviews: 2)
    high = @generator.details(index: 12, likes: 10, reviews: 2)
    assert_equal low.reject { |key, _| key == :likes }, high.reject { |key, _| key == :likes }
    assert_equal 0, low[:likes]
    assert_equal 10, high[:likes]
  end

  def test_reviews_do_not_change_any_other_data
    low = @generator.details(index: 5, likes: 3, reviews: 0)
    high = @generator.details(index: 5, likes: 3, reviews: 8)
    assert_equal low.reject { |key, _| [:review_count, :reviews].include?(key) }, high.reject { |key, _| [:review_count, :reviews].include?(key) }
    assert_equal 8, high[:reviews].length
  end

  def test_fractional_likes
    values = (1..500).map { |index| @generator.movie(index: index, likes: 0.5, reviews: 0)[:likes] }
    assert(values.all? { |count| [0, 1].include?(count) })
    assert_in_delta 250, values.sum, 45
  end

  def test_fractional_reviews
    values = (1..500).map { |index| @generator.movie(index: index, likes: 0, reviews: 3.7)[:review_count] }
    assert(values.all? { |count| [3, 4].include?(count) })
    assert_in_delta 350, values.count(4), 45
  end

  def test_pages_are_contiguous
    first = @generator.movies(page: 1, size: 12, likes: 0, reviews: 0)
    second = @generator.movies(page: 2, size: 12, likes: 0, reviews: 0)
    assert_equal (1..12).to_a, first[:movies].map { |item| item[:index] }
    assert_equal (13..24).to_a, second[:movies].map { |item| item[:index] }
  end

  def test_region_changes_data
    english = @generator.movie(index: 3, likes: 0, reviews: 0)
    polish = MovieGenerator.new(seed: '1234567891234567', region: 'pl-PL').movie(index: 3, likes: 0, reviews: 0)
    refute_equal english[:title], polish[:title]
  end

  def test_many_title_structures
    titles = (1..70).map { |index| @generator.movie(index: index, likes: 0, reviews: 0)[:title] }
    assert_operator titles.uniq.size, :>=, 60
  end

  def test_trailer_contains_realtime_video_scenes
    trailer = @generator.trailer(index: 2)
    assert_equal 3, trailer[:scenes].size
    assert_equal 8.4, trailer[:duration]
    trailer[:scenes].each do |scene|
      assert_match(/\.mp4(?:\?|\z)/, scene[:url])
      assert scene[:clip_id]
      assert scene[:caption]
    end
  end

  def test_seed_changes_results
    one = @generator.movie(index: 1, likes: 3, reviews: 2)
    two = MovieGenerator.new(seed: '1234567891234568', region: 'en-US').movie(index: 1, likes: 3, reviews: 2)
    refute_equal one[:title], two[:title]
  end

  def test_requested_locales_only
    assert_equal %w[en-US pl-PL], MovieGenerator.regions.map { |region| region[:code] }.sort
  end

  def test_polish_titles_and_labels
    polish = MovieGenerator.new(seed: '1234567891234567', region: 'pl-PL')
    movies = polish.movies(page: 1, size: 20, likes: 0.5, reviews: 2)
    genres = MovieGenerator::REGIONS.fetch('pl-PL').fetch('genres')
    assert_equal 20, movies[:movies].length
    assert movies[:movies].all? { |movie| genres.include?(movie[:genre]) }
    assert movies[:movies].all? { |movie| !movie[:title].empty? && !movie[:title].include?('{') }
    assert movies[:movies].all? { |movie| movie[:actors].length.between?(2, 4) }
  end

  def test_polish_reviews_and_trailer_captions
    polish = MovieGenerator.new(seed: '1234567891234567', region: 'pl-PL')
    details = polish.details(index: 9, likes: 2, reviews: 5)
    assert_equal 5, details[:reviews].length
    assert details[:reviews].all? { |review| MovieGenerator::REGIONS.fetch('pl-PL').fetch('reviews').include?(review[:text]) }
    captions = MovieGenerator::REGIONS.fetch('pl-PL').fetch('mood_trailer_cards').fetch(details[:mood])
    assert_includes captions, details[:trailer][:scenes].first[:caption]
    assert_equal "W ROLI GŁÓWNEJ: #{details[:actors].first}", details[:trailer][:scenes][1][:caption]
    assert_equal details[:title], details[:trailer][:scenes].last[:caption]
  end

  def test_polish_reproducibility_and_independence
    first = MovieGenerator.new(seed: '1234567891234567', region: 'pl-PL').details(index: 42, likes: 0, reviews: 1)
    second = MovieGenerator.new(seed: '1234567891234567', region: 'pl-PL').details(index: 42, likes: 5, reviews: 1)
    assert_equal first.reject { |key, _| key == :likes }, second.reject { |key, _| key == :likes }
    assert_equal first, MovieGenerator.new(seed: '1234567891234567', region: 'pl-PL').details(index: 42, likes: 0, reviews: 1)
  end

  def test_polish_title_pattern_placeholders
    title_data = MovieGenerator::REGIONS.fetch('pl-PL').fetch('locale_title')
    placeholders = title_data.fetch('patterns').flat_map { |pattern| pattern.scan(/\{(\w+)\}/).flatten }.uniq
    assert_equal [], placeholders.reject { |key| key == 'year' || title_data.key?(key) }
  end

  def test_user_interface_locales_have_matching_keys
    translations = MovieGenerator.ui_translations
    assert_equal %w[en-US pl-PL], translations.keys.sort
    assert_equal translations.fetch('en-US').keys.sort, translations.fetch('pl-PL').keys.sort
  end

  def test_invalid_params
    assert_raises(MovieGenerator::InvalidParameter) { MovieGenerator.new(seed: 'x', region: 'en-US') }
    assert_raises(MovieGenerator::InvalidParameter) { MovieGenerator.new(seed: '15', region: 'de-DE') }
    assert_raises(MovieGenerator::InvalidParameter) { @generator.movies(page: 1, size: 12, likes: 11, reviews: 0) }
  end
end

class MovieGeneratorExtendedTest < Minitest::Test
  def setup
    @generator = MovieGenerator.new(seed: '1234567891234567', region: MovieGenerator.default_region)
  end

  def test_region_metadata_is_read_from_external_config
    MovieGenerator.regions.each do |region|
      assert_equal MovieGenerator::REGIONS.fetch(region[:code]).fetch('label'), region[:label]
      assert_equal MovieGenerator::REGIONS.fetch(region[:code]).fetch('html_lang'), region[:html_lang]
    end
  end

  def test_reviews_extend_without_modifying_old_entries
    one = @generator.details(index: 19, likes: 3, reviews: 2)
    many = @generator.details(index: 19, likes: 3, reviews: 8)
    assert_equal one[:reviews], many[:reviews].first(2)
    assert_equal one[:trailer], many[:trailer]
  end

  def test_trailer_uses_distinct_sources
    (1..50).each do |index|
      trailer = @generator.trailer(index: index)
      sources = trailer[:scenes].map do |scene|
        clip = MovieGenerator::CLIPS.find { |item| item.fetch('id') == scene[:clip_id] }
        clip.fetch('source_id', clip.fetch('id'))
      end
      assert_equal sources.uniq, sources
    end
  end

  def test_media_status_counts_available_local_videos
    status = MovieGenerator.media_status
    assert_equal MovieGenerator::CLIPS.length, status.fetch(:total)
    assert_operator status.fetch(:local), :>=, 0
  end

  def test_floating_point_counts_are_within_bounds
    [0, 0.5, 3.7, 5, 10].each do |average|
      values = (1..40).map { |i| @generator.movie(index: i, likes: average, reviews: average) }
      assert values.all? { |v| [average.floor, average.ceil].include?(v[:likes]) }
      assert values.all? { |v| [average.floor, average.ceil].include?(v[:review_count]) }
    end
  end
end

class MovieGeneratorMusicTest < Minitest::Test
  def setup
    @generator = MovieGenerator.new(seed: '1234567891234567', region: 'en-US')
  end

  def test_soundtracks_exist_for_each_mood
    %w[action city mystery nature people].each do |mood|
      paths = MovieGenerator::AUDIO_LIBRARY.fetch(mood)
      assert_operator paths.size, :>=, 12
      paths.each do |url|
        assert File.file?(File.join(MovieGenerator::ROOT, 'public', url.delete_prefix('/')))
      end
    end
  end

  def test_soundtrack_is_deterministic
    first = @generator.trailer(index: 112)
    second = MovieGenerator.new(seed: '1234567891234567', region: 'en-US').trailer(index: 112)
    assert_equal first.fetch(:audio_url), second.fetch(:audio_url)
  end

  def test_soundtrack_matches_mood
    (1..50).each do |index|
      trailer = @generator.trailer(index: index)
      assert_match(%r{\A/audio/#{trailer.fetch(:mood)}-\d+\.mp3\z}, trailer.fetch(:audio_url))
    end
  end

  def test_multiple_soundtracks_are_selected
    sampled = (1..100).map { |index| @generator.trailer(index: index).fetch(:audio_url) }
    assert_operator sampled.uniq.size, :>=, 20
  end
end
