module GTFS
  class Realtime
    class FeedStatusType < GTFS::Realtime::Model
      has_many :feeds

    end
  end
end