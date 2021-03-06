class SessionsController < ApplicationController
  skip_before_filter :authenticate_user
  before_filter :check_ssl, :except => %w(destroy)
  
  def show
    redirect_to new_session_path
  end
  
  # sign in form
  def new
    if Person.count > 0
      generate_encryption_key
    else
      @show_help = local_request?
      render :action => 'no_users'
    end
  end
  
  # sign in
  def create
    if Rails.env == 'test' and params[:password]
      password = params[:password]
    else
      password = decrypt_password(params[:encrypted_password])
    end
    if person = Person.authenticate(params[:email], password)
      reset_session
      unless person.can_sign_in?
        redirect_to page_for_public_path('system/unauthorized')
        return
      end
      session[:logged_in_id] = person.id
      session[:logged_in_name] = person.first_name + ' ' + person.last_name
      session[:ip_address] = request.remote_ip
      flash[:notice] = "Welcome, #{person.first_name}."
      if params[:from].to_s.any?
        redirect_to 'http://' + request.host + ([80, 443].include?(request.port) ? '' : ":#{request.port}") + params[:from]
      else
        redirect_to person
      end
    elsif person == nil
      if family = Family.find_by_email(params[:email])
        flash[:warning] = 'That email address was found, but you must verify it before you can sign in.'
        redirect_to new_account_path(:email => params[:email])
      else
        flash[:warning] = 'That email address cannot be found in our system. Please try another email.'
        new; render :action => 'new'
        flash.clear
      end
    else
      if p = Person.find_by_email(params[:email]) and p.encrypted_password.nil?
        flash[:warning] = "Your account hasn't been activated yet. <a href=\"/pages/help\">Click here</a> to get started."
      else
        flash[:warning] = "The password you entered doesn't match our records. Please try again."
      end
      new; render :action => 'new'
      flash.clear
    end
  end
  
  # sign out
  def destroy
    #session[:logged_in_id] = nil
    reset_session
    redirect_to new_session_path
  end
  
  private
    def check_ssl
      unless request.ssl? or RAILS_ENV != 'production' or !Setting.get(:features, :ssl)
        redirect_to :protocol => 'https://', :from => params[:from]
        return
      end
    end
    
    def session_salt
      unless session[:salt] and session[:salt_generated] > 5.minutes.ago
        session[:salt] = (0..25).inject('') { |r, i| r << rand(93) + 33 }
        session[:salt_generated] = Time.now
      end
      session[:salt]
    end
  
end
