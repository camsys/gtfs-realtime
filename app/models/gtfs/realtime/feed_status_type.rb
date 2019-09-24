#
#
# Errored - feed file could not be parsed.
# Empty - feed file can be parsed but there were no entries
# Successful - feed has been parsed. This does not mean there weren't errors in feed just that the feed file could be read. Can be set before or after iterating through entries.
# Running - Only used on trip updates while iterating through entries. Successful set after iteration.
#
#

module GTFS
  class Realtime
    class FeedStatusType < GTFS::Realtime::Model
      has_many :feeds

    end
  end
end