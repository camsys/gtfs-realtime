# gtfs-realtime

[gfts-realtime](https://github.com/rofreg/gtfs-realtime) is a gem to interact with realtime transit data presented in the [GTFS Realtime format](https://developers.google.com/transit/gtfs-realtime/). It was built in order to interact with the RIPTA realtime data API for the public bus system in Providence, RI.

This gem has been forked by Cambridge Systematics and updated to archive realtime transit data rather than just getting the latest feed. It saves the data into a partitioned postgres database.

## Installation

Add to your application's Gemfile:
```ruby
gem 'bulk_data_methods', github: 'AirHelp/bulk_data_methods', branch: 'rails5'
gem 'partitioned', github: 'AirHelp/partitioned', branch: 'rails-5-1'
gem 'gtfs-realtime', path: '../gtfs-realtime'

gem 'whenever', require: false
```

Add your feeds:
```ruby
GTFS::Realtime.configure([{name: 'feed_name', trip_updates_feed: 'xxx', vehicle_positions_feed: 'xxx', service_alerts_feed: 'xxx', interval_seconds: '###'}])
```

where you pass to `configure` an array of hashes for all your feeds
* feed_name - some identifier of this feed such as "Subway", "Buses", "Elevators"
* xxx - URL of feed
* interval seconds - how often you ping the URL to pull latest feed data, in seconds

You can re-run `configure` as many times as you want to add new feeds. TODO: currently, you cannot delete feeds.

In your application, Add your whenever config to refresh the realtime feed every ### seconds and save to the database:
```ruby
GTFS::Realtime::Configuration.all.each do |config|
  every config.interval_seconds.seconds do # 1.minute 1.day 1.week 1.month 1.year is also supported
    runner "GTFS::Realtime.refresh_realtime_feed!(#{config.name})"
  end
end
```
Note: if you don't ping your feed in the same interval as you config you can't reconstruct as it happened.

## Limitations

* Assumes all feeds have a header gtfs_realtime_version of 1.0
* Partitions are not configurable. All realtime tables are partitioned by feed, and a week of data.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/camsys/gtfs-realtime. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
