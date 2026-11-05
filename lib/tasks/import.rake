namespace :import do
  desc "Import a CSV (auto-detects transactions vs holdings). Usage: rake import:csv FILE=path/to.csv [BROKER=Parametric]"
  task csv: :environment do
    file = ENV["FILE"] or abort "FILE=path/to.csv is required"
    broker = ENV["BROKER"]

    record = CsvImport.create!(source_filename: File.basename(file), broker_name: broker, status: :pending)
    result = Importers::Dispatcher.new(source: file, default_broker: broker, csv_import: record).call

    puts "Kind: #{record.kind}"
    puts "Imported: #{result.imported}"
    puts "Skipped (already present): #{result.skipped}"
    if result.errors.any?
      puts "Errors: #{result.errors.size}"
      result.errors.first(5).each { |e| puts "  - #{e[:error]}" }
    end
  end
end
