class AddApiKeyConfigurations < ActiveRecord::Migration[5.0]
  def up
    unless column_exists? :gtfs_realtime_configurations, :trip_updates_api_key
      add_column :gtfs_realtime_configurations, :trip_updates_api_key, :string, after: :trip_updates_feed
      add_column :gtfs_realtime_configurations, :vehicle_positions_api_key, :string, after: :vehicle_positions_feed
    end
  end

  def down
    remove_column :gtfs_realtime_configurations, :trip_updates_api_key
    remove_column :gtfs_realtime_configurations, :vehicle_positions_api_key
  end
end
