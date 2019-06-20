module GTFS
  class Realtime
    class RealtimeFeedHandler

      attr_accessor :gtfs_realtime_configuration
      attr_accessor :previous_feeds

      def initialize(gtfs_realtime_configuration: GTFS::Realtime::Configuration.new, previous_feeds: {trip_updates_feed: nil, vehicle_positions_feed: nil, service_alerts_feed: nil})
        self.gtfs_realtime_configuration = gtfs_realtime_configuration
        self.previous_feeds = previous_feeds
      end

      def pre_process(model_name, previous_feed_time, current_feed_time)
        puts previous_feed_time
        puts current_feed_time
        # check if need to create new partition
        if current_feed_time.try(:at_beginning_of_week) != previous_feed_time.try(:at_beginning_of_week)
          klass = "GTFS::Realtime::#{model_name}".constantize
          klass.create_new_partition_tables([[@gtfs_realtime_configuration.id, current_feed_time.at_beginning_of_week]]) unless klass.partition_tables.include? "p#{gtfs_realtime_configuration.id}_#{current_feed_time.at_beginning_of_week.strftime('%Y%m%d')}"

          if model_name == 'TripUpdate'
            GTFS::Realtime::StopTimeUpdate.create_new_partition_tables([[@gtfs_realtime_configuration.id, current_feed_time.at_beginning_of_week]]) unless GTFS::Realtime::StopTimeUpdate.partition_tables.include? "p#{@gtfs_realtime_configuration.id}_#{current_feed_time.at_beginning_of_week.strftime('%Y%m%d')}"
          end
        end
      end

      def post_process(model_name,feed)
        @previous_feeds["#{model_name.tableize}_feed".to_sym] = feed
      end

      def process
        process_trip_updates
        process_vehicle_positions
        process_service_alerts
      end


      def process_trip_updates

        feed = get_feed(@gtfs_realtime_configuration.trip_updates_feed)
        trip_updates = (feed.try(:entity) || []).select{|x| x.trip_update.present?}
        trip_updates_header = feed.try(:header)

        # get the feed time of the last feed processed
        previous_feed_time = Time.at(@previous_feeds[:trip_updates_feed].header.timestamp) unless @previous_feeds[:trip_updates_feed].nil?

        # get the feed time of the feed being processed currently
        current_feed_time = Time.at(trip_updates_header.timestamp) unless trip_updates_header.nil?
        current_feed_time_without_timezone = Time.zone.at(current_feed_time.to_i) # used as string in query


        pre_process('TripUpdate', previous_feed_time, current_feed_time)

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

        # if no feed has ever been processed, this is the first time its being saved so save all rows
        # if previous feed time is in different DB partition than current feed time, save all rows (a full backup as opposed to jut saving diff)
        if previous_feed_time.nil? || GTFS::Realtime::TripUpdate.partition_normalize_key_value(previous_feed_time) != GTFS::Realtime::TripUpdate.partition_normalize_key_value(current_feed_time)
          GTFS::Realtime::TripUpdate.create_many(
              trip_updates.collect do |trip_update|
                {
                    configuration_id: @gtfs_realtime_configuration.id,
                    interval_seconds: 0,
                    feed_timestamp: current_feed_time
                }.merge(get_trip_update_hash(trip_update))
              end
          )

          GTFS::Realtime::StopTimeUpdate.create_many(
              trip_updates.collect do |trip_update|
                trip_update.trip_update.stop_time_update.collect do |stop_time_update|
                  {
                      configuration_id: @gtfs_realtime_configuration.id,
                      trip_update_id: trip_update.id.to_s.strip,
                      interval_seconds: 0,
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
          prev_trip_updates = @previous_feeds[:trip_updates_feed].entity
          new_trip_ids = trip_updates.map{|x| x.trip_update.trip.trip_id.to_s.strip} - prev_trip_updates.map{|x| x.trip_update.trip.trip_id.to_s.strip}
          new_trip_updates = trip_updates.select{|x| new_trip_ids.include? x.trip_update.trip.trip_id.to_s.strip}

          GTFS::Realtime::TripUpdate.create_many(
              new_trip_updates.collect do |trip_update|
                {
                    configuration_id: @gtfs_realtime_configuration.id,
                    interval_seconds: 0,
                    feed_timestamp: current_feed_time
                }.merge(get_trip_update_hash(trip_update))
              end
          )

          # update all unchanged trip updates with a new end feed_timestamp
          GTFS::Realtime::TripUpdate.update_many(
              (trip_updates - new_trip_updates).collect do |trip_update|
                {
                    configuration_id: @gtfs_realtime_configuration.id,
                    feed_timestamp: previous_feed_time,
                    interval_seconds: @gtfs_realtime_configuration.interval_seconds
                }.merge(get_trip_update_hash(trip_update))
              end,
              {
                  set_array: '"'+ "feed_timestamp ='#{current_feed_time_without_timezone}', interval_seconds = \#{table_name}.interval_seconds + datatable.interval_seconds"+'"',
                  where_datatable: '"#{table_name}.configuration_id = datatable.configuration_id AND #{table_name}.id = datatable.id AND #{table_name}.trip_id = datatable.trip_id AND #{table_name}.route_id = datatable.route_id AND #{table_name}.feed_timestamp = datatable.feed_timestamp"'
              }
          )

          # store all new stop updates in an array to be added at once for performance
          all_new_stop_time_updates = new_trip_updates.collect do |trip_update|
            trip_update.trip_update.stop_time_update.collect do |stop_time_update|
              {
                  configuration_id: @gtfs_realtime_configuration.id,
                  trip_update_id: trip_update.id.to_s.strip,
                  interval_seconds: 0,
                  feed_timestamp: current_feed_time
              }.merge(get_stop_time_update_hash(stop_time_update))

            end
          end.flatten

          all_other_stop_time_updates = []

          # For all other trip updates, check stop updates for changes
          (trip_updates - new_trip_updates).each do |trip_update|

            # get all new stop time updates that weren't in previously processed feed
            # order by departure time
            # convert all stop time updates to hashes for easy comparison
            prev_stop_time_updates = @previous_feeds[:trip_updates_feed].entity.find{|x| x.id.to_s.strip == trip_update.id.to_s.strip}.trip_update.stop_time_update.sort_by { |x| x.departure&.time || 0 }.map{|x| get_stop_time_update_hash(x)}
            stop_time_updates = trip_update.trip_update.stop_time_update.sort_by { |x| x.departure&.time || 0 }.map{|x| get_stop_time_update_hash(x)}
            new_stop_time_updates = stop_time_updates - prev_stop_time_updates

            all_new_stop_time_updates +=
                new_stop_time_updates.collect do |stop_time_update|
                  {
                      configuration_id: @gtfs_realtime_configuration.id,
                      trip_update_id: trip_update.id.to_s.strip,
                      interval_seconds: 0,
                      feed_timestamp: current_feed_time
                  }.merge(stop_time_update)
                end

            # for all other stop updates, compare
            updated_stop_time_updates = (stop_time_updates - new_stop_time_updates)
            prev_stop_time_updates_to_check = (prev_stop_time_updates & updated_stop_time_updates)

            updated_stop_time_updates.each_with_index do |stop_time_update, idx|
              # if different add new row
              if stop_time_update != prev_stop_time_updates_to_check[idx]
                all_new_stop_time_updates << (
                {
                    configuration_id: @gtfs_realtime_configuration.id,
                    trip_update_id: trip_update.id.to_s.strip,
                    interval_seconds: 0,
                    feed_timestamp: current_feed_time
                }.merge(stop_time_update)

                )
              else # if not update feed timestamp
                all_other_stop_time_updates << ({
                    configuration_id: @gtfs_realtime_configuration.id,
                    trip_update_id: trip_update.id.to_s.strip,
                    feed_timestamp: previous_feed_time,
                    interval_seconds: @gtfs_realtime_configuration.interval_seconds
                }.merge(stop_time_update))
              end
            end
          end

          # save stop time updates to database
          GTFS::Realtime::StopTimeUpdate.create_many(all_new_stop_time_updates)
          GTFS::Realtime::StopTimeUpdate.update_many(
              all_other_stop_time_updates,
              {
                  set_array: '"'+ "feed_timestamp ='#{current_feed_time_without_timezone}', interval_seconds = \#{table_name}.interval_seconds + datatable.interval_seconds"+'"',
                  where_datatable: '
                    "#{table_name}.configuration_id = datatable.configuration_id AND #{table_name}.trip_update_id = datatable.trip_update_id AND #{table_name}.stop_id = datatable.stop_id AND #{table_name}.arrival_delay = datatable.arrival_delay AND #{table_name}.arrival_time = datatable.arrival_time AND #{table_name}.departure_delay = datatable.departure_delay AND #{table_name}.departure_time = datatable.departure_time AND #{table_name}.feed_timestamp = datatable.feed_timestamp"'
              }
          )

        end

        post_process('TripUpdate', feed)
      end

      def process_vehicle_positions
        feed = get_feed(@gtfs_realtime_configuration.vehicle_positions_feed)
        vehicle_positions = (feed.try(:entity) || []).select{|x| x.vehicle.present?}
        vehicle_positions_header = feed.try(:header)


        previous_feed_time = Time.at(@previous_feeds[:vehicle_positions_feed].header.timestamp) unless @previous_feeds[:vehicle_positions_feed].nil?
        current_feed_time = Time.at(vehicle_positions_header.timestamp) unless vehicle_positions_header.nil?

        pre_process('VehiclePosition', previous_feed_time, current_feed_time)

        # this data is partitioned but not checked for duplicates currently
        GTFS::Realtime::VehiclePosition.create_many(
            vehicle_positions.collect do |vehicle|
              {
                  configuration_id: @gtfs_realtime_configuration.id,
                  interval_seconds: 0,
                  id: vehicle.id.to_s.strip,
                  trip_id: vehicle.vehicle.trip.trip_id.to_s.strip,
                  stop_id: vehicle.vehicle.stop_id.to_s.strip,
                  latitude: vehicle.vehicle.position.try(:latitude).try(:to_f),
                  longitude: vehicle.vehicle.position.try(:longitude).try(:to_f),
                  bearing: vehicle.vehicle.position.try(:bearing).try(:to_f),
                  timestamp: Time.at(vehicle.vehicle.timestamp),
                  feed_timestamp: current_feed_time
              }
            end
        )

        post_process('VehiclePosition', feed)
      end

      def process_service_alerts
        feed = get_feed(@gtfs_realtime_configuration.service_alerts_feed)
        service_alerts = (feed.try(:entity) || []).select{|x| x.alert.present?}
        service_alerts_header = feed.try(:header)

        previous_feed_time = Time.at(@previous_feeds[:service_alerts_feed].header.timestamp) unless @previous_feeds[:service_alerts_feed].nil?
        current_feed_time = Time.at(service_alerts_header.timestamp) unless service_alerts_header.nil?

        pre_process('ServiceAlert', previous_feed_time, current_feed_time)

        # this data is partitioned but not checked for duplicates currently
        GTFS::Realtime::ServiceAlert.create_many(
            service_alerts.collect do |service_alert|
              {
                  configuration_id: @gtfs_realtime_configuration.id,
                  interval_seconds: 0,
                  id: service_alert.id.to_s.strip,
                  stop_id: service_alert.alert.informed_entity.first.stop_id.to_s.strip,
                  header_text: service_alert.alert.header_text.translation.first.text,
                  description_text: service_alert.alert.description_text.translation.first.text,
                  start_time: Time.at(service_alert.alert.active_period.first.start),
                  end_time: Time.at(service_alert.alert.active_period.first.end),
                  feed_timestamp: current_feed_time
              }
            end
        )

        post_process('ServiceAlert', feed)
      end

      private

      def get_feed(path)
        return nil if path.nil?

        if File.exists?(path)
          data = File.open(path, 'r'){|f| f.read}
        else
          data = Net::HTTP.get(URI.parse(path))
        end

        TransitRealtime::FeedMessage.decode(data)
      end


      def get_trip_update_hash(trip_update)
        {
            id: trip_update.id.to_s.strip,
            trip_id: trip_update.trip_update.trip.trip_id.to_s.strip,
            route_id: trip_update.trip_update.trip.route_id.to_s.strip
        }
      end

      def get_stop_time_update_hash(stop_time_update)
        {
            stop_id: stop_time_update.stop_id.to_s.strip,
            arrival_delay: stop_time_update.arrival&.delay,
            arrival_time: (stop_time_update.arrival&.time&.> 0) ? Time.at(stop_time_update.arrival.time) : nil,
            departure_delay: stop_time_update.departure&.delay,
            departure_time: (stop_time_update.departure&.time&.> 0) ? Time.at(stop_time_update.departure.time) : nil,
        }
      end
    end
  end
end
