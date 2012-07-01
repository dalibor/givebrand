class User < ActiveRecord::Base

  include ApplicationHelper
  include ActionView::Helpers::AssetTagHelper

  # Include default devise modules. Others available are:
  # :token_authenticatable, :encryptable, :confirmable, :lockable, :timeoutable and :omniauthable
  devise :invitable, :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable #, :omniauthable

  # Additions
  mount_uploader :avatar, AvatarUploader

  # Attributes
  attr_accessible :email, :password, :password_confirmation, :remember_me,
    :username, :full_name, :short_bio, :location, :twitter_handle,
    :personal_url, :avatar, :avatar_cache, :tag_names

  attr_accessor :tag_names

  # Associations
  has_many :authentications, dependent: :destroy
  has_many :user_tags, dependent: :destroy
  has_many :tags, through: :user_tags, :order => "name asc"
  has_many :activity_items, order: 'created_at desc', dependent: :destroy
  has_many :incoming_activities, :foreign_key => :target_id,
                                 :class_name => 'ActivityItem',
                                 :order => 'created_at DESC'
  has_many :votes, :foreign_key => :voter_id, :dependent => :destroy
  has_many :voted_users, :through => :votes, :uniq => true
  has_many :voters, :through => :user_tags, :uniq => true
  has_many :twitter_contacts, :dependent => :destroy
  has_many :incoming_endorsements, :through => :user_tags, :source => :endorsements
  has_many :outgoing_endorsements, :class_name => 'Endorsement', :foreign_key => :endorsed_by_id, :dependent => :destroy

  # Friendships
  has_many :friendships, :foreign_key => :follower_id, :dependent => :destroy
  has_many :reverse_friendships, :foreign_key => :followed_id,
              :class_name => 'Friendship', :dependent => :destroy
  has_many :followings, :through => :friendships, :source => :followed
  has_many :followers, :through => :reverse_friendships, :source => :follower

  # Validations
  validates :username, :presence => true,
               :format => { with: /^\w+$/,
                            message: "only use letters, numbers and '_'" },
               :length => { minimum: 3 },
               :uniqueness => true,
               :exclusion => { :in => %w(admin superuser test givebrand) }
  validates :personal_url, :url_format => true, :allow_blank => true
  validate :username_is_not_a_route
  validates :short_bio, :length => {:maximum => 200}

  # Callbacks
  before_validation :add_protocol_to_personal_url
  before_validation :clean_twitter_username

  # Scopes
  scope :none, where("1 = 0")
  scope :active, where('invitation_token IS NULL')
  scope :inactive, where('invitation_token IS NOT NULL')
  scope :order_by_invitation_time, order("invitation_sent_at desc")
  scope :order_by_name, order('full_name ASC, username ASC')

  def profile_complete_percent
    empty_count = 0
    empty_count += 1 if job_title.blank?
    empty_count += 1 if location.blank?
    empty_count += 1 if twitter_handle.blank?
    empty_count += 1 if full_name.blank?
    empty_count += 1 if personal_url.blank?
    empty_count += 1 unless user_tags.any?
    empty_count += 1 unless avatar.present?
    percentage = ((9 - empty_count) * 100) / 9
    [0,percentage,100].sort[1]
  end

  def short_name
    name ? name.to_s.split(' ').first : username
  end

  def name
    read_attribute(:full_name).presence || username
  end

  def friends
    voted_users & voters
  end

  def active?
    invitation_token.blank?
  end

  def voted_count
    voted_users.count(:distinct => true)
  end

  def voters_count
    voters.count(:distinct => true)
  end

  def pending
    User.invited_by(self).inactive
  end

  def top_tags(limit)
    user_tags.joins(:votes).
      select('user_tags.id, user_tags.tag_id, COUNT(*) AS total_votes').
      group("votes.voteable_id, user_tags.id, user_tags.tag_id").
      limit(limit).order('total_votes DESC').
      includes(:tag).
      map { |user_tag| user_tag.tag }
  end

  def interacted_by(other_user)
    user_tags.joins(:votes).where('votes.voter_id = ?', other_user.id).exists?
  end

  def add_tags(user, tag_names, options = {})
    UserTag.add_tags(self, user, tag_names, options)
  end

  def add_following(invited)
    followings << invited unless followings.exists?(invited)
  end

  def add_vote(user_tag, log_vote_activity = true)
    if self != user_tag.user
      vote = vote_exclusively_for(user_tag)
      # Vote.create!(:vote => direction, :voteable => voteable, :voter => self)
      if log_vote_activity
        activity_items.create(item: vote, target: user_tag.user)
      end
    else
      vote = false
    end
    vote
  end

  def remove_vote(user_tag)
    if user_tag.tagger == self && user_tag.votes.length <= 1
      user_tag.destroy
    else
      vote = user_tag.votes.for_voter(self).first
      vote ? vote.destroy : false
    end
  end
  def apply_omniauth(omniauth)
    unless omniauth['credentials'].blank?
      authentications.build(:provider => omniauth['provider'],
                            :uuid => omniauth['uid'],
                            :token => omniauth['credentials']['token'],
                            :secret => omniauth['credentials']['secret'])

    end
  end

  def outgoing_activities
    activity_items.joins(:target).
      where('users.invitation_token IS NULL').
      order('created_at DESC')
  end

  def all_activities(params = {})
    ActivityItem.paginate_by_sql(["SELECT t.* FROM
                        (
                          SELECT activity_items.* FROM activity_items
                          INNER JOIN users ON users.id = activity_items.target_id AND users.invitation_token IS NULL
                          WHERE activity_items.user_id = :id
                          UNION
                          SELECT activity_items.* FROM activity_items
                          INNER JOIN users ON users.id = activity_items.target_id AND users.invitation_token IS NULL
                          WHERE activity_items.user_id IN (:user_ids)
                          UNION
                          SELECT activity_items.* FROM activity_items
                          INNER JOIN users ON users.id = activity_items.target_id AND users.invitation_token IS NULL
                          WHERE activity_items.target_id = :id
                        ) AS t
                        ORDER BY created_at DESC", id: id, user_ids: friends.map(&:id)],
                        :page => params[:page], :per_page => params[:per_page])
  end

  def vote_exclusively_for(voteable)
    Vote.where(:voter_id => self.id, :voteable_id => voteable.id).map(&:destroy)
    Vote.create!(:vote => true, :voteable => voteable, :voter => self)
  end

  def update_twitter_oauth(token, secret)
    self.twitter_token  = token
    self.twitter_secret = secret
    self.save(validate: false)
  end

  def disconnect_from_twitter!
    twitter_contacts.destroy_all
    self.twitter_token  = nil
    self.twitter_secret = nil
    self.twitter_id     = nil
    self.save(validate: false)
  end

  def to_param
    username
  end

  # Changes error message for attribute if error already exists
  def change_error_message(field, message)
    if self.errors[field].include?('is already registered')
      self.errors[field].clear
      self.errors[field]= message
    end
  end

  def endorse(user_tag, description)
    unless user_tag.user_id == self.id
      user_tag.endorsements.create endorser: self, description: description
    end
  end

  # Class methods

  def self.search(params)
    scope = scoped
    if params[:q].present?
      scope = scope.search_by_name_or_tag(params[:q])
    else
      scope = scope.none
    end
    scope = scope.paginate(:per_page => 10, :page => params[:page])

    scope
  end

  def self.search_by_name_or_tag(q)
    includes(user_tags: :tag).
      where("UPPER(users.full_name) LIKE UPPER(:q) OR
             UPPER(users.username) LIKE UPPER(:q) OR
             UPPER(tags.name) LIKE UPPER(:q)", {:q => "%#{q}%"})
  end

  def self.find_first_by_auth_conditions(warden_conditions)
    conditions = warden_conditions.dup
    if login = conditions.delete(:email)
      where(conditions).where(["lower(username) = :value OR lower(email) = :value",
                               { :value => login.downcase }]).first
    else
      where(conditions).first
    end
  end

  def self.invited_by(user)
    where(:invited_by_id => user.id).inactive.order_by_invitation_time
  end

  private
  def email_required?
    authentications.blank?
  end

  def add_protocol_to_personal_url
    personal_url.to_s.strip!
    if personal_url.present? && personal_url !~ /http/
      self.personal_url = 'http://' + personal_url
    end
  end

  def clean_twitter_username
    twitter_handle.to_s.strip!
    if twitter_handle.present? && twitter_handle[0] == '@'
      self.twitter_handle = twitter_handle[1..-1]
    end
  end

  def username_is_not_a_route
    path = Rails.application.routes.
        recognize_path("#{username}", :method => :get) rescue nil

    if !(path && path[:controller] == 'users' &&
         path[:action] == 'show' && path[:id] == username)
      errors.add(:username, "is not available")
    end
  end
end
