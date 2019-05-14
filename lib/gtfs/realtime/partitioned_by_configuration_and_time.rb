module GTFS
  class Realtime
    class PartitionedByConfigurationAndTime < Partitioned::MultiLevel
      self.abstract_class = true
      self.table_name_prefix = "gtfs_realtime_"

      #
      # Normalize a partition key value by week. We've picked
      # the beginning of the week to key on, which is Monday.
      #
      # @param [Time] time_value the time value to normalize
      # @return [Time] the value normalized
      def self.partition_normalize_key_value(time_value)
        return time_value.at_beginning_of_week
      end

      #
      # The size of the partition table, 7 days (1.week)
      #
      # @return [Integer] the size of this partition
      def self.partition_table_size
        return 1.week
      end

      #
      # Generate an enumerable that represents all the dates between
      # start_date and end_date skipping step.
      #
      # This can be used to calls that take an enumerable like create_infrastructure.
      #
      # @param [Date] start_date the first date to generate the range from
      # @param [Date] end_date the last date to generate the range from
      # @param [Object] step (:default) number of values to advance (:default means use {#self.partition_table_size}).
      # @return [Enumerable] the range generated
      def self.partition_generate_range(start_date, end_date, step = :default)
        step = partition_table_size if step == :default
        current_date = partition_normalize_key_value(start_date)
        dates = []
        while current_date <= end_date
          dates << current_date
          current_date += step
        end
        return dates
      end

      partitioned do |partition|
        partition.using_classes PartitionedByConfiguration, PartitionedByWeeklyTimeField
      end

    end
  end
end
