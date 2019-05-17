require "spec_helper"

describe GTFS::Realtime do
  let!(:time_now)               { Time.now }
  let!(:trip1)                  { Transit_realtime::TripDescriptor.new(trip_id: 'Trip1') }
  let!(:stop_time_updates1)     { [Transit_realtime::TripUpdate::StopTimeUpdate.new(stop_id: 'Stop1A', arrival: Transit_realtime::TripUpdate::StopTimeEvent.new(time:(time_now-10.minutes).to_i)), Transit_realtime::TripUpdate::StopTimeUpdate.new(stop_id: 'Stop1B', arrival: Transit_realtime::TripUpdate::StopTimeEvent.new(time: (time_now-15.minutes).to_i))] }
  let!(:trip_update1)           { Transit_realtime::TripUpdate.new(trip: trip1, stop_time_update: stop_time_updates1) }
  let!(:feed_entity1)           { Transit_realtime::FeedEntity.new(id: 'Entity1', trip_update: trip_update1) }

  let!(:trip2)                  { Transit_realtime::TripDescriptor.new(trip_id: 'Trip2') }
  let!(:stop_time_updates2)     { [Transit_realtime::TripUpdate::StopTimeUpdate.new(stop_id: 'Stop2A', arrival: Transit_realtime::TripUpdate::StopTimeEvent.new(time: (time_now-10.minutes).to_i)), Transit_realtime::TripUpdate::StopTimeUpdate.new(stop_id: 'Stop2B', arrival: Transit_realtime::TripUpdate::StopTimeEvent.new(time: (time_now-15.minutes).to_i))] }
  let!(:trip_update2)           { Transit_realtime::TripUpdate.new(trip: trip2, stop_time_update: stop_time_updates2) }
  let! (:feed_entity2)          { Transit_realtime::FeedEntity.new(id: 'Entity2', trip_update: trip_update2) }

  let!(:feed_header)            { Transit_realtime::FeedHeader.new(timestamp: (time_now-1.hour).to_i) }
  let!(:feed_message)           { Transit_realtime::FeedMessage.new(header: feed_header, entity: [feed_entity1, feed_entity2]) }

  let!(:trip1_new)              { Transit_realtime::TripDescriptor.new(trip_id: 'Trip1New') }
  let!(:stop_time_updates1_new) { [Transit_realtime::TripUpdate::StopTimeUpdate.new(stop_id: 'Stop1ANew', arrival: Transit_realtime::TripUpdate::StopTimeEvent.new(time: time_now.to_i)), Transit_realtime::TripUpdate::StopTimeUpdate.new(stop_id: 'Stop1BNew', arrival: Transit_realtime::TripUpdate::StopTimeEvent.new(time: (time_now-5.minutes).to_i))] }
  let!(:trip_update1_new)       { Transit_realtime::TripUpdate.new(trip: trip1_new, stop_time_update: stop_time_updates1_new) }
  let!(:feed_entity1_new)       { Transit_realtime::FeedEntity.new(id: 'Entity1New', trip_update: trip_update1_new) }

  let!(:trip2_new)              { Transit_realtime::TripDescriptor.new(trip_id: 'Trip2New') }
  let!(:stop_time_updates2_new) { [Transit_realtime::TripUpdate::StopTimeUpdate.new(stop_id: 'Stop2ANew', arrival: Transit_realtime::TripUpdate::StopTimeEvent.new(time: time_now.to_i)), Transit_realtime::TripUpdate::StopTimeUpdate.new(stop_id: 'Stop2BNew', arrival: Transit_realtime::TripUpdate::StopTimeEvent.new(time: (time_now-5.minutes).to_i))] }
  let!(:trip_update2_new)       { Transit_realtime::TripUpdate.new(trip: trip2_new, stop_time_update: stop_time_updates2_new) }
  let! (:feed_entity2_new)      { Transit_realtime::FeedEntity.new(id: 'Entity2New', trip_update: trip_update2_new) }

  let!(:feed_header_new)        { Transit_realtime::FeedHeader.new(timestamp: time_now.to_i) }
  let!(:feed_message_new)       { Transit_realtime::FeedMessage.new(header: feed_header_new, entity: [feed_entity1_new, feed_entity2_new]) }


  before(:all) do
    GTFS::Realtime.configure([{name: 'TEST', interval_seconds: 30, trip_updates_feed: 'TEST'}])
  end

  before(:each) do
    GTFS::Realtime.previous_feeds = nil # reset the previous feed before each test so can set up own environment for prev feed
    GTFS::Realtime::TripUpdate.delete_all
    GTFS::Realtime::StopTimeUpdate.delete_all
  end

  it "has a version number" do
    expect(GTFS::Realtime::VERSION).not_to be nil
  end

  it "loads data with the gtfs gem" do
    skip("static feeds not loaded currently.")
    expect(GTFS::Source).to receive(:build).with(STATIC_FEED_URL)

    GTFS::Realtime.configure do |config|
      config.static_feed = STATIC_FEED_URL
    end
  end

  it "loads static GTFS data into a database" do
    skip("static feeds not loaded currently.")
    expect(GTFS::Realtime::Route).to receive(:bulk_insert)

    GTFS::Realtime.configure do |config|
      config.static_feed = STATIC_FEED_URL
    end
  end

  it 'if no previous feed load all' do

    allow(GTFS::Realtime).to receive(:get_feed) { |path| path.nil? ? [] : feed_message}
    GTFS::Realtime.refresh_realtime_feed!('TEST')

    expect(GTFS::Realtime::TripUpdate.count).to eq(2)
    expect(GTFS::Realtime::StopTimeUpdate.count).to eq(4)

  end


  it 'previous feed not in same partition as current feed' do
    feed_header.timestamp = (time_now - 1.month).to_i # set new feed to be greater > 1 week than prev feed so not in same partition
    feed_message_new.entity << feed_entity1 # make sure there is the same trip update in both feeds

    allow(GTFS::Realtime).to receive(:get_feed) { |path| path.nil? ? [] : feed_message}
    GTFS::Realtime.refresh_realtime_feed!('TEST')

    allow(GTFS::Realtime).to receive(:get_feed) { |path| path.nil? ? [] : feed_message_new}
    GTFS::Realtime.refresh_realtime_feed!('TEST')

    expect(GTFS::Realtime::TripUpdate.from_partition(GTFS::Realtime::Configuration.first.id, (time_now - 1.month).at_beginning_of_week).count).to eq(2)
    expect(GTFS::Realtime::TripUpdate.from_partition(GTFS::Realtime::Configuration.first.id, time_now.at_beginning_of_week).count).to eq(3)
    expect(GTFS::Realtime::TripUpdate.from_partition(GTFS::Realtime::Configuration.first.id, (time_now - 1.month).at_beginning_of_week)).to include(GTFS::Realtime::TripUpdate.find_by(id: feed_entity1.id))
    expect(GTFS::Realtime::TripUpdate.from_partition(GTFS::Realtime::Configuration.first.id, (time_now - 1.month).at_beginning_of_week)).to include(GTFS::Realtime::TripUpdate.find_by(id: feed_entity1.id))

  end

  it 'adds new trip updates' do
    allow(GTFS::Realtime).to receive(:get_feed).exactly(4).times { |path| path.nil? ? [] : feed_message}
    GTFS::Realtime.refresh_realtime_feed!('TEST')


    allow(GTFS::Realtime).to receive(:get_feed) { |path| path.nil? ? [] : feed_message_new}
    GTFS::Realtime.refresh_realtime_feed!('TEST')

    expect(GTFS::Realtime::TripUpdate.pluck(:id)).to eq([feed_entity1.id, feed_entity2.id, feed_entity1_new.id, feed_entity2_new.id])
  end

  it 'updates end time of same trip updates' do
    feed_message_new.entity << feed_entity1 # make sure there is the same trip update in both feeds

    allow(GTFS::Realtime).to receive(:get_feed) { |path| path.nil? ? [] : feed_message}
    GTFS::Realtime.refresh_realtime_feed!('TEST')

    expect(GTFS::Realtime::TripUpdate.find_by(id: feed_entity1.id).feed_timestamp.to_i).to eq(feed_header.timestamp)

    allow(GTFS::Realtime).to receive(:get_feed) { |path| path.nil? ? [] : feed_message_new}
    GTFS::Realtime.refresh_realtime_feed!('TEST')
    expect(GTFS::Realtime::TripUpdate.find_by(id: feed_entity1.id).feed_timestamp.to_i).to eq(feed_header_new.timestamp)
  end

  it 'enters two rows if trip update is not in a feed then added back' do


    allow(GTFS::Realtime).to receive(:get_feed) { |path| path.nil? ? [] : feed_message}
    GTFS::Realtime.refresh_realtime_feed!('TEST')
    expect(GTFS::Realtime::TripUpdate.count).to eq(2)

    allow(GTFS::Realtime).to receive(:get_feed) { |path| path.nil? ? [] : feed_message_new}
    GTFS::Realtime.refresh_realtime_feed!('TEST')
    expect(GTFS::Realtime::TripUpdate.count).to eq(4)

    allow(GTFS::Realtime).to receive(:get_feed) { |path| path.nil? ? [] : feed_message}
    GTFS::Realtime.refresh_realtime_feed!('TEST')
    expect(GTFS::Realtime::TripUpdate.count).to eq(6)

  end

end
