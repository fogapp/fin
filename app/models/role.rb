# typed: strict

# Shared membership-role vocabulary for household memberships and invite
# codes (an invite's role becomes the membership's role on acceptance).
class Role < T::Enum
  extend T::Sig

  include ApplicationEnum

  enums do
    Member = new("member")
    Admin = new("admin")
  end
end
