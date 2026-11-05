# typed: true

class User < ApplicationRecord
  extend T::Sig

  has_one  :preference, class_name: "UserPreference", dependent: :destroy
  has_many :household_memberships, dependent: :destroy
  has_many :households, through: :household_memberships
  has_many :api_tokens,           dependent: :destroy
  has_many :webauthn_credentials, dependent: :destroy
  # Sign-ins from an OpenID provider linked to this account (fog sign-in).
  has_many :identities,           dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false }

  sig { returns(T::Boolean) }
  def passkey_enrolled?
    webauthn_credentials.exists?
  end
end
