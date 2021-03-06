class InviteController < ApplicationController
  before_filter :authenticate_user!

  def index
    load_contacts
    #@users = Authentication.existing_users(@contacts)
    respond_to do |format|
      format.html { render layout: (request.xhr? ? false : true) }
      format.js
    end
  end

  def state
    redirect_to invite_url unless request.xhr?

    if current_user.twitter_state == 'finished' || current_user.linkedin_state == 'finished' || current_user.facebook_state == 'finished'
      load_contacts
    else
      @authentication_contacts = []
    end
    #render json: {twitter_state: current_user.twitter_state,
    # linkedin_state: current_user.linkedin_state}
  end

  private

  def load_contacts
    @authentication_contacts = current_user.authentication_contacts.includes(:contact => :user).search(params)
  end
end
