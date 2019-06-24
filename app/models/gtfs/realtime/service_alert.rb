module GTFS
  class Realtime
    class ServiceAlert < GTFS::Realtime::PartitionedByConfigurationAndTime

      belongs_to :configuration

      partitioned do |partition|
        partition.index :stop_id
      end

    end
  end
end
