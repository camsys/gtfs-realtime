module GTFS
  class Realtime
    class TripUpdate < GTFS::Realtime::PartitionedByRouteId
      belongs_to :trip
      belongs_to :route

      validates_uniqueness_of :id

      partitioned do |partition|
        partition.index :id, :unique => true
        partition.index :trip_id
        partition.index [:trip_id, :route_id], :unique => true
      end
    end
  end
end
