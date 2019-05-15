require "gtfs/realtime/nearby"

module GTFS
  class Realtime
    class VehiclePosition < GTFS::Realtime::PartitionedByConfigurationAndTime
      include GTFS::Realtime::Nearby

      belongs_to :configuration

      belongs_to :stop
      belongs_to :trip

      partitioned do |partition|
        partition.index :stop_id
        partition.index :trip_id
      end
    end
  end
end
