class CreatePartitions < ActiveRecord::Migration[5.0]
  def up
    GTFS::Realtime::TripUpdate.create_infrastructure
    GTFS::Realtime::StopTimeUpdate.create_infrastructure
    GTFS::Realtime::VehiclePosition.create_infrastructure
    GTFS::Realtime::ServiceAlert.create_infrastructure

    GTFS::Realtime::Feed.create_infrastructure
  end

  def down
    GTFS::Realtime::TripUpdate.delete_infrastructure
    GTFS::Realtime::StopTimeUpdate.delete_infrastructure
    GTFS::Realtime::VehiclePosition.delete_infrastructure
    GTFS::Realtime::ServiceAlert.delete_infrastructure

    GTFS::Realtime::Feed.delete_infrastructure
  end
end
