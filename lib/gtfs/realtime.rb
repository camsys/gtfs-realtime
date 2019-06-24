require "gtfs"
require "active_record"
require "bulk_insert"
require "partitioned"
require "gtfs/gtfs_gem_patch"
require 'gtfs/realtime/engine'

require "gtfs/realtime/version"

module GTFS
  class Realtime
    # This is a singleton object, so everything will be on the class level
    class << self

      attr_accessor :test

      # this method is run to add feeds
      def configure(new_configurations=[])
        run__migrations

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

        start_time = Time.now
        puts "Starting GTFS-RT refresh for #{config.name} at #{start_time}."

        if config.handler.present?
          klass = config.handler.constantize
          transit_realtime_file = klass::TRANSIT_REALTIME_FILE
        else
          klass = GTFS::Realtime::RealtimeFeedHandler
          transit_realtime_file = 'gtfs-realtime-new.pb.rb'
        end

        if reload_transit_realtime
          Object.send(:remove_const, :TransitRealtime) if Object.constants.include? :TransitRealtime
          load transit_realtime_file
        else
          require transit_realtime_file
        end

        handler = klass.new(gtfs_realtime_configuration: config) # TODO figure out previous feeds
        GTFS::Realtime::Model.transaction do
          handler.process
        end # end of ActiveRecord transaction

        puts "Finished GTFS-RT refresh for #{config.name} at #{Time.now}. Took #{Time.now - start_time} seconds."
      end

      private

      def run_migrations
        ActiveRecord::Migrator.migrate(File.expand_path("../realtime/migrations", __FILE__))
      end
    end
  end
end
