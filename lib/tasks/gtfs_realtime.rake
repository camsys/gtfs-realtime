namespace :gtfs_realtime do
  desc "run migrations"
  task run_migrations: :environment do
    GTFS::Realtime.run_migrations
  end
end
