class EmailMessage
  include ActiveModel::Validations
  include ActiveModel::Conversion
  include ActiveModel::Validations::Callbacks
  extend ActiveModel::Naming

  # Attributes
  attr_accessor :view_context, :inviter, :email, :invited,
                :tag_names, :tag1, :tag2, :tag3

  # Callbacks
  before_validation :set_tag_names

  # Validations
  validates_presence_of :inviter, :email
  validate :validate_at_least_one_tag
  validate :validate_user_is_not_already_registered

  def initialize(attributes = {})
    attributes.each do |name, value|
      send("#{name}=", value)
    end
  end

  def save
    if valid?
      # assign tag names to the user, we are using them in the invitation email
      invited = User.invite!({email: email, tag_names: tag_names}, inviter)
      inviter.add_tags(invited, TagCleaner.clean(tag_names.join(',')), skip_email: true)
      inviter.add_following(invited)
      true
    else
      false
    end
  end

  def persisted?
    false
  end

  private
  def set_tag_names
    self.tag_names = [tag1.presence, tag2.presence, tag3.presence].compact
  end

  def validate_at_least_one_tag
    errors[:tag1] << 'add at least one tag' if tag_names.blank?
  end

  def validate_user_is_not_already_registered
    user = User.find_by_email(email)
    if user && user.active?
      errors[:email] << "#{view_context.link_to(user.name, view_context.me_user_path(user.username))} is registered"
    end
  end
end
