module GTFS
  class Realtime
    class PartitionedByConfiguration < Partitioned::PartitionedBase
      self.abstract_class = true
      self.table_name_prefix = "gtfs_realtime_"

      def self.partition_foreign_key
        return :configuration_id
      end

      partitioned do |partition|
        partition.foreign_key lambda {|model, foreign_key_value|
          return Partitioned::PartitionedBase::Configurator::Data::ForeignKey.new(model.partition_foreign_key,
                                                                                  'gtfs_realtime_configurations',
                                                                                  :id)
        }

        partition.on lambda {|model| return model.partition_foreign_key }

      end

    end
  end
end
