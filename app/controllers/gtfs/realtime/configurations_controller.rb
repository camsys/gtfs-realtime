require_dependency "gtfs/realtime/application_controller"

module GTFS
  class Realtime
    class ConfigurationsController < ApplicationController
      layout "api"

      before_action :get_configuration, except: [:index]

      def index

      end

      def show

        if @config.handler.present?
          klass = @config.handler.constantize
          transit_realtime_file = klass::TRANSIT_REALTIME_FILE
        else
          klass = GTFS::Realtime::RealtimeFeedHandler
          transit_realtime_file = 'gtfs-realtime-new.pb.rb'
        end

        Object.send(:remove_const, :TransitRealtime) if Object.constants.include? :TransitRealtime
        load transit_realtime_file

        handler = klass.new(gtfs_realtime_configuration: @config)

        feed_message = handler.recreate(params)

        respond_to do |format|
          format.html {

            feed_file = Tempfile.new "tripUpdates", "#{Rails.root}/tmp", encoding: 'ascii-8bit'
            ObjectSpace.undefine_finalizer(feed_file)
            begin
              feed_file << feed_message.serialize_to_string
            rescue => ex
              Rails.logger.warn ex
            ensure
              feed_file.close
            end

            send_file feed_file.path
          }
          format.json { render json: feed_message }
        end
      end

      private

      def get_configuration
        @config = GTFS::Realtime::Configuration.find_by(id: params[:id])
      end
    end
  end
end

