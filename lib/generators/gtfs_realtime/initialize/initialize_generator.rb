module GtfsRealtime
  class InitializeGenerator < Rails::Generators::Base
    argument :config_name, type: :string
    source_root File.expand_path('../templates', __FILE__)

    def create_jobs
      (config_name == 'all' ? GTFS::Realtime::Configuration.all : GTFS::Realtime::Configuration.where(name: config_name)).each do |config|


        create_file "app/jobs/#{config.name.gsub(' ', '').underscore}_job.rb", <<-FILE
class #{config.name.gsub(' ', '').underscore.classify}Job
  def perform
    GTFS::Realtime.refresh_realtime_feed!(GTFS::Realtime::Configuration.find_by(name: '#{config.name}'), false)
  end
end
        FILE
      end
    end

    def setup_cronotab

      (config_name == 'all' ? GTFS::Realtime::Configuration.all : GTFS::Realtime::Configuration.where(name: config_name)).each do |config|

        create_file "config/cronotab_#{config.name.gsub(' ', '').underscore}.rb", <<-RUBY
require 'gtfs-realtime-new.pb.rb'
        RUBY

        append_to_file "config/cronotab_#{config.name.gsub(' ', '').underscore}.rb", <<-RUBY
Crono.perform(#{config.name.gsub(' ', '').underscore.classify}Job).every #{config.interval_seconds}.seconds
        RUBY
      end
    end
  end
end