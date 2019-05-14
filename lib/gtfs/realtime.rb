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

      def configure(new_configurations=[])
        run_migrations

        new_configurations.each do |config|
          GTFS::Realtime::Configuration.create!(config) unless GTFS::Realtime::Configuration.find_by(name: config[:name])
        end
      end

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

        # create partition tables for TripUpdate which is partitioned by Route
        GTFS::Realtime::TripUpdate.create_new_partition_tables(GTFS::Realtime::Route.distinct.map(&:id).map(&:downcase))
      end

      def refresh_realtime_feed!(config_name)

        start_time = Time.now
        puts "Starting GTFS-RT refresh at #{start_time}."

        config = GTFS::Realtime::Configuration.find_by(name: config_name)
        feeds = {trip_updates_feed: get_feed(config.trip_updates_feed), vehicle_positions_feed: get_feed(config.vehicle_positions_feed), service_alerts_feed: get_feed(config.service_alerts_feed)}
        trip_updates = feeds[:trip_updates_feed].try(:entity) || []
        trip_updates_header = feeds[:trip_updates_feed].try(:header)
        vehicle_positions = feeds[:vehicle_positions_feed].try(:entity) || []
        vehicle_positions_header = feeds[:vehicle_positions_feed].try(:header)
        service_alerts = feeds[:service_alerts_feed].try(:entity) || []
        service_alerts_header = feeds[:service_alerts_feed].try(:header)



        # assumption:
        # Feed A at 12:00
        # Feed B at 12:01
        #
        # pseudo when B is pulled:
        # order A & B trip_updates by trip_id
        # add in all rows for B.trip_updates.trip_id - A.trip_updates.trip_id
        # for all rows in B not added in:
        #                                 order A & B stop time updates by arrival_time
        # add in all rows B.stop_time_updates - A.stop_time_updates
        # for all rows in B not added in:
        #                                 compare corresponding A row & B


        GTFS::Realtime::Model.transaction do

          previous_feed_time = GTFS::Realtime::TripUpdate.order(feed_timestamp: :desc).first.feed_timestamp
          current_feed_time = Time.at(trip_updates_header.timestamp)

          if  previous_feed_time != current_feed_time

            prev_trip_updates = GTFS::Realtime::TripUpdate.from_partition(config.id, current_feed_time.at_beginning_of_week).where(feed_timestamp: previous_feed_time)

            new_trip_updates = trip_updates.select{|t| !(prev_trip_updates.pluck(:trip_id).include? t.trip_update.trip.trip_id.strip)}
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

            all_new_stop_time_updates = new_trip_updates.collect do |trip_update|
               trip_update.trip_update.stop_time_update.collect do |stop_time_update|
                 {
                     configuration_id: config.id,
                     interval_seconds: config.interval_seconds,
                     trip_update_id: trip_update.id.strip,
                     stop_id: stop_time_update.stop_id.strip,
                     arrival_delay: stop_time_update.arrival&.delay,
                     arrival_time: (stop_time_update.arrival&.time&.> 0) ? Time.at(stop_time_update.arrival.time) : nil,
                     departure_delay: stop_time_update.departure&.delay,
                     departure_time: (stop_time_update.departure&.time&.> 0) ? Time.at(stop_time_update.departure.time) : nil,
                     feed_timestamp: current_feed_time
                 }
               end
            end.flatten

            (trip_updates - new_trip_updates).each do |trip_update|

              prev_stop_time_updates = GTFS::Realtime::StopTimeUpdate.from_partition(config.id, current_feed_time.at_beginning_of_week).where(feed_timestamp: previous_feed_time, trip_update_id: trip_update.id)

              stop_time_updates = trip_update.trip_update.stop_time_update.sort { |x,y| ((x.arrival&.time&.> 0) && (y.arrival&.time&.> 0)) ? (x.arrival.time <=> y.arrival.time) : (x ? -1 : 1) }

              new_stop_time_updates = stop_time_updates.select{|t| !(prev_stop_time_updates.pluck(:arrival_time).include? ((t.arrival&.time&.> 0) ? Time.at(t.arrival.time) : nil))}

              all_new_stop_time_updates +=
                  new_stop_time_updates.collect do |stop_time_update|
                    {
                        configuration_id: config.id,
                        interval_seconds: config.interval_seconds,
                        trip_update_id: trip_update.id.strip,
                        stop_id: stop_time_update.stop_id.strip,
                        arrival_delay: stop_time_update.arrival&.delay,
                        arrival_time: (stop_time_update.arrival&.time&.> 0) ? Time.at(stop_time_update.arrival.time) : nil,
                        departure_delay: stop_time_update.departure&.delay,
                        departure_time: (stop_time_update.departure&.time&.> 0) ? Time.at(stop_time_update.departure.time) : nil,
                        feed_timestamp: current_feed_time
                    }
                  end

              updated_stop_time_updates = (stop_time_updates - new_stop_time_updates)
              prev_stop_time_updates_to_check = prev_stop_time_updates.where('stop_id IN (?)', updated_stop_time_updates.collect{|s| s.stop_id.strip}).order(:arrival_time)

              all_new_stop_time_updates += updated_stop_time_updates.each_with_index.select{ |update, idx| ((update.arrival&.time&.> 0) ? Time.at(update.arrival.time) : nil) != prev_stop_time_updates_to_check[idx].arrival_time}.collect do |stop_time_update|
                stop_time_update = stop_time_update[0]
                {
                    configuration_id: config.id,
                    interval_seconds: config.interval_seconds,
                    trip_update_id: trip_update.id.strip,
                    stop_id: stop_time_update.stop_id.strip,
                    arrival_delay: stop_time_update.arrival&.delay,
                    arrival_time: (stop_time_update.arrival&.time&.> 0) ? Time.at(stop_time_update.arrival.time) : nil,
                    departure_delay: stop_time_update.departure&.delay,
                    departure_time: (stop_time_update.departure&.time&.> 0) ? Time.at(stop_time_update.departure.time) : nil,
                    feed_timestamp: current_feed_time
                }
              end
            end

            GTFS::Realtime::StopTimeUpdate.create_many(all_new_stop_time_updates)

          end

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
                feed_timestamp: current_feed_time
              }
            end
          )

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
                feed_timestamp: current_feed_time
              }
            end
          )
        end

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
    end
  end
end
