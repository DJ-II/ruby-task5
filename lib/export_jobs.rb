require 'securerandom'
require 'thread'
require 'fileutils'
require_relative 'trailer_exporter'

class ExportJobs
  @mutex = Mutex.new
  @jobs = {}

  class << self
    def create(params)
      exporter = TrailerExporter.new(**params)
      exporter.validate!
      @mutex.synchronize do
        cleanup_old
        raise TrailerExporter::ExportError, 'Another export is running. Try again when it finishes.' if @jobs.values.any? { |job| job[:state] == 'working' }
        id = SecureRandom.hex(16)
        @jobs[id] = { id: id, state: 'working', completed: 0, total: 10, created_at: Time.now, path: nil, directory: nil, error: nil }
        Thread.new do
          begin
            path, directory = exporter.perform do |completed, total|
              @mutex.synchronize { @jobs[id].merge!(completed: completed, total: total) }
            end
            @mutex.synchronize { @jobs[id].merge!(state: 'done', path: path, directory: directory) }
          rescue StandardError => e
            warn "Export job #{id}: #{e.class}: #{e.message}"
            @mutex.synchronize { @jobs[id].merge!(state: 'error', error: e.message) }
          end
        end
        id
      end
    end

    def get(id)
      @mutex.synchronize do
        cleanup_old
        @jobs[id]&.dup
      end
    end

    private

    def cleanup_old
      @jobs.delete_if do |_id, job|
        expired = job[:state] != 'working' && (Time.now - job[:created_at]) > 1800
        FileUtils.remove_entry(job[:directory]) if expired && job[:directory] && Dir.exist?(job[:directory])
        expired
      end
    end
  end
end
