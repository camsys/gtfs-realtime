require "gtfs"
require "active_record"
require "bulk_insert"
require "partitioned"
require "gtfs/gtfs_gem_patch"

require 'carrierwave'
require 'fog'

require 'chronic'

require 'gtfs/realtime/engine'

require "gtfs/realtime/version"

module GTFS
  class Realtime
    # This is a singleton object, so everything will be on the class level
    class << self

      attr_accessor :test

      # this method is run to add feeds
      def configure(new_configurations=[])
        run_migrations

        new_configurations.each do |config|
          GTFS::Realtime::Configuration.create!(config) unless GTFS::Realtime::Configuration.find_by(name: config[:name])
        end
      end

      #
      # This method queries the feed URL to get the latest GTFS-RT data and saves it to the database
      # It can be run manually or on a schedule
      #
      # @param [String] config_name name of feed saved in the configuration
      #
      def refresh_realtime_feed!(config, reload_transit_realtime=true)

        metric_service = PutMetricDataService.new
        start_time = Time.now

        Rails.logger.info "Starting GTFS-RT refresh for #{config.name} at #{start_time}."
        Crono.logger.info "Starting GTFS-RT refresh for #{config.name} at #{start_time} in Crono." if Crono.logger

        if config.handler.present?
          klass = config.handler.constantize
        else
          klass = GTFS::Realtime::RealtimeFeedHandler
        end

        handler = klass.new(gtfs_realtime_configuration: config)
        GTFS::Realtime::Model.transaction do
          begin
            handler.process
            metric_service.put_metric("#{config.name}:HealthyCount", 'Count',1)
          rescue
            metric_service.put_metric("#{config.name}:ErrorCount", 'Count', 1)
          end
        end # end of ActiveRecord transaction

        metric_service.put_metric("#{config.name}:Runtime", 'Seconds',Time.now - start_time)
        Rails.logger.info "Finished GTFS-RT refresh for #{config.name} at #{Time.now}. Started #{start_time} and took #{Time.now - start_time} seconds in Crono."
        Crono.logger.info "Finished GTFS-RT refresh for #{config.name} at #{Time.now}. Started #{start_time} and took #{Time.now - start_time} seconds in Crono." if Crono.logger

      end

      private

      def run_migrations
        ActiveRecord::Migrator.migrate(File.expand_path("../realtime/migrations", __FILE__))
      end
    end
  end
end
