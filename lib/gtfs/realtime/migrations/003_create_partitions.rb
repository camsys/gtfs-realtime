class CreatePartitions < ActiveRecord::Migration[5.0]
  def up
    GTFS::Realtime::TripUpdate.create_infrastructure
    # run in loading static feed - when routes are loaded
    # GTFS::Realtime::TripUpdate.create_new_partition_tables(GTFS::Realtime::Route.distinct.map(&:id).map(&:downcase))

    GTFS::Realtime::StopTimeUpdate.create_infrastructure
    GTFS::Realtime::StopTimeUpdate.create_new_partition_tables(GTFS::Realtime::StopTimeUpdate.partition_generate_range(Date.parse('2019-01-01'), Date.parse('2019-12-31')))

    GTFS::Realtime::VehiclePosition.create_infrastructure
    GTFS::Realtime::VehiclePosition.create_new_partition_tables(GTFS::Realtime::VehiclePosition.partition_generate_range(Date.parse('2019-01-01'), Date.parse('2019-12-31')))

    GTFS::Realtime::ServiceAlert.create_infrastructure
    GTFS::Realtime::ServiceAlert.create_new_partition_tables(GTFS::Realtime::ServiceAlert.partition_generate_range(Date.parse('2019-01-01'), Date.parse('2019-12-31')))

  end

  def down
    GTFS::Realtime::TripUpdate.delete_infrastructure
    GTFS::Realtime::StopTimeUpdate.delete_infrastructure
    GTFS::Realtime::VehiclePosition.delete_infrastructure
    GTFS::Realtime::ServiceAlert.delete_infrastructure
  end
end
