module GTFS
  class Realtime
    class TripUpdate < GTFS::Realtime::PartitionedByConfigurationAndTime

      belongs_to :configuration

      partitioned do |partition|
        partition.index :trip_id
      end

    end
  end
end
