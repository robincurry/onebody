# == Schema Information
#
# Table name: families
#
#  id                 :integer       not null, primary key
#  legacy_id          :integer       
#  name               :string(255)   
#  last_name          :string(255)   
#  suffix             :string(25)    
#  address1           :string(255)   
#  address2           :string(255)   
#  city               :string(255)   
#  state              :string(2)     
#  zip                :string(10)    
#  home_phone         :integer       
#  email              :string(255)   
#  latitude           :float         
#  longitude          :float         
#  share_address      :boolean       default(TRUE)
#  share_mobile_phone :boolean       
#  share_work_phone   :boolean       
#  share_fax          :boolean       
#  share_email        :boolean       
#  share_birthday     :boolean       default(TRUE)
#  share_anniversary  :boolean       default(TRUE)
#  updated_at         :datetime      
#  wall_enabled       :boolean       default(TRUE)
#  visible            :boolean       default(TRUE)
#  share_activity     :boolean       default(TRUE)
#  site_id            :integer       
#  share_home_phone   :boolean       default(TRUE)
#

class Family < ActiveRecord::Base
  has_many :people, :order => 'sequence', :dependent => :destroy
  belongs_to :site
  
  acts_as_scoped_globally 'site_id', "(Site.current ? Site.current.id : 'site-not-set')"
  
  acts_as_photo "#{DB_PHOTO_PATH}/families", PHOTO_SIZES
  acts_as_logger LogItem
  
  alias_method 'photo_without_logging=', 'photo='
  def photo=(p)
    LogItem.create :model_name => 'Family', :instance_id => id, :object_changes => {'photo' => (p ? 'changed' : 'removed')}, :person => Person.logged_in
    self.photo_without_logging = p
  end
  
  share_with :mobile_phone
  share_with :address
  share_with :anniversary
  
  def address
    address1.to_s + (address2.to_s.any? ? "\n#{address2}" : '')
  end
  
  def mapable?
    address1.to_s.any? and city.to_s.any? and state.to_s.any? and zip.to_s.any?
  end
  
  def mapable_address
    "#{address1}, #{address2.to_s.any? ? address2+', ' : ''}#{city}, #{state} #{zip}".gsub(/'/, "\\'")
  end
  
  def pretty_address
    a = ''
    a << address1.to_s   if address1.to_s.any?
    a << ", #{address2}" if address2.to_s.any?
    a << ", #{city}"     if city.to_s.any?
    a << ", #{state}"    if state.to_s.any?
    a << "  #{zip}"      if zip.to_s.any?
  end
  
  def latitude
    return nil unless mapable?
    update_lat_lon unless read_attribute(:latitude) and read_attribute(:longitude)
    read_attribute :latitude
  end
  
  def longitude
    return nil unless mapable?
    update_lat_lon unless read_attribute(:latitude) and read_attribute(:longitude)
    read_attribute :longitude
  end
  
  def update_lat_lon
    return nil unless mapable? and Setting.get(:services, :yahoo).to_s.any?
    url = "http://api.local.yahoo.com/MapsService/V1/geocode?appid=#{Setting.get(:services, :yahoo)}&location=#{URI.escape(mapable_address)}"
    begin
      xml = URI(url).read
      result = REXML::Document.new(xml).elements['/ResultSet/Result']
      lat, lon = result.elements['Latitude'].text.to_f, result.elements['Longitude'].text.to_f
    rescue
      logger.error("Could not get latitude and longitude for address #{mapable_address} for family #{name}.")
    else
      update_attributes :latitude => lat, :longitude => lon
    end
  end
  
  def home_phone=(phone)
    write_attribute :home_phone, phone.to_s.digits_only
  end

  def children_without_consent
    people.select { |p| !p.consent_or_13? }
  end
  
  def visible_people
    people.find(:all).select { |p| Person.logged_in.admin?(:view_hidden_profiles) or p.visible? }
  end
end
