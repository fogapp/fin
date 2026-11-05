# typed: false
# frozen_string_literal: true

require "rails_helper"

# Fog creates the database's extensions as its own admin role; the restore
# runs as the app's role, which can neither drop nor recreate them. A dump
# restored with its extension entries fails on the very first --clean.
RSpec.describe FogBackup::Restorer do
  it "restores everything in the dump except its extensions" do
    Dir.mktmpdir do |dir|
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      dump = Pathname(dir).join("primary.dump")
      args = [ "pg_dump", "-Fc", "-f", dump.to_s, "-h", config[:host].to_s, "-p", (config[:port] || 5432).to_s ]
      args += [ "-U", config[:username].to_s ] if config[:username]
      result = FogBackup::Shell.run(args + [ config[:database].to_s ], env: { "PGPASSWORD" => config[:password].to_s })
      expect(result.stderr).to eq("")

      full = FogBackup::Shell.run([ "pg_restore", "--list", dump.to_s ]).stdout
      expect(full).to match(/ EXTENSION - /)

      toc = described_class.new.send(:restorable_toc, dump).read
      expect(toc).not_to match(/ EXTENSION /)
      expect(toc).to match(/ TABLE public accounts /)
      expect(toc.lines.count).to eq(full.lines.count - full.lines.count { |l| l.match?(described_class::EXTENSION_ENTRY) })
    end
  end

  # A table newer than the artifact, with a foreign key into a table the
  # dump restores, blocked pg_restore --clean on every boot. The restore now
  # empties Fin's own tables first. Proven in a scratch schema: the
  # transaction the spec runs in rolls the DDL back.
  it "drops every table Fin owns, cascading through foreign keys, before restoring" do
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL)
      CREATE SCHEMA restorer_spec;
      CREATE TABLE restorer_spec.households (id bigint PRIMARY KEY);
      CREATE TABLE restorer_spec.newer (id bigint PRIMARY KEY, household_id bigint REFERENCES restorer_spec.households (id));
    SQL

    described_class.new.send(:drop_own_tables, schema: "restorer_spec")

    left = connection.select_values("SELECT tablename FROM pg_tables WHERE schemaname = 'restorer_spec'")
    expect(left).to be_empty
    expect(connection.table_exists?("households")).to be(true)
  end

  # Every format this app ever wrote restores: each file component is read
  # from the path its manifest entry names and unpacked by its extension.
  describe "file components" do
    around { |example| Dir.mktmpdir { |dir| @dir = Pathname(dir); example.run } }

    def restore(format)
      artifact = build_fog_artifact(@dir.join("build"), format: format, files: { "note.txt" => format })
      manifest = FogBackup::Preflight.check(artifact_path: artifact).manifest
      work = @dir.join("work")
      work.mkpath
      system("tar", "-xf", artifact.to_s, "-C", work.to_s, exception: true)
      storage = @dir.join("storage")
      described_class.new.send(:restore_files, work, manifest, storage: storage)
      storage
    end

    it "unpacks a fog-backup/2 artifact's plain tar" do
      expect(restore("fog-backup/2").join("note.txt").read).to eq("fog-backup/2")
    end

    it "unpacks a fog-backup/1 artifact's zstd tar" do
      expect(restore("fog-backup/1").join("note.txt").read).to eq("fog-backup/1")
    end

    it "refuses a component path that leaves the artifact" do
      expect { described_class.new.send(:component_file, @dir, { "name" => "storage", "path" => "../escape.tar" }) }
        .to raise_error(described_class::Error, /outside the artifact/)
    end
  end
end
