module GTFS
  class Realtime
    class Configuration < GTFS::Realtime::Model

      after_create :create_partitions

      def to_s
        name
      end

      protected

      def create_partitions
        GTFS::Realtime::TripUpdate.create_new_partition_tables([self.id])
        GTFS::Realtime::StopTimeUpdate.create_new_partition_tables([self.id])
        GTFS::Realtime::VehiclePosition.create_new_partition_tables([self.id])
        GTFS::Realtime::ServiceAlert.create_new_partition_tables([self.id])

        GTFS::Realtime::Feed.create_new_partition_tables([self.id])
      end

    end
  end
end
