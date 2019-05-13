module GTFS
  class Realtime
    class PartitionedByRouteId < Partitioned::PartitionedBase
      self.abstract_class = true
      self.table_name_prefix = "gtfs_realtime_"

      def self.partition_foreign_key
        return :route_id
      end

      partitioned do |partition|
        partition.foreign_key lambda {|model, foreign_key_value|
          return Partitioned::PartitionedBase::Configurator::Data::ForeignKey.new(model.partition_foreign_key,
                                                    'gtfs_realtime_routes',
                                                    :id)
        }

        partition.on lambda {|model| return model.partition_foreign_key }

      end


    end
  end
end