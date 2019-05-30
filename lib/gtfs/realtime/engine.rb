module GTFS
  class Realtime
    class Engine < Rails::Engine
      isolate_namespace GTFS::Realtime
      engine_name "GTFS"
    end
  end
end