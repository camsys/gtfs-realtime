module GTFS
  class Realtime
    class TripUpdate < GTFS::Realtime::PartitionedByConfigurationAndTime

      belongs_to :configuration

      belongs_to :trip
      belongs_to :route

    end
  end
end
