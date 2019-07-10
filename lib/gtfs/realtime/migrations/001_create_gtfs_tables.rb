class CreateGTFSTables < ActiveRecord::Migration[5.0]
  def change
    create_table :gtfs_realtime_configurations do |t|
      t.string :name
      t.string :handler
      t.string :static_feed
      t.string :trip_updates_feed
      t.string :vehicle_positions_feed
      t.string :service_alerts_feed
      t.integer :interval_seconds
    end

    create_table :gtfs_realtime_trip_updates do |t|
      t.integer :configuration_id, index: true
      t.timestamp :feed_timestamp
      t.integer :interval_seconds
      t.string :trip_id
      t.string :route_id
      t.integer :direction_id
      t.string :start_time
      t.string :start_date
      t.integer :schedule_relationship
      t.string :vehicle_id
      t.string :vehicle_label
      t.string :license_plate
      t.timestamp :timestamp
      t.integer :delay
    end
    change_column :gtfs_realtime_trip_updates, :id, :string

    create_table :gtfs_realtime_stop_time_updates, id: false do |t|
      t.integer :configuration_id, index: true
      t.timestamp :feed_timestamp
      t.integer :interval_seconds
      t.string :trip_update_id, index: true
      t.string :stop_id, index: true
      t.integer :stop_sequence
      t.integer :schedule_relationship
      t.integer :arrival_delay
      t.timestamp :arrival_time
      t.integer :arrival_uncertainty
      t.integer :departure_delay
      t.timestamp :departure_time
      t.integer :departure_uncertainty
    end

    create_table :gtfs_realtime_vehicle_positions do |t|
      t.integer :configuration_id, index: true
      t.timestamp :feed_timestamp
      t.integer :interval_seconds
      t.string :vehicle_id
      t.string :vehicle_label
      t.string :license_plate
      t.string :trip_id, index: true
      t.string :route_id
      t.integer :direction_id
      t.string :start_time
      t.string :start_date
      t.integer :schedule_relationship
      t.string :stop_id, index: true
      t.integer :current_stop_sequence
      t.integer :current_status
      t.integer :congestion_level
      t.integer :occupancy_status
      t.float :latitude
      t.float :longitude
      t.float :bearing
      t.float :odometer
      t.float :speed
      t.timestamp :timestamp
    end
    change_column :gtfs_realtime_vehicle_positions, :id, :string

    create_table :gtfs_realtime_service_alerts do |t|
      t.integer :configuration_id, index: true
      t.timestamp :feed_timestamp
      t.integer :interval_seconds
      t.string :agency_id
      t.integer :route_type
      t.string :trip_id
      t.string :route_id
      t.integer :direction_id
      t.string :start_time
      t.string :start_date
      t.integer :schedule_relationship
      t.string :stop_id, index: true
      t.integer :cause
      t.integer :effect
      t.integer :severity_level
      t.string :url
      t.string :header_text
      t.text :description_text
      t.timestamp :start_time
      t.timestamp :end_time
    end
    change_column :gtfs_realtime_service_alerts, :id, :string

    create_table :gtfs_realtime_feeds do |t|
      t.integer :configuration_id, index: true
      t.timestamp :feed_timestamp
      t.string :class_name
      t.string :feed_file
    end
  end
end
