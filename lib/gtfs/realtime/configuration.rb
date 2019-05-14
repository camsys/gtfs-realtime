module GTFS
  class Realtime
    class Configuration < GTFS::Realtime::Model

      after_create :create_partitions

      protected

      def create_partitions
        GTFS::Realtime::TripUpdate.create_new_partition_tables([self.id])
        GTFS::Realtime::TripUpdate.create_new_partition_tables(GTFS::Realtime::TripUpdate.partition_generate_range(Date.parse('2019-01-01'), Date.parse('2019-12-31')).map{|datetime| [self.id, datetime]})
        GTFS::Realtime::StopTimeUpdate.create_new_partition_tables([self.id])
        GTFS::Realtime::StopTimeUpdate.create_new_partition_tables(GTFS::Realtime::StopTimeUpdate.partition_generate_range(Date.parse('2019-01-01'), Date.parse('2019-12-31')).map{|datetime| [self.id, datetime]})
        GTFS::Realtime::VehiclePosition.create_new_partition_tables([self.id])
        GTFS::Realtime::VehiclePosition.create_new_partition_tables(GTFS::Realtime::VehiclePosition.partition_generate_range(Date.parse('2019-01-01'), Date.parse('2019-12-31')).map{|datetime| [self.id, datetime]})
        GTFS::Realtime::ServiceAlert.create_new_partition_tables([self.id])
        GTFS::Realtime::ServiceAlert.create_new_partition_tables(GTFS::Realtime::ServiceAlert.partition_generate_range(Date.parse('2019-01-01'), Date.parse('2019-12-31')).map{|datetime| [self.id, datetime]})
      end

    end
  end
end
