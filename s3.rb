require 'aws/s3'
require './secret.rb'

class S3
  include AWS::S3

  def initialize
    Base.establish_connection!(:access_key_id     => Secret::ACCESS_KEY_ID,
                               :secret_access_key => Secret::SECRET_ACCESS_KEY)
  end
end
