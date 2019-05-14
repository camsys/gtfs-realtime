module GTFS
  class Realtime
    class ServiceAlert < GTFS::Realtime::PartitionedByConfigurationAndTime

      belongs_to :configuration

      belongs_to :stop

    end
  end
end
