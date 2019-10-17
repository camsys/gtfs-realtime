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


        feed_response = handler.recreate(params)
        feed_message = feed_response[:feed_message]

        respond_to do |format|

          if feed_message
            format.html {

              feed_file = Tempfile.new "tripUpdates", "#{Rails.root}/tmp", encoding: 'ascii-8bit'
              ObjectSpace.undefine_finalizer(feed_file)
              begin
                feed_file << feed_message.serialize_to_string
                send_file feed_file.path
              rescue => ex
                Rails.logger.warn ex
              ensure
                feed_file.close
                feed_file.unlink
              end


            }
            format.json { render json: feed_message }
          else
            format.any { render json: {errors: feed_response[:errors].join(',')}}
          end
        end
      end

      private

      def get_configuration
        @config = GTFS::Realtime::Configuration.find_by(id: params[:id])
      end
    end
  end
end

