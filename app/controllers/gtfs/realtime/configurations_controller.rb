require_dependency "gtfs/realtime/application_controller"

module GTFS
  class Realtime
    class ConfigurationsController < ApplicationController
      layout "api"

      before_action :get_configuration, except: [:index]

      def index

      end

      def show
        if params[:timestamp].blank?
          timestamp = GTFS::Realtime::TripUpdate.from_partition(@config.id).maximum(:feed_timestamp)
        else
          timestamp = Time.at(params[:timestamp].to_i)
        end


        @trip_updates = GTFS::Realtime::TripUpdate.from_partition(@config.id, timestamp.at_beginning_of_week).where("(feed_timestamp - (interval_seconds * interval '1 second')) <= ? AND ? <= feed_timestamp", timestamp, timestamp)
        @stop_time_updates = GTFS::Realtime::StopTimeUpdate.from_partition(@config.id, timestamp.at_beginning_of_week).where("(feed_timestamp - (interval_seconds * interval '1 second')) <= ? AND ? <= feed_timestamp", timestamp, timestamp)
        @vehicle_positions = GTFS::Realtime::VehiclePosition.from_partition(@config.id, timestamp.at_beginning_of_week).where("(feed_timestamp - (interval_seconds * interval '1 second')) <= ? AND ? <= feed_timestamp", timestamp, timestamp)
        @service_alerts = GTFS::Realtime::ServiceAlert.from_partition(@config.id, timestamp.at_beginning_of_week).where("(feed_timestamp - (interval_seconds * interval '1 second')) <= ? AND ? <= feed_timestamp", timestamp, timestamp)


        entities = @trip_updates.collect do |trip_update_row|

          trip = Transit_realtime::TripDescriptor.new(trip_id: trip_update_row.trip_id)
          stop_time_updates = @stop_time_updates.where(trip_update_id: trip_update_row.id).collect do |stop_time_update|
            arrival = Transit_realtime::TripUpdate::StopTimeEvent.new(time: stop_time_update.arrival_time.to_i)
            arrival.delay = stop_time_update.arrival_delay unless stop_time_update.arrival_delay.blank?
            departure = Transit_realtime::TripUpdate::StopTimeEvent.new(time: stop_time_update.departure_time.to_i)
            departure.delay = stop_time_update.departure_delay unless stop_time_update.departure_delay.blank?

            Transit_realtime::TripUpdate::StopTimeUpdate.new(
                stop_id: stop_time_update.stop_id,
                arrival: arrival,
                departure: departure,
            )
          end
          trip_update = Transit_realtime::TripUpdate.new(trip: trip, stop_time_update: stop_time_updates)
          Transit_realtime::FeedEntity.new(id: trip_update_row.id, trip_update: trip_update)
        end

        @vehicle_positions.each do |vehicle_position_row|
          trip = Transit_realtime::TripDescriptor.new(trip_id: vehicle_position_row.trip_id)

          vehicle_position = Transit_realtime::VehiclePosition.new(trip: trip, stop_id: vehicle_position_row.stop_id, timestamp: vehicle_position_row.timestamp)
          vehicle_position.position = Transit_realtime::Position.new(latitude: vehicle_position_row.latitude, longitude: vehicle_position_row.longitude, bearing: vehicle_position_row.bearing) unless vehicle_position_row.latitude.blank? && vehicle_position_row.longitude.blank? && vehicle_position_row.bearing.blank?

          entity_idx = entities.index{|x| x.id == vehicle_position_row.id}
          if entity_idx.nil?
            entities << Transit_realtime::FeedEntity.new(id: vehicle_position_row.id, vehicle: vehicle_position)
          else
            entities[entity_idx].vehicle = vehicle_position
          end

        end

        @service_alerts.each do |alert_row|
          informed_entity = Transit_realtime::EntitySelector.new(stop_id: alert_row.stop_id)
          header_text = Transit_realtime::TranslatedString.new(translation: [Transit_realtime::TranslatedString::Translation.new(text: alert_row.header_text)])
          description_text = Transit_realtime::TranslatedString.new(translation: [Transit_realtime::TranslatedString::Translation.new(text: alert_row.description_text)])
          active_period = Transit_realtime::TimeRange.new(start: alert_row.start_time, end: alert_row. end_time)

          alert = Transit_realtime::Alert.new(active_period: [active_period], informed_entity: [informed_entity], header_text: header_text, description_text: description_text)

          entity_idx = entities.index{|x| x.id == alert_row.id}
          if entity_idx.nil?
            entities << Transit_realtime::FeedEntity.new(id: alert_row.id, alert: alert)
          else
            entities[entity_idx].alert = alert
          end

        end

        feed_header = Transit_realtime::FeedHeader.new(timestamp: timestamp.to_i, gtfs_realtime_version: '1.0') # assume gtfs realtime version
        feed_message = Transit_realtime::FeedMessage.new(header: feed_header, entity: entities)

        respond_to do |format|
          format.html {

            feed_file = Tempfile.new "tripUpdates", "#{Rails.root}/tmp", encoding: 'ascii-8bit'
            ObjectSpace.undefine_finalizer(feed_file)
            begin
              feed_file << feed_message.encode
            rescue => ex
              Rails.logger.warn ex
            ensure
              feed_file.close
            end

            send_file feed_file.path
          }
          format.json { render json: feed_message }
        end
      end

      private

      def get_configuration
        @config = GTFS::Realtime::Configuration.find_by(id: params[:id])
      end
    end
  end
end

