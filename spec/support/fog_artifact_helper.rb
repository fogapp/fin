# typed: false
# frozen_string_literal: true

# Builds a fog-backup artifact by hand, in either format this app restores:
# fog-backup/1 carries its storage tree as `files/storage.tar.zst`,
# fog-backup/2 as a plain `files/storage.tar`. The dump is placeholder bytes
# — preflight only hashes it — so these artifacts exercise the manifest and
# the file components, not pg_restore.
module FogArtifactHelper
  def build_fog_artifact(dir, format: FogBackup::Manifest::FORMAT, app: FogBackup::Manifest::APP,
    files: { "hello.txt" => "hello" }, storage_path: nil)
    root = Pathname(dir)
    work = root.join("work")
    work.join("db").mkpath
    work.join("files").mkpath
    tree = root.join("tree")
    tree.mkpath
    files.each { |name, contents| tree.join(name).write(contents) }

    storage_path ||= format == "fog-backup/1" ? "files/storage.tar.zst" : "files/storage.tar"
    work.join("db/primary.dump").write("placeholder dump bytes")
    tar = [ "tar" ]
    tar << "--zstd" if storage_path.end_with?(".zst")
    system(*tar, "-cf", work.join(storage_path).to_s, "-C", tree.to_s, ".", exception: true)

    components = [ [ "primary", "db/primary.dump", "db" ], [ "storage", storage_path, "files" ] ].map do |name, path, kind|
      file = work.join(path)
      FogBackup::Manifest::Component.new(name: name, path: path, kind: kind,
        bytes: file.size, sha256: Digest::SHA256.file(file.to_s).hexdigest)
    end
    manifest = FogBackup::Manifest.build(components: components).merge(format: format, app: app)
    work.join("manifest.json").write(JSON.generate(manifest))

    artifact = root.join("artifact.tar")
    system("tar", "-cf", artifact.to_s, "-C", work.to_s, "manifest.json", "db/primary.dump", storage_path, exception: true)
    artifact
  end
end

RSpec.configure { |config| config.include FogArtifactHelper }
