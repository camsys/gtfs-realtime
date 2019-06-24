module GTFS
  class Realtime
    class StopTimeUpdate < GTFS::Realtime::PartitionedByConfigurationAndTime

      belongs_to :configuration

      belongs_to :trip_update

      partitioned do |partition|
        partition.index :trip_update_id
        partition.index :stop_id
      end

      def arrival_time
        super ? super.in_time_zone(Time.zone) : nil
      end

      def departure_time
        super ? super.in_time_zone(Time.zone) : nil
      end
    end
  end
end
