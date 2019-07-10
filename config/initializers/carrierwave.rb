CarrierWave.configure do |config|
  config.root = Rails.root.join('tmp') # adding these...
  config.cache_dir = 'carrierwave' # ...two lines

  config.fog_credentials = {
    :provider               => 'AWS',
    :aws_access_key_id      => Rails.application.config.aws_access_key,
    :aws_secret_access_key  => Rails.application.config.aws_secret_key,
    :region                 => Rails.application.config.aws_s3_region,
    :path_style            => true
  } unless Rails.env.test? # no tests depend on this right now.  Just turn off fog

  # For testing, upload files to local `tmp` folder.
  if Rails.env.test? || Rails.env.cucumber?
    config.storage = :file
    config.enable_processing = false
    config.root = "#{Rails.root}/tmp"
  else
    config.storage = :fog
  end

  config.cache_dir = "#{Rails.root}/tmp/uploads"                  # To let CarrierWave work on heroku

  config.fog_directory    = Rails.application.config.aws_s3_bucket
  config.fog_use_ssl_for_aws = false
  #config.s3_access_policy = :public_read                          # Generate http:// urls. Defaults to :authenticated_read (https://)
  #config.fog_host         = "#{ENV['S3_ASSET_URL']}/#{ENV['S3_BUCKET_NAME']}"

end
