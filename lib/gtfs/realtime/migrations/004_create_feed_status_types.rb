class CreateFeedStatusTypes < ActiveRecord::Migration[5.0]
  def up
    create_table :gtfs_realtime_feed_status_types do |t|
      t.string :name
      t.string :description
      t.boolean :active
    end

    add_reference :gtfs_realtime_feeds, :feed_status_type, after: :feed_file, index: true

    [
        {name: 'Successful', description: 'Feed file can be processed', active: true},
        {name: 'Empty', description: 'Feed file was empty', active: true},
        {name: 'Errored', description: 'Feed file could not be processed', active: true},
        {name: 'Running', description: 'Feed file being processed', active: true}
    ].each do |type|
      GTFS::Realtime::FeedStatusType.create!(type)
    end

  end

  def down
    drop_table :gtfs_realtime_feed_status_types
    remove_column :gtfs_realtime_feeds, :feed_status_type_id
  end
end
