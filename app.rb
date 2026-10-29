require 'sinatra/base'
require 'json'
require_relative 'lib/movie_generator'
require_relative 'lib/export_jobs'

class MovieShowcase < Sinatra::Base
  set :bind, '0.0.0.0'
  set :port, ENV.fetch('PORT', '4567').to_i
  set :server, :puma
  set :public_folder, File.expand_path('public', __dir__)
  set :views, File.expand_path('views', __dir__)
  set :host_authorization, { permitted_hosts: [] }

  before '/api/*' do
    content_type 'application/json', charset: 'utf-8'
    cache_control :no_store
  end

  get '/' do
    erb :index, locals: { initial_seed: MovieGenerator::DEFAULT_SEED, ui_translations: MovieGenerator.ui_translations, regions: MovieGenerator.regions, default_region: MovieGenerator.default_region }
  end

  get '/health' do
    content_type 'text/plain'
    'ok'
  end

  get '/api/config' do
    JSON.generate(regions: MovieGenerator.regions, random_seed: MovieGenerator.random_seed)
  end

  get '/api/media-status' do
    JSON.generate(MovieGenerator.media_status)
  end

  get '/api/movies' do
    generator = MovieGenerator.new(seed: params.fetch('seed', MovieGenerator::DEFAULT_SEED), region: params.fetch('region', MovieGenerator.default_region))
    JSON.generate(generator.movies(page: params.fetch('page', '1'), size: params.fetch('size', '12'), likes: params.fetch('likes', '0.5'), reviews: params.fetch('reviews', '2')))
  end

  get '/api/movie/:index' do
    generator = MovieGenerator.new(seed: params.fetch('seed', MovieGenerator::DEFAULT_SEED), region: params.fetch('region', MovieGenerator.default_region))
    JSON.generate(generator.details(index: params['index'], likes: params.fetch('likes', '0.5'), reviews: params.fetch('reviews', '2')))
  end

  post '/api/exports' do
    content_type 'application/json', charset: 'utf-8'
    payload = JSON.parse(request.body.read(4096))
    id = ExportJobs.create({
      seed: payload.fetch('seed', MovieGenerator::DEFAULT_SEED),
      region: payload.fetch('region', MovieGenerator.default_region),
      page: payload.fetch('page', 1),
      likes: payload.fetch('likes', 0.5),
      reviews: payload.fetch('reviews', 2)
    })
    status 202
    JSON.generate(id: id, state: 'working')
  rescue JSON::ParserError, KeyError
    halt 422, JSON.generate(error: 'Invalid export parameters.')
  rescue MovieGenerator::InvalidParameter, TrailerExporter::ExportError => e
    halt 422, JSON.generate(error: e.message)
  end

  get '/api/exports/:id' do
    job = ExportJobs.get(params['id'])
    halt 404, JSON.generate(error: 'Export not found.') unless job
    JSON.generate(job.slice(:state, :completed, :total, :error))
  end

  get '/api/exports/:id/download' do
    job = ExportJobs.get(params['id'])
    halt 404, 'Export not found.' unless job && job[:state] == 'done' && File.file?(job[:path])
    send_file job[:path], type: 'application/zip', filename: File.basename(job[:path]), disposition: 'attachment'
  end

  error MovieGenerator::InvalidParameter do
    status 422
    JSON.generate(error: env['sinatra.error'].message)
  end

  error StandardError do
    status 500
    JSON.generate(error: 'Internal server error.')
  end
end

MovieShowcase.run! if $PROGRAM_NAME == __FILE__
