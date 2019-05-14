module GTFS
  class Realtime
    class PartitionedByWeeklyTimeField < Partitioned::ByWeeklyTimeField
      self.abstract_class = true
      self.table_name_prefix = "gtfs_realtime_"

      def self.partition_time_field
        return :feed_timestamp
      end

      partitioned do |partition|
      end

    end
  end
end
