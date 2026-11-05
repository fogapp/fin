ENV["GIT_SHA"] ||= begin
  revision_file = Rails.root.join("REVISION")
  if revision_file.exist?
    revision_file.read.strip
  else
    `git -C #{Rails.root.to_s.shellescape} rev-parse HEAD 2>/dev/null`.strip.presence
  end
rescue
  nil
end
