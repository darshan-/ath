require 'aws/s3'
require './secret.rb'
require './xml_helper.rb'
require './nicer_nil.rb'

class S3Storage
  def initialize()
    AWS::S3::Base.establish_connection!(:access_key_id     => Secret::ACCESS_KEY_ID,
                                        :secret_access_key => Secret::SECRET_ACCESS_KEY)
  end

  def get_langs()
    langs = []

    AWS::S3::Bucket.find('ath-bi-strings').objects().each do |o|
      langs << o.key.split('_').first
    end

    langs.uniq - ['en']
  end

  def get_strings(lang)
    XMLHelper.xml_to_str(AWS::S3::Bucket.find('ath-bi-strings').objects(:prefix => lang + '_').last.value)
  end

  def put_strings(lang, strings)
    xml_str = XMLHelper.str_to_xml(strings)

    o = AWS::S3::Bucket.find('ath-bi-strings').new_object()
    o.key = AWS::S3::Bucket.find('ath-bi-strings').objects(:prefix => lang + '_').last.key.next || lang + '_000001'
    o.value = xml_str
    o.store
  end
end
