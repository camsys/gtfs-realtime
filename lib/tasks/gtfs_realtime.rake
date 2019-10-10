namespace :gtfs_realtime do
  desc "run migrations"
  task run_migrations: :environment do
    GTFS::Realtime.run_migrations
    GTFS::Realtime::Feed.where(feed_status_type_id: 4).update_all(feed_status_type_id: nil)
  end
end
