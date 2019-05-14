require "gtfs/realtime/nearby"

module GTFS
  class Realtime
    class VehiclePosition < GTFS::Realtime::PartitionedByConfigurationAndTime
      include GTFS::Realtime::Nearby

      belongs_to :configuration

      belongs_to :stop
      belongs_to :trip
    end
  end
end
