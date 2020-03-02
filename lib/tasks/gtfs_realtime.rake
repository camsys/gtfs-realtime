namespace :gtfs_realtime do
  desc "run migrations"
  task run_migrations: :environment do
    GTFS::Realtime.run_migrations
  end

  task reset_all_running_feeds: :environment do
    GTFS::Realtime::Feed.where(feed_status_type_id: 4).update_all(feed_status_type_id: nil)
  end
end
