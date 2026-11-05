# typed: true

class InviteCode < ApplicationRecord
  extend T::Sig

  typed_enum :role, Role

  belongs_to :household
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :used_by,    class_name: "User", optional: true

  validates :code, presence: true, uniqueness: true

  before_validation :generate_code, on: :create

  scope :unused, -> { where(used_at: nil) }
  scope :unexpired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :usable,    -> { unused.unexpired }

  sig { returns(T::Boolean) }
  def used?
    used_at.present?
  end

  sig { returns(T::Boolean) }
  def expired?
    ea = expires_at
    !!(ea.present? && ea < Time.current)
  end

  sig { returns(T::Boolean) }
  def usable?
    !used? && !expired?
  end

  sig { params(user: User).returns(T::Boolean) }
  def consume!(user)
    update!(used_at: Time.current, used_by: user)
  end

  private

  sig { void }
  def generate_code
    return if code.present?
    loop do
      candidate = SecureRandom.urlsafe_base64(12)
      unless self.class.exists?(code: candidate)
        self.code = candidate
        break
      end
    end
  end
end
