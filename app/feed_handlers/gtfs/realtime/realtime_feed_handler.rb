module GTFS
  class Realtime
    class RealtimeFeedHandler

      attr_accessor :gtfs_realtime_configuration
      attr_accessor :put_metric_data_service

      def initialize(gtfs_realtime_configuration: GTFS::Realtime::Configuration.new)
        self.gtfs_realtime_configuration = gtfs_realtime_configuration
        self.put_metric_data_service = PutMetricDataService.new
      end

      def pre_process(class_name, current_feed_time, feed_file, has_entries=true)

        # check if need to create new partition
        # feed table
        if current_feed_time
          GTFS::Realtime::Feed.create_new_partition_tables([[@gtfs_realtime_configuration.id, current_feed_time.at_beginning_of_week]]) unless GTFS::Realtime::Feed.partition_tables.include? "p#{@gtfs_realtime_configuration.id}_#{current_feed_time.at_beginning_of_week.strftime('%Y%m%d')}"

          klass = "GTFS::Realtime::#{class_name}".constantize
          klass.create_new_partition_tables([[@gtfs_realtime_configuration.id, current_feed_time.at_beginning_of_week]]) unless klass.partition_tables.include? "p#{@gtfs_realtime_configuration.id}_#{current_feed_time.at_beginning_of_week.strftime('%Y%m%d')}"

          if class_name == 'TripUpdate'
            GTFS::Realtime::StopTimeUpdate.create_new_partition_tables([[@gtfs_realtime_configuration.id, current_feed_time.at_beginning_of_week]]) unless GTFS::Realtime::StopTimeUpdate.partition_tables.include? "p#{@gtfs_realtime_configuration.id}_#{current_feed_time.at_beginning_of_week.strftime('%Y%m%d')}"
          end
        end

        # save the feed file

        if class_name == 'TripUpdate'
          status = nil
        elsif current_feed_time.nil?
          status = 'Errored'
        elsif !has_entries
          status = 'Empty'
        else
          status = 'Successful'
        end

        temp_file = Tempfile.new "#{Time.now.to_i}_#{@gtfs_realtime_configuration.name}", "#{Rails.root}/tmp", encoding: 'ascii-8bit'
        ObjectSpace.undefine_finalizer(temp_file)
        begin
          temp_file << feed_file
          GTFS::Realtime::Feed.create!(configuration_id: @gtfs_realtime_configuration.id, feed_timestamp: (current_feed_time || Time.now), class_name: class_name, feed_file: temp_file, feed_status_type_id: GTFS::Realtime::FeedStatusType.find_by(name: status).try(:id))
        rescue => ex
          Rails.logger.warn ex
        ensure
          temp_file.close
          temp_file.unlink
        end

      end

      def process

        errored = false

        if @gtfs_realtime_configuration.trip_updates_feed.present?

          feed_file = get_feed_file(@gtfs_realtime_configuration.trip_updates_feed)
          feed = get_feed(feed_file)
          trip_updates_header = feed.try(:header)

          # get the feed time of the feed being processed currently
          current_feed_time = Time.at(trip_updates_header.timestamp) unless trip_updates_header.nil?

          pre_process('TripUpdate', current_feed_time, feed_file)


         if GTFS::Realtime::Feed.from_partition(@gtfs_realtime_configuration.id, Date.today.at_beginning_of_week).where(class_name: 'TripUpdate', feed_status_type_id: GTFS::Realtime::FeedStatusType.find_by(name: 'Running').id).count == 0
           GTFS::Realtime::Feed.from_partition(@gtfs_realtime_configuration.id, Date.today.at_beginning_of_week).order(:feed_timestamp).where(class_name: 'TripUpdate', feed_status_type_id: nil).each do |trip_updates_feed|
             start_time = Time.now

             Rails.logger.info "Starting GTFS-RT refresh for TripUpdate #{@gtfs_realtime_configuration.name} at #{start_time}."
             Crono.logger.info "Starting GTFS-RT refresh for TripUpdate #{@gtfs_realtime_configuration.name} at #{start_time} in Crono." if Crono.logger

             trip_updates_feed.update_columns(feed_status_type_id: GTFS::Realtime::FeedStatusType.find_by(name: 'Running').id)
             status = nil
             GTFS::Realtime::Model.transaction do
               begin
                 status = process_trip_updates(trip_updates_feed)
               rescue => ex
                 errored = true
                 Rails.logger.error ex
                 Crono.logger.error ex if Crono.logger
               end
             end # end of ActiveRecord transaction

             trip_updates_feed.update_columns(feed_status_type_id: GTFS::Realtime::FeedStatusType.find_by(name: (status || 'Errored')).id)

             @put_metric_data_service.put_metric("#{@gtfs_realtime_configuration.name}:Runtime", 'Seconds',Time.now - start_time)
             Rails.logger.info "Finished GTFS-RT refresh for TripUpdate #{@gtfs_realtime_configuration.name} at #{Time.now}. Started #{start_time} and took #{Time.now - start_time} seconds in Crono."
             Crono.logger.info "Finished GTFS-RT refresh for TripUpdate #{@gtfs_realtime_configuration.name} at #{Time.now}. Started #{start_time} and took #{Time.now - start_time} seconds in Crono." if Crono.logger
           end
          end
        end

        if @gtfs_realtime_configuration.vehicle_positions_feed.present?
          start_time = Time.now

          Rails.logger.info "Starting GTFS-RT refresh for VehiclePosition #{@gtfs_realtime_configuration.name} at #{start_time}."
          Crono.logger.info "Starting GTFS-RT refresh for VehiclePosition #{@gtfs_realtime_configuration.name} at #{start_time} in Crono." if Crono.logger
          GTFS::Realtime::Model.transaction do
            begin
              process_vehicle_positions
            rescue
              errored = true
              Rails.logger.error ex
              Crono.logger.error ex if Crono.logger
            end
          end
          Rails.logger.info "Finished GTFS-RT refresh for VehiclePosition #{@gtfs_realtime_configuration.name} at #{Time.now}. Started #{start_time} and took #{Time.now - start_time} seconds in Crono."
          Crono.logger.info "Finished GTFS-RT refresh for VehiclePosition #{@gtfs_realtime_configuration.name} at #{Time.now}. Started #{start_time} and took #{Time.now - start_time} seconds in Crono." if Crono.logger
        end

        if @gtfs_realtime_configuration.service_alerts_feed.present?
          start_time = Time.now

          Rails.logger.info "Starting GTFS-RT refresh for ServiceAlert #{@gtfs_realtime_configuration.name} at #{start_time}."
          Crono.logger.info "Starting GTFS-RT refresh for ServiceAlert #{@gtfs_realtime_configuration.name} at #{start_time} in Crono." if Crono.logger

          GTFS::Realtime::Model.transaction do
            begin
              process_service_alerts
            rescue
              errored = true
              Rails.logger.error ex
              Crono.logger.error ex if Crono.logger
            end
          end
          Rails.logger.info "Finished GTFS-RT refresh for ServiceAlert #{@gtfs_realtime_configuration.name} at #{Time.now}. Started #{start_time} and took #{Time.now - start_time} seconds in Crono."
          Crono.logger.info "Finished GTFS-RT refresh for ServiceAlert #{@gtfs_realtime_configuration.name} at #{Time.now}. Started #{start_time} and took #{Time.now - start_time} seconds in Crono." if Crono.logger
        end

        @put_metric_data_service.put_metric("#{@gtfs_realtime_configuration.name}:#{errored ? 'ErrorCount' : 'HealthyCount'}", 'Count',1)
      end


      def process_trip_updates(trip_updates_feed)

        feed_file = get_feed_file(trip_updates_feed.feed_file.url)
        feed = get_feed(feed_file)
        trip_updates_header = feed.try(:header)

        # get the feed time of the feed being processed currently
        current_feed_time = Time.at(trip_updates_header.timestamp) unless trip_updates_header.nil?
        current_feed_time_without_timezone = Time.zone.at(current_feed_time.to_i) # used as string in query

        trip_updates = (feed.try(:entity) || []).select{|x| x.trip_update.present?}.map{|x| trip_update_to_database_attributes(x).merge({stop_time_updates: x.trip_update.stop_time_update.map{|y| stop_time_update_to_database_attributes(y)}})}

        @put_metric_data_service.put_metric("#{@gtfs_realtime_configuration.name}:TripUpdateCount", 'Count',trip_updates.count)

        # update feed status
        if current_feed_time.nil?
          status = 'Errored'
        elsif trip_updates.empty?
          status = 'Empty'
        else
          # get the feed time of the last feed processed
          prev_trip_updates_feed = get_cached_objects(@gtfs_realtime_configuration, 'TripUpdate')
          previous_feed_time = Time.at(prev_trip_updates_feed.header.timestamp) unless prev_trip_updates_feed.nil?

          # update cache
          clear_cached_objects(@gtfs_realtime_configuration, 'TripUpdate')
          cache_objects(@gtfs_realtime_configuration, 'TripUpdate', feed_file) unless feed_file.nil?

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
                  }.merge(trip_update.except(:stop_time_updates))
                end
            )

            GTFS::Realtime::StopTimeUpdate.create_many(
                trip_updates.collect do |trip_update|
                  trip_update[:stop_time_updates].collect do |stop_time_update|
                    {
                        configuration_id: @gtfs_realtime_configuration.id,
                        trip_update_id: trip_update[:id],
                        interval_seconds: 0,
                        feed_timestamp: current_feed_time
                    }.merge(stop_time_update)
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
            prev_trip_updates = (prev_trip_updates_feed.entity || []).select{|x| x.trip_update.present?}.map{|x| trip_update_to_database_attributes(x).merge({stop_time_updates: x.trip_update.stop_time_update.map{|y| stop_time_update_to_database_attributes(y)}})}
            new_trip_updates = trip_updates - prev_trip_updates

            GTFS::Realtime::TripUpdate.create_many(
                new_trip_updates.collect do |trip_update|
                  {
                      configuration_id: @gtfs_realtime_configuration.id,
                      interval_seconds: 0,
                      feed_timestamp: current_feed_time
                  }.merge(trip_update.except(:stop_time_updates))
                end
            )

            # update all unchanged trip updates with a new end feed_timestamp
            GTFS::Realtime::TripUpdate.update_many(
                (trip_updates - new_trip_updates).collect do |trip_update|
                  {
                      configuration_id: @gtfs_realtime_configuration.id,
                      feed_timestamp: previous_feed_time,
                      interval_seconds: @gtfs_realtime_configuration.interval_seconds
                  }.merge(trip_update.except(:stop_time_updates))
                end,
                {
                    set_array: '"'+ "feed_timestamp ='#{current_feed_time_without_timezone}', interval_seconds = \#{table_name}.interval_seconds + datatable.interval_seconds"+'"',
                    where_datatable: '"#{table_name}.configuration_id = datatable.configuration_id AND #{table_name}.id = datatable.id AND #{table_name}.trip_id = datatable.trip_id AND #{table_name}.route_id = datatable.route_id AND #{table_name}.feed_timestamp = datatable.feed_timestamp"'
                }
            )

            # store all new stop updates in an array to be added at once for performance
            all_new_stop_time_updates = new_trip_updates.collect do |trip_update|
              trip_update[:stop_time_updates].collect do |stop_time_update|
                {
                    configuration_id: @gtfs_realtime_configuration.id,
                    trip_update_id: trip_update[:id],
                    interval_seconds: 0,
                    feed_timestamp: current_feed_time
                }.merge(stop_time_update)

              end
            end.flatten

            all_other_stop_time_updates = []

            # For all other trip updates, check stop updates for changes
            (trip_updates - new_trip_updates).each do |trip_update|

              # get all new stop time updates that weren't in previously processed feed
              # order by departure time
              # convert all stop time updates to hashes for easy comparison
              prev = prev_trip_updates.find{|x| x[:id] == trip_update[:id]}
              prev_stop_time_updates = (prev.present? ? prev[:stop_time_updates] : []).sort_by { |x| x[:departure_time] || 0 }
              stop_time_updates = trip_update[:stop_time_updates].sort_by { |x| x[:departure_time] || 0 }
              new_stop_time_updates = stop_time_updates - prev_stop_time_updates

              all_new_stop_time_updates +=
                  new_stop_time_updates.collect do |stop_time_update|
                    {
                        configuration_id: @gtfs_realtime_configuration.id,
                        trip_update_id: trip_update[:id],
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
                      trip_update_id: trip_update[:id],
                      interval_seconds: 0,
                      feed_timestamp: current_feed_time
                  }.merge(stop_time_update)

                  )
                else # if not update feed timestamp
                  all_other_stop_time_updates << ({
                      configuration_id: @gtfs_realtime_configuration.id,
                      trip_update_id: trip_update[:id],
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

          status = 'Successful'
        end

        return status
      end

      def process_vehicle_positions
        feed_file = get_feed_file(@gtfs_realtime_configuration.vehicle_positions_feed)
        feed = get_feed(feed_file)
        vehicle_positions = (feed.try(:entity) || []).select{|x| x.vehicle.present?}
        vehicle_positions_header = feed.try(:header)

        prev_vehicle_positions_feed = get_cached_objects(@gtfs_realtime_configuration, 'VehiclePosition')
        previous_feed_time = Time.at(prev_vehicle_positions_feed.header.timestamp) unless prev_vehicle_positions_feed.nil?
        current_feed_time = Time.at(vehicle_positions_header.timestamp) unless vehicle_positions_header.nil?

        pre_process('VehiclePosition', current_feed_time, feed_file,!vehicle_positions.empty?)

        # this data is partitioned but not checked for duplicates currently
        GTFS::Realtime::VehiclePosition.create_many(
            vehicle_positions.collect do |vehicle|
              {
                  configuration_id: @gtfs_realtime_configuration.id,
                  interval_seconds: 0,
                  id: vehicle.id.to_s.strip,
                  vehicle_id: vehicle.vehicle.vehicle.id.to_s.strip,
                  vehicle_label: vehicle.vehicle.vehicle.label.to_s.strip,
                  license_plate: vehicle.vehicle.vehicle.license_plate.to_s.strip,
                  trip_id: vehicle.vehicle.trip.trip_id.to_s.strip,
                  route_id: vehicle.vehicle.trip.route_id.to_s.strip,
                  direction_id: vehicle.vehicle.trip.direction_id,
                  start_time: vehicle.vehicle.trip.start_time.to_s.strip,
                  start_date: vehicle.vehicle.trip.start_date.to_s.strip,
                  schedule_relationship: vehicle.vehicle.trip.schedule_relationship,
                  current_stop_sequence: vehicle.vehicle.current_stop_sequence,
                  current_status: vehicle.vehicle.current_status,
                  congestion_level: vehicle.vehicle.congestion_level,
                  occupancy_status: vehicle.vehicle.occupancy_status,
                  stop_id: vehicle.vehicle.stop_id.to_s.strip,
                  latitude: vehicle.vehicle.position.try(:latitude).try(:to_f),
                  longitude: vehicle.vehicle.position.try(:longitude).try(:to_f),
                  bearing: vehicle.vehicle.position.try(:bearing).try(:to_f),
                  odometer: vehicle.vehicle.position.try(:odometer).try(:to_f),
                  speed: vehicle.vehicle.position.try(:speed).try(:to_f),
                  timestamp: Time.at(vehicle.vehicle.timestamp),
                  feed_timestamp: current_feed_time
              }
            end
        )
      end

      def process_service_alerts
        feed_file = get_feed_file(@gtfs_realtime_configuration.service_alerts_feed)
        feed = get_feed(feed_file)
        service_alerts = (feed.try(:entity) || []).select{|x| x.alert.present?}
        service_alerts_header = feed.try(:header)

        prev_service_alerts_feed = get_cached_objects(@gtfs_realtime_configuration, 'ServiceAlert')
        previous_feed_time = Time.at(prev_service_alerts_feed.header.timestamp) unless prev_service_alerts_feed.nil?
        current_feed_time = Time.at(service_alerts_header.timestamp) unless service_alerts_header.nil?

        pre_process('ServiceAlert', current_feed_time, feed_file, !service_alerts.empty?)

        new_alerts = []

        service_alerts.each do |service_alert|
          service_alert.active_period.each_with_index do |active_period,idx|
            new_alerts << {
                configuration_id: @gtfs_realtime_configuration.id,
                interval_seconds: 0,
                id: service_alert.id.to_s.strip,
                agency_id: service_alert.alert.informed_entity[idx].agency_id.to_s.strip,
                route_id: service_alert.alert.informed_entity[idx].route_id.to_s.strip,
                route_type: service_alert.alert.informed_entity[idx].route_type,
                trip_id: service_alert.alert.informed_entity[idx].trip.trip_id.to_s.strip,
                direction_id: service_alert.alert.informed_entity[idx].trip.direction_id,
                #start_time: service_alert.alert.informed_entity[idx].trip.start_time.to_s.strip,
                start_date: service_alert.alert.informed_entity[idx].trip.start_date.to_s.strip,
                schedule_relationship: service_alert.alert.informed_entity[idx].trip.schedule_relationship,
                current_stop_sequence: service_alert.alert.informed_entity[idx].trip.current_stop_sequence,
                stop_id: service_alert.alert.informed_entity[idx].stop_id.to_s.strip,
                cause: service_alert.alert.cause,
                effect: service_alert.alert.effect,
                severity_level: service_alert.alert.severity_level,
                url: service_alert.alert.url.translation.first.text,
                header_text: service_alert.alert.header_text.translation.first.text,
                description_text: service_alert.alert.description_text.translation.first.text,
                start_time: Time.at(active_period.start),
                end_time: Time.at(active_period.end),
                feed_timestamp: current_feed_time
            }
          end
        end

        # this data is partitioned but not checked for duplicates currently
        GTFS::Realtime::ServiceAlert.create_many(new_alerts)
      end


      def recreate(opts)

        if opts[:timestamp].present?
          timestamp = Chronic.parse(opts[:timestamp])
          feeds = GTFS::Realtime::Feed.from_partition(@gtfs_realtime_configuration.id).where("feed_timestamp <= ?", timestamp)
        else
          feeds = GTFS::Realtime::Feed.from_partition(@gtfs_realtime_configuration.id)
        end
        if opts[:feed_status]
          feed_status_names = opts[:feed_status].split(',')
          feeds = feeds.where(feed_status_type_id: GTFS::Realtime::FeedStatusType.where(name: feed_status_names).select(:id))
        end

        timestamp = feeds.maximum(:feed_timestamp)

        if GTFS::Realtime::TripUpdate.partition_tables.include? "p#{@gtfs_realtime_configuration.id}_#{timestamp.at_beginning_of_week.strftime('%Y%m%d')}"
          @trip_updates = GTFS::Realtime::TripUpdate.from_partition(@gtfs_realtime_configuration.id, timestamp.at_beginning_of_week).where("(feed_timestamp - (interval_seconds * interval '1 second')) <= ? AND ? <= feed_timestamp", timestamp, timestamp)
        else
          @trip_updates = []
        end
        if GTFS::Realtime::StopTimeUpdate.partition_tables.include? "p#{@gtfs_realtime_configuration.id}_#{timestamp.at_beginning_of_week.strftime('%Y%m%d')}"
          @stop_time_updates = GTFS::Realtime::StopTimeUpdate.from_partition(@gtfs_realtime_configuration.id, timestamp.at_beginning_of_week).where("(feed_timestamp - (interval_seconds * interval '1 second')) <= ? AND ? <= feed_timestamp", timestamp, timestamp)
        else
          @stop_time_updates = []
        end
        if GTFS::Realtime::VehiclePosition.partition_tables.include? "p#{@gtfs_realtime_configuration.id}_#{timestamp.at_beginning_of_week.strftime('%Y%m%d')}"
          @vehicle_positions = GTFS::Realtime::VehiclePosition.from_partition(@gtfs_realtime_configuration.id, timestamp.at_beginning_of_week).where("(feed_timestamp - (interval_seconds * interval '1 second')) <= ? AND ? <= feed_timestamp", timestamp, timestamp)
        else
          @vehicle_positions = []
        end

        if GTFS::Realtime::ServiceAlert.partition_tables.include? "p#{@gtfs_realtime_configuration.id}_#{timestamp.at_beginning_of_week.strftime('%Y%m%d')}"
          @service_alerts = GTFS::Realtime::ServiceAlert.from_partition(@gtfs_realtime_configuration.id, timestamp.at_beginning_of_week).where("(feed_timestamp - (interval_seconds * interval '1 second')) <= ? AND ? <= feed_timestamp", timestamp, timestamp)
       else
         @service_alerts = []
       end

        entities = @trip_updates.collect do |trip_update_row|

          stop_time_updates = @stop_time_updates.where(trip_update_id: trip_update_row.id).collect do |stop_time_update|
            stop_time_update_from_database_attributes(stop_time_update)
          end
          trip_update = trip_update_from_database_attributes(trip_update_row)
          trip_update.stop_time_update = stop_time_updates
          TransitRealtime::FeedEntity.new(id: trip_update_row.id, trip_update: trip_update)
        end


        @vehicle_positions.each do |vehicle_position_row|
          trip = TransitRealtime::TripDescriptor.new(trip_id: vehicle_position_row.trip_id, route_id: vehicle_position_row.route_id, direction_id: vehicle_position_row.direction_id, start_time: vehicle_position_row.start_time, start_date: vehicle_position_row.start_date, schedule_relationship: vehicle_position_row.schedule_relationship)
          vehicle = TransitRealtime::VehicleDescriptor.new(id: vehicle_position_row.vehicle_id, label: vehicle_position_row.vehicle_label, license_plate: vehicle_position_row.license_plate)
          vehicle_position = TransitRealtime::VehiclePosition.new(trip: trip, vehicle: vehicle, current_stop_sequence: vehicle_position_row.current_stop_sequence, stop_id: vehicle_position_row.stop_id, current_status: vehicle_position_row.current_status, timestamp: vehicle_position_row.timestamp.to_i, congestion_level: vehicle_position_row.congestion_level, occupancy_status: vehicle_position_row.occupancy_status)
          vehicle_position.position = TransitRealtime::Position.new(latitude: vehicle_position_row.latitude, longitude: vehicle_position_row.longitude, bearing: vehicle_position_row.bearing, odometer: vehicle_position_row.odometer, speed: vehicle_position_row.speed)

          entity_idx = entities.index{|x| x.id == vehicle_position_row.id}
          if entity_idx.nil?
            entities << TransitRealtime::FeedEntity.new(id: vehicle_position_row.id, vehicle: vehicle_position)
          else
            entities[entity_idx].vehicle = vehicle_position
          end

        end


        @service_alerts.each do |alert_row|
          trip = TransitRealtime::TripDescriptor.new(trip_id: alert_row.trip_id, route_id: alert_row.route_id, direction_id: alert_row.direction_id, start_time: alert_row.start_time, start_date: alert_row.start_date, schedule_relationship: alert_row.schedule_relationship)
          informed_entity = TransitRealtime::EntitySelector.new(agency_id: alert_row.agency_id, route_id: alert_row.route_id, route_type: alert_row.route_type, trip: trip, stop_id: alert_row.stop_id)

          url = TransitRealtime::TranslatedString.new(translation: [TransitRealtime::TranslatedString::Translation.new(text: alert_row.url)])
          header_text = TransitRealtime::TranslatedString.new(translation: [TransitRealtime::TranslatedString::Translation.new(text: alert_row.header_text)])
          description_text = TransitRealtime::TranslatedString.new(translation: [TransitRealtime::TranslatedString::Translation.new(text: alert_row.description_text)])
          active_period = TransitRealtime::TimeRange.new(start: alert_row.start_time.to_i, end: alert_row.end_time.to_i)

          alert = TransitRealtime::Alert.new(active_period: [active_period], informed_entity: [informed_entity], cause: alert_row.cause, effect: alert_row.effect, url: url, header_text: header_text, description_text: description_text)

          entity_idx = entities.index{|x| x.id == alert_row.id}
          if entity_idx.nil?
            entities << TransitRealtime::FeedEntity.new(id: alert_row.id, alert: alert)
          else
            entities[entity_idx].alert = alert
          end

        end

        feed_header = TransitRealtime::FeedHeader.new(timestamp: timestamp.to_i, gtfs_realtime_version: '1.0') # assume gtfs realtime version

        return TransitRealtime::FeedMessage.new(header: feed_header, entity: entities)
      end

      private

      def get_feed_file(path)
        return nil if path.nil?

        if File.exists?(path)
          data = File.open(path, 'r'){|f| f.read}
        else
          data = Net::HTTP.get(URI.parse(path))
        end

        data
      end


      def get_feed(data)
        begin
          return TransitRealtime::FeedMessage.parse(data)
        rescue
          Rails.logger.info "Could not parse GTFS-RT file"
          Crono.logger.info "Could not parse GTFS-RT file" if Crono.logger

          return nil
        end
      end

      #-----------------------------------------------------------------------------
      # Cache an object
      #-----------------------------------------------------------------------------
      def cache_objects(config, class_name, objects)
        Rails.logger.info "FeedHandler CACHE put for config #{config} #{class_name}"
        Crono.logger.info "FeedHandler CACHE put for config #{config} #{class_name}" if Crono.logger
        Rails.cache.fetch(get_cache_key(config,class_name), :force => true) { objects }
      end

      #-----------------------------------------------------------------------------
      # Return a cached object. If the object does not exist, an empty array is
      # returned
      #-----------------------------------------------------------------------------
      def get_cached_objects(config,class_name)
        Rails.logger.info "FeedHandler CACHE get for key #{config} #{class_name}"
        Crono.logger.info "FeedHandler CACHE get for key #{config} #{class_name}" if Crono.logger
        ret = Rails.cache.fetch(get_cache_key(config,class_name))

        return get_feed(ret)
      end

      def get_cache_key(config,class_name)
        return "#{config.name}_#{class_name.tableize}_feed"
      end

      def clear_cached_objects(config,class_name)
        Rails.logger.debug "ApplicationController CACHE clear for key #{config} #{class_name}"
        Rails.cache.delete(get_cache_key(config,class_name))
      end


      def trip_update_to_database_attributes(trip_update)
        {
            id: trip_update.id.to_s.strip,
            trip_id: trip_update.trip_update.trip.trip_id.to_s.strip,
            route_id: trip_update.trip_update.trip.route_id.to_s.strip,
            direction_id: trip_update.trip_update.trip.direction_id,
            start_time: trip_update.trip_update.trip.start_time.to_s.strip,
            start_date: trip_update.trip_update.trip.start_date.to_s.strip,
            schedule_relationship: trip_update.trip_update.trip.schedule_relationship,
            vehicle_id: trip_update.trip_update.vehicle.id.to_s.strip,
            vehicle_label: trip_update.trip_update.vehicle.label.to_s.strip,
            license_plate: trip_update.trip_update.vehicle.license_plate.to_s.strip,
            timestamp: Time.at(trip_update.trip_update.timestamp),
            delay: trip_update.trip_update.delay
        }
      end

      def trip_update_from_database_attributes(trip_update_row)
        trip = TransitRealtime::TripDescriptor.new(trip_id: trip_update_row.trip_id, route_id: trip_update_row.route_id, direction_id: trip_update_row.direction_id, start_time: trip_update_row.start_time, start_date: trip_update_row.start_date, schedule_relationship: trip_update_row.schedule_relationship)
        vehicle = TransitRealtime::VehicleDescriptor.new(id: trip_update_row.vehicle_id, label: trip_update_row.vehicle_label, license_plate: trip_update_row.license_plate)

        TransitRealtime::TripUpdate.new(trip: trip, vehicle: vehicle,timestamp: trip_update_row.timestamp.to_i, delay: trip_update_row.delay)
      end

      def stop_time_update_to_database_attributes(stop_time_update)
        {
            stop_id: stop_time_update.stop_id.to_s.strip,
            stop_sequence: stop_time_update.stop_sequence,
            schedule_relationship: stop_time_update.schedule_relationship,
            arrival_delay: stop_time_update.arrival&.delay,
            arrival_time: (stop_time_update.arrival&.time&.> 0) ? Time.at(stop_time_update.arrival.time) : nil,
            arrival_uncertainty: stop_time_update.arrival&.uncertainty,
            departure_delay: stop_time_update.departure&.delay,
            departure_time: (stop_time_update.departure&.time&.> 0) ? Time.at(stop_time_update.departure.time) : nil,
            departure_uncertainty: stop_time_update.departure&.uncertainty,
        }
      end

      def stop_time_update_from_database_attributes(stop_time_update)
        arrival = TransitRealtime::TripUpdate::StopTimeEvent.new(time: stop_time_update.arrival_time.to_i, delay: stop_time_update.arrival_delay, uncertainty: stop_time_update.arrival_uncertainty)
        departure = TransitRealtime::TripUpdate::StopTimeEvent.new(time: stop_time_update.departure_time.to_i, delay: stop_time_update.departure_delay, uncertainty: stop_time_update.departure_uncertainty)

        TransitRealtime::TripUpdate::StopTimeUpdate.new(
            stop_sequence: stop_time_update.stop_sequence,
            stop_id: stop_time_update.stop_id,
            arrival: arrival,
            departure: departure,
            schedule_relationship: stop_time_update.schedule_relationship
        )
      end

    end
  end
end
