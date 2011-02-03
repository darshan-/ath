require 'aws/s3'
require './secret.rb'

class NilClass
  def value()   self end
  def key()     self end
  def next()    self end
  def [](*args) self end
end

class S3Storage
  def initialize()
    AWS::S3::Base.establish_connection!(:access_key_id     => Secret::ACCESS_KEY_ID,
                                        :secret_access_key => Secret::SECRET_ACCESS_KEY)
  end

  def get_strings(lang)
    AWS::S3::Bucket.find('ath-bi-strings').objects(:prefix => lang).last.value
  end

  def put_strings(lang, strings_xml)
    o = AWS::S3::Bucket.find('ath-bi-strings').new_object()
    o.key = AWS::S3::Bucket.find('ath-bi-strings').objects(:prefix => lang).last.key.next || lang << '000001'
    o.value = strings_xml
    o.store
  end
end
