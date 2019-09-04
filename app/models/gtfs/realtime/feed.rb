module GTFS
  class Realtime
    class Feed < GTFS::Realtime::PartitionedByConfigurationAndTime
      belongs_to :configuration
      belongs_to :feed_status_type

      mount_uploader :feed_file, FeedFileUploader

      validates :feed_file,               :presence => true

      partitioned do |partition|

      end

    end
  end
end