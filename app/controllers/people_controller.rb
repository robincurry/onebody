class PeopleController < ApplicationController

  #caches_action :show, :for => 1.hour, :cache_path => Proc.new { |c| "people/#{c.params[:id]}_for_#{Person.logged_in.id}" }
  #cache_sweeper :person_sweeper, :family_sweeper, :only => %w(create update destroy import)

  def index
    respond_to do |format|
      format.html { redirect_to @logged_in }
      if can_export?
        @people = Person.paginate(:order => 'last_name, first_name, suffix', :page => params[:page], :per_page => params[:per_page] || 50)
        format.xml { render :xml  => @people.to_xml(:read_attribute => true, :except => %w(feed_code encrypted_password salt api_key site_id), :include => [:groups, :family]) }
        format.csv { render :text => @people.to_csv(:read_attribute => true, :except => %w(feed_code encrypted_password salt api_key site_id), :include => params[:no_family] ? nil : [:family]) }
      end
    end
  end
  
  def show
    if params[:legacy_id]
      @person = Person.find_by_legacy_id(params[:id], :include => :family)
    else
      @person = Person.find_by_id(params[:id], :include => :family)
    end
    if @person and @logged_in.can_see?(@person)
      @family = @person.family
      @family_people = @person.family.visible_people
      @me = (@logged_in == @person)
      @show_map = Setting.get(:services, :yahoo) and @person.family.mapable? and @person.share_address_with(@logged_in)
      if params[:simple]
        if @logged_in.full_access?
          if params[:photo]
            render :action => 'show_simple_photo', :layout => false
          else
            render :action => 'show_simple', :layout => false
          end
        else
          render :text => '', :status => 404
        end
      elsif params[:services]
        render :action => 'services'
      elsif not @logged_in.full_access? and not @me
        render :action => 'show_limited'
      else
        respond_to do |format|
          format.html
          format.xml { render :xml => @person.to_xml(:read_attribute => true) } if can_export?
        end
      end
    else
      render :text => 'Person not found.', :status => 404, :layout => true
    end
  end
  
  def new
    if Site.current.max_people.nil? or Person.count < Site.current.max_people
      if @logged_in.admin?(:edit_profiles)
        @family = Family.find(params[:family_id])
        defaults = {:can_sign_in => true, :visible_to_everyone => true, :visible_on_printed_directory => true, :full_access => true}
        @person = Person.new(defaults.merge(:family_id => @family.id).merge(:last_name => @family.last_name))
      else
        render :text => 'You are not authorized to create a person.', :layout => true, :status => 401
      end
    else
      render :text => 'No people can be added at this time. Sorry.', :layout => true, :status => 500
    end
  end
  
  def create
    raise 'no more groups can be created' unless Site.current.max_people.nil? or Person.count < Site.current.max_people
    if @logged_in.admin?(:edit_profiles)
      @person = Person.new(params[:person])
      respond_to do |format|
        if @person.save
          format.html { redirect_to @person.family }
          format.xml  { render :xml => @person, :status => :created, :location => @person }
        else
          format.html { render :action => "new" }
          format.xml  { render :xml => @person.errors, :status => :unprocessable_entity }
        end
      end
    else
      render :text => 'You are not authorized to create a person.', :layout => true, :status => 401
    end
  end

  def edit
    @person ||= Person.find(params[:id])
    if @logged_in.can_edit?(@person)
      @family = @person.family
      @service_categories = Person.service_categories
    else
      render :text => 'You are not authorized to edit this person.', :layout => true, :status => 401
    end
  end
  
  def update
    @person = Person.find(params[:id])
    if @logged_in.can_edit?(@person)
      if updated = @person.update_from_params(params)
        respond_to do |format|
          format.html do
            flash[:notice] = 'Changes submitted (some changes may require staff review).'
            redirect_to edit_person_path(@person, :anchor => params[:anchor])
          end
          format.xml { render :xml => @person.to_xml } if can_export?
        end
      else
        edit; render :action => 'edit'
      end
    else
      render :text => 'You are not authorized to edit this person.', :layout => true, :status => 401
    end
  end
  
  def destroy
    if @logged_in.admin?(:edit_profiles)
      @person = Person.find(params[:id])
      unless me?
        @person.destroy
        redirect_to @person.family
      else
        render :text => 'You cannot delete yourself.', :status => 500
      end
    else
     render :text => 'You are not authorized to delete this person.', :status => 401
    end
  end
  
  def import
    if @logged_in.admin?(:import_data) and Site.current.import_export_enabled?
      if request.get?
        @column_names  = Person.columns.map { |c| c.name }
        @column_names += Family.columns.map { |c| "family_#{c.name}" }
        @column_names.reject! { |c| c =~ /site_id/ }
      elsif request.post?
        @records = Person.queue_import_from_csv_file(params[:file].read, params[:match_by_name])
        render :action => 'import_queue'
      elsif request.put?
        Person.import_data(params)
        render :text => 'Import successful.', :layout => true
      end
    else
      render :text => 'You are not authorized to import data.', :layout => true, :status => 401
    end
  end
  
  def hashify
    if @logged_in.admin?(:import_data) and Site.current.import_export_enabled?
      if Person.connection.adapter_name == 'MySQL'
        hashes = Person.hashify(:legacy_ids => params[:legacy_id].to_s.split(','), :attributes => params[:attrs].split(','), :debug => params[:debug])
        render :xml => hashes
      else
        render :text => 'This method is only available in a MySQL environment.', :status => 500
      end
    else
      render :text => 'You are not authorized to import data.', :layout => true, :status => 401
    end
  end
  
  def batch
    if @logged_in.admin?(:import_data) and Site.current.import_export_enabled?
      records = Hash.from_xml(request.body.read)['records']
      statuses = records.map do |record|
        person = Person.find_by_legacy_id(record['legacy_id']) || Person.new
        person.family_id = Family.connection.select_value("select id from families where legacy_id = #{record['legacy_family_id'].to_i} and site_id = #{Site.current.id}")
        record.each do |key, value|
          value = nil if value == ''
          person.write_attribute(key, value)
        end
        if person.save
          {:status => 'saved', :legacy_id => person.legacy_id, :id => person.id}
        else
          {:status => 'error', :legacy_id => record['legacy_id'], :error => person.errors.full_messages.join('; ')}
        end
      end
      render :xml => statuses
    else
      render :text => 'You are not authorized to import data.', :layout => true, :status => 401
    end
  end
  
  def schema
    render :xml => Person.columns.map { |c| {:name => c.name, :type => c.type} }
  end

end
