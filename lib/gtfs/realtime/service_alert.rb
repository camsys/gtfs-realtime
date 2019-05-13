module GTFS
  class Realtime
    class ServiceAlert < GTFS::Realtime::PartitionedByWeeklyTimeField
      belongs_to :stop

      def self.partition_time_field
        return :start_time
      end

      partitioned do |partition|
        partition.index :stop_id
      end
    end
  end
end
