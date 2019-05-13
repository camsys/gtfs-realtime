require "gtfs/realtime/nearby"

module GTFS
  class Realtime
    class VehiclePosition < GTFS::Realtime::PartitionedByWeeklyTimeField
      include GTFS::Realtime::Nearby

      def self.partition_time_field
        return :timestamp
      end

      partitioned do |partition|
        partition.index :trip_id
        partition.index :stop_id
      end

      belongs_to :stop
      belongs_to :trip
    end
  end
end
