class InvitationMessage
  include ActiveModel::Validations
  include ActiveModel::Conversion
  include ActiveModel::Validations::Callbacks
  extend ActiveModel::Naming
  include Rails.application.routes.url_helpers

  # Attributes
  attr_accessor :view_context, :inviter, :uid, :provider, :screen_name,
                :tag_names, :tag1, :tag2, :tag3

  # Callbacks
  before_validation :set_tag_names

  # Validations
  validates :inviter, presence: true
  validates :uid, presence: true
  validates :provider, inclusion: {in: ['twitter', 'facebook', 'linkedin']}
  validate :validate_at_least_one_tag

  def initialize(attributes = {})
    attributes.each do |name, value|
      send("#{name}=", value)
    end
  end

  def save
    if valid?
      invite_contact
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

  def invite_contact
    User.transaction do
      invited = create_user
      send_invitation_message(invited)
      contact.update_attributes({invited: true, user_id: invited.id}) if contact
    end
  end

  def create_user
    fake_email = "#{provider}_#{contact.uid}".downcase  #devise saves email with downcase
    user = User.find_by_email(fake_email)
    unless user
      avatar = get_avatar_url(contact)
      user = User.new(email: fake_email,
                      full_name: contact.name,
                      remote_avatar_url: avatar)
      user.invited_by = inviter
      user.skip_invitation = true
      # devise invitable makes uid downcase - REFACTOR THIS
      #def user.downcase_keys
      #  nil
      #end
      user.invite!
    end
    inviter.add_tags(user, TagCleaner.clean(tag_names.join(',')), skip_email: true)
    inviter.add_following(user)
    user
  end

  def send_invitation_message(user)
    url = view_context.accept_invitation_url(user, :invitation_token => user.invitation_token)
    case provider
    when 'twitter'
      message = "I've tagged you with \"#{tag_names.first}\" on GiveBrand! Start building your profile here: #{url}"
      client.direct_message_create(screen_name, message)
    when 'linkedin'
      message = "I've tagged you with \"#{tag_names.join(', ')}\" on GiveBrand! Start building your profile here: #{url}"
      client.send_message("I invite you to claim your brand at GiveBrand!", message, [contact.uid])
    end
  end

  def client
    @client ||= GiveBrand::Client.new(inviter, provider)
  end

  def contact
    @contact ||= inviter.contacts.where(['provider = ?', provider]).find_by_uid!(uid)
  end

  def get_avatar_url(contact)
    if provider == 'twitter'
      # replace the last '_normal' with ''
      contact.avatar.to_s.reverse.sub('_normal'.reverse, '').reverse
    end
  end
end
