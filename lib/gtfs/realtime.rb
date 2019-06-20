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
        ru__migrations

        new_configurations.each do |config|
          GTFS::Realtime::Configuration.create!(config) unless GTFS::Realtime::Configuration.find_by(name: config[:name])
        end
      end

      # this method currently does not work
      def load_static_feed!(force: false)
        return if !force && GTFS::Realtime::Route.count > 0

        static_data = GTFS::Source.build(@configuration.static_feed)
        return unless static_data

        GTFS::Realtime::Model.transaction do
          GTFS::Realtime::CalendarDate.delete_all
          GTFS::Realtime::CalendarDate.bulk_insert(values:
            static_data.calendar_dates.collect do |calendar_date|
              {
                service_id: calendar_date.service_id.to_s.strip,
                date: Date.strptime(calendar_date.date, "%Y%m%d"),
                exception_type: calendar_date.exception_type
              }
            end
          )

          GTFS::Realtime::Route.delete_all
          GTFS::Realtime::Route.bulk_insert(:id, :short_name, :long_name, :url, values:
            static_data.routes.collect do |route|
              {
                id: route.id.to_s.strip,
                short_name: route.short_name,
                long_name: route.long_name,
                url: route.url
              }
            end
          )

          GTFS::Realtime::Shape.delete_all
          GTFS::Realtime::Shape.bulk_insert(:id, :sequence, :latitude, :longitude, values:
            static_data.shapes.collect do |shape|
              {
                id: shape.id.to_s.strip,
                sequence: shape.pt_sequence,
                latitude: shape.pt_lat.to_f,
                longitude: shape.pt_lon.to_f
              }
            end
          )

          GTFS::Realtime::Stop.delete_all
          GTFS::Realtime::Stop.bulk_insert(:id, :name, :latitude, :longitude, values:
            static_data.stops.collect do |stop|
              {
                id: stop.id.to_s.strip,
                name: stop.name.to_s.strip,
                latitude: stop.lat.to_f,
                longitude: stop.lon.to_f
              }
            end
          )

          GTFS::Realtime::StopTime.delete_all
          GTFS::Realtime::StopTime.bulk_insert(values:
            static_data.stop_times.collect do |stop_time|
              {
                stop_id: stop_time.stop_id.to_s.strip,
                trip_id: stop_time.trip_id.to_s.strip,
                arrival_time: stop_time.arrival_time,
                departure_time: stop_time.departure_time,
                stop_sequence: stop_time.stop_sequence.to_i
              }
            end
          )

          GTFS::Realtime::Trip.delete_all
          GTFS::Realtime::Trip.bulk_insert(:id, :headsign, :route_id, :service_id, :shape_id, :direction_id, values:
            static_data.trips.collect do |trip|
              {
                id: trip.id.to_s.strip,
                headsign: trip.headsign.to_s.strip,
                route_id: trip.route_id.to_s.strip,
                service_id: trip.service_id.to_s.strip,
                shape_id: trip.shape_id.to_s.strip,
                direction_id: trip.direction_id
              }
            end
          )
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
