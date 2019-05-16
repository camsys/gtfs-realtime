require "google/transit/gtfs-realtime.pb"
require "gtfs"
require "active_record"
require "bulk_insert"
require "gtfs/gtfs_gem_patch"

require "gtfs/realtime/model"

require "gtfs/realtime/configuration"

require "gtfs/realtime/partitioned_by_route_id"
require "gtfs/realtime/partitioned_by_weekly_time_field"
require "gtfs/realtime/partitioned_by_configuration"
require "gtfs/realtime/partitioned_by_configuration_and_time"

require "gtfs/realtime/calendar_date"
require "gtfs/realtime/route"
require "gtfs/realtime/service_alert"
require "gtfs/realtime/shape"
require "gtfs/realtime/stop"
require "gtfs/realtime/stop_time"
require "gtfs/realtime/stop_time_update"
require "gtfs/realtime/trip"
require "gtfs/realtime/trip_update"
require "gtfs/realtime/vehicle_position"
require "gtfs/realtime/version"

module GTFS
  class Realtime
    # This is a singleton object, so everything will be on the class level
    class << self

      # save in-memory the last feed processed
      attr_accessor :previous_feeds

      # this method is run to add feeds
      def configure(new_configurations=[])
        run_migrations

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
                service_id: calendar_date.service_id.strip,
                date: Date.strptime(calendar_date.date, "%Y%m%d"),
                exception_type: calendar_date.exception_type
              }
            end
          )

          GTFS::Realtime::Route.delete_all
          GTFS::Realtime::Route.bulk_insert(:id, :short_name, :long_name, :url, values:
            static_data.routes.collect do |route|
              {
                id: route.id.strip,
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
                id: shape.id.strip,
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
                id: stop.id.strip,
                name: stop.name.strip,
                latitude: stop.lat.to_f,
                longitude: stop.lon.to_f
              }
            end
          )

          GTFS::Realtime::StopTime.delete_all
          GTFS::Realtime::StopTime.bulk_insert(values:
            static_data.stop_times.collect do |stop_time|
              {
                stop_id: stop_time.stop_id.strip,
                trip_id: stop_time.trip_id.strip,
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
                id: trip.id.strip,
                headsign: trip.headsign.strip,
                route_id: trip.route_id.strip,
                service_id: trip.service_id.strip,
                shape_id: trip.shape_id.strip,
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
      def refresh_realtime_feed!(config_name)

        start_time = Time.now
        puts "Starting GTFS-RT refresh at #{start_time}."

        # pull trip update, vehicle position, and service alerts entries and header data
        config = GTFS::Realtime::Configuration.find_by(name: config_name)
        feeds = {trip_updates_feed: get_feed(config.trip_updates_feed), vehicle_positions_feed: get_feed(config.vehicle_positions_feed), service_alerts_feed: get_feed(config.service_alerts_feed)}
        trip_updates = feeds[:trip_updates_feed].try(:entity) || []
        trip_updates_header = feeds[:trip_updates_feed].try(:header)
        vehicle_positions = feeds[:vehicle_positions_feed].try(:entity) || []
        vehicle_positions_header = feeds[:vehicle_positions_feed].try(:header)
        service_alerts = feeds[:service_alerts_feed].try(:entity) || []
        service_alerts_header = feeds[:service_alerts_feed].try(:header)


        # (Simple) Logic to pulling feed data:
        #
        # Assuming:
        # Feed A at 12:00
        # Feed B at 12:01
        #
        # When B is pulled, get B - A. Add all rows of B - A as that is all new data
        # With all remaining rows of B (ie. B-(B-A)), iterate through (ordering where relevant) and check for changes.
        # If row of B != row of A, add row of B to database.
        # Else update feed timestamp
        GTFS::Realtime::Model.transaction do

          # get the feed time of the last feed processed
          previous_feed_time = Time.at(@previous_feeds[config.name][:trip_updates_feed].header.timestamp) unless @previous_feeds.nil? || @previous_feeds[config.name][:trip_updates_feed].nil?

          # get the feed time of the feed being processed currently
          current_feed_time = Time.at(trip_updates_header.timestamp) unless trip_updates_header.nil?

          # if no feed has ever been processed, this is the first time its being saved so save all rows
          # if previous feed time is in different DB partition than current feed time, save all rows (a full backup as opposed to jut saving diff)
          if previous_feed_time.nil? || GTFS::Realtime::TripUpdate.partition_normalize_key_value(previous_feed_time) != GTFS::Realtime::TripUpdate.partition_normalize_key_value(current_feed_time)
            GTFS::Realtime::TripUpdate.create_many(
                trip_updates.collect do |trip_update|
                  {
                      configuration_id: config.id,
                      interval_seconds: config.interval_seconds,
                      id: trip_update.id.strip,
                      trip_id: trip_update.trip_update.trip.trip_id.strip,
                      route_id: trip_update.trip_update.trip.route_id.strip,
                      feed_timestamp: current_feed_time
                  }
                end
            )

            GTFS::Realtime::StopTimeUpdate.create_many(
               trip_updates.collect do |trip_update|
                 trip_update.trip_update.stop_time_update.collect do |stop_time_update|
                   {
                       configuration_id: config.id,
                       trip_update_id: trip_update.id.strip,
                       interval_seconds: config.interval_seconds,
                       feed_timestamp: current_feed_time
                   }.merge(get_stop_time_update_hash(stop_time_update))
                 end
               end.flatten
            )

          # ensure you have feed data
          # then confirm the data is new.
          # if the previous_feed_time and current_feed_time are the same we can assume the feed data has not changed and therefore has already been processed
          elsif current_feed_time && previous_feed_time != current_feed_time
            # In a trip update, for a trip_id, the route_id will not change
            # so we only need to look for new trip updates that weren't in the previously processed feed
            # and add them and their corresponding stop updates
            prev_trip_updates = @previous_feeds[config.name][:trip_updates_feed].entity
            new_trip_ids = trip_updates.map{|x| x.trip_update.trip.trip_id.strip} - prev_trip_updates.map{|x| x.trip_update.trip.trip_id.strip}
            new_trip_updates = trip_updates.select{|x| new_trip_ids.include? x.trip_update.trip.trip_id.strip}

            GTFS::Realtime::TripUpdate.create_many(
                new_trip_updates.collect do |trip_update|
                  {
                      configuration_id: config.id,
                      interval_seconds: config.interval_seconds,
                      id: trip_update.id.strip,
                      trip_id: trip_update.trip_update.trip.trip_id.strip,
                      route_id: trip_update.trip_update.trip.route_id.strip,
                      feed_timestamp: current_feed_time
                  }
                end
            )

            # update all unchanged trip updates with a new end feed_timestamp
            trip_updates_update_hash = Hash.new
            (trip_updates - new_trip_updates).each do |trip_update|

              key = {
                  configuration_id: config.id,
                  id: trip_update.id.strip,
                  trip_id: trip_update.trip_update.trip.trip_id.strip,
                  route_id: trip_update.trip_update.trip.route_id.strip,
                  feed_timestamp: previous_feed_time
              }

              value = {feed_timestamp: current_feed_time, :interval_seconds => config.interval_seconds}

              trip_updates_update_hash[key] = value
            end
            GTFS::Realtime::TripUpdate.update_many(trip_updates_update_hash)

            # store all new stop updates in an array to be added at once for performance
            all_new_stop_time_updates = new_trip_updates.collect do |trip_update|
              trip_update.trip_update.stop_time_update.collect do |stop_time_update|
                {
                    configuration_id: config.id,
                    trip_update_id: trip_update.id.strip,
                    interval_seconds: config.interval_seconds,
                    feed_timestamp: current_feed_time
                }.merge(get_stop_time_update_hash(stop_time_update))

              end
            end.flatten

            all_other_stop_time_updates = Hash.new

            # For all other trip updates, check stop updates for changes
            (trip_updates - new_trip_updates).each do |trip_update|

              # get all new stop time updates that weren't in previously processed feed
              # order by departure time
              # convert all stop time updates to hashes for easy comparison
              prev_stop_time_updates = @previous_feeds[config.name][:trip_updates_feed].entity.find{|x| x.trip_update.trip.trip_id.strip == trip_update.id}.trip_update.stop_time_update.sort_by { |x| x.departure&.time || 0 }.map{|x| get_stop_time_update_hash(x)}
              stop_time_updates = trip_update.trip_update.stop_time_update.sort_by { |x| x.departure&.time || 0 }.map{|x| get_stop_time_update_hash(x)}
              new_stop_time_updates = stop_time_updates - prev_stop_time_updates

              all_new_stop_time_updates +=
                  new_stop_time_updates.collect do |stop_time_update|
                    {
                        configuration_id: config.id,
                        trip_update_id: trip_update.id.strip,
                        interval_seconds: config.interval_seconds,
                        feed_timestamp: current_feed_time
                    }.merge(stop_time_update)
                  end

              # for all other stop updates, compare
              updated_stop_time_updates = (stop_time_updates - new_stop_time_updates)
              prev_stop_time_updates_to_check = (prev_stop_time_updates & updated_stop_time_updates)

              updated_stop_time_updates.each_with_index do |stop_time_update, idx|
                # if different add new row
                if stop_time_update != prev_stop_time_updates_to_check[idx]
                  all_new_stop_time_updates += (
                    {
                        configuration_id: config.id,
                        trip_update_id: trip_update.id.strip,
                        interval_seconds: config.interval_seconds,
                        feed_timestamp: current_feed_time
                    }.merge(stop_time_update)

                  )
                else # if not update feed timestamp
                  key = {
                      configuration_id: config.id,
                      trip_update_id: trip_update.id.strip,
                      interval_seconds: config.interval_seconds,
                      feed_timestamp: previous_feed_time
                  }.merge(stop_time_update)

                  value = {interval_seconds: config.interval_seconds, feed_timestamp: current_feed_time}

                  all_other_stop_time_updates[key] = value
                end
              end
            end

            # save stop time updates to database
            GTFS::Realtime::StopTimeUpdate.create_many(all_new_stop_time_updates)
            GTFS::Realtime::StopTimeUpdate.update_many(all_other_stop_time_updates)

          end

          # this data is partitioned but not checked for duplicates currently
          GTFS::Realtime::VehiclePosition.create_many(
            vehicle_positions.collect do |vehicle|
              {
                configuration_id: config.id,
                interval_seconds: config.interval_seconds,
                trip_id: vehicle.vehicle.trip.trip_id.strip,
                stop_id: vehicle.vehicle.stop_id.strip,
                latitude: vehicle.vehicle.position.latitude.to_f,
                longitude: vehicle.vehicle.position.longitude.to_f,
                bearing: vehicle.vehicle.position.bearing.to_f,
                timestamp: Time.at(vehicle.vehicle.timestamp),
                feed_timestamp: Time.at(vehicle_positions_header.timestamp)
              }
            end
          )

          # this data is partitioned but not checked for duplicates currently
          GTFS::Realtime::ServiceAlert.create_many(
            service_alerts.collect do |service_alert|
              {
                configuration_id: config.id,
                interval_seconds: config.interval_seconds,
                stop_id: service_alert.alert.informed_entity.first.stop_id.strip,
                header_text: service_alert.alert.header_text.translation.first.text,
                description_text: service_alert.alert.description_text.translation.first.text,
                start_time: Time.at(service_alert.alert.active_period.first.start),
                end_time: Time.at(service_alert.alert.active_period.first.end),
                feed_timestamp: Time.at(service_alerts_header.timestamp)
              }
            end
          )
        end

        @previous_feeds ||= Hash.new
        @previous_feeds[config.name] = feeds

        puts "Finished GTFS-RT refresh at #{Time.now}. Took #{Time.now - start_time} seconds."
      end

      private

      def get_feed(path)
        return nil if path.nil?

        if File.exists?(path)
          data = File.open(path, 'r'){|f| f.read}
        else
          data = Net::HTTP.get(URI.parse(path))
        end

        Transit_realtime::FeedMessage.decode(data)
      end

      def run_migrations
        ActiveRecord::Migrator.migrate(File.expand_path("../realtime/migrations", __FILE__))
      end

      def get_stop_time_update_hash(stop_time_update)
        {
            stop_id: stop_time_update.stop_id.strip,
            arrival_delay: stop_time_update.arrival&.delay,
            arrival_time: (stop_time_update.arrival&.time&.> 0) ? Time.at(stop_time_update.arrival.time) : nil,
            departure_delay: stop_time_update.departure&.delay,
            departure_time: (stop_time_update.departure&.time&.> 0) ? Time.at(stop_time_update.departure.time) : nil,
        }
      end
    end
  end
end
