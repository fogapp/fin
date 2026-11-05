require "rails_helper"

RSpec.describe Office::Exporter do
  let(:client) { instance_double(Office::Client) }

  before do
    create(:office_configuration)
    allow(Office::Client).to receive(:new).and_return(client)
  end

  describe "#create" do
    it "sends the dataset as CSV and records the link to the new spreadsheet" do
      create(:cash_transaction, description: "COFFEE", amount: -4.25, transaction_date: Date.new(2026, 9, 1))
      allow(client).to receive(:create_sheet_from_csv)
        .and_return("id" => 77, "title" => "Transactions", "sheet" => "Sheet1")
      allow(client).to receive(:document_url).with(77).and_return("https://office.test/d/77")

      export = described_class.new.create(dataset: "transactions", params: {})

      expect(client).to have_received(:create_sheet_from_csv) do |title:, csv:, **|
        expect(title).to eq("Transactions")
        expect(csv.lines.first).to start_with("Date,Post date,Description")
        expect(csv).to include("2026-09-01,,COFFEE")
        expect(csv).to include("-4.25")
      end
      expect(export).to have_attributes(
        dataset: "transactions", document_id: 77, sheet_name: "Sheet1",
        url: "https://office.test/d/77", row_count: 2, column_count: 13
      )
      expect(export.last_exported_at).to be_present
      expect(export.user).to eq(Current.user)
    end

    it "stores the filters so a refresh replays the same query" do
      account = create(:account)
      allow(client).to receive_messages(create_sheet_from_csv: { "id" => 1 }, document_url: "u")

      export = described_class.new.create(
        dataset: "transactions", params: { account_id: account.id, description: "REI" }
      )

      expect(export.filter_params).to eq(account_id: account.id.to_s, description: "REI")
    end

    it "passes the configuration's default folder through to Office" do
      OfficeConfiguration.current.update!(default_folder_id: 12)
      allow(client).to receive_messages(create_sheet_from_csv: { "id" => 1 }, document_url: "u")

      described_class.new.create(dataset: "holdings", params: {})

      expect(client).to have_received(:create_sheet_from_csv).with(hash_including(folder_id: 12))
    end

    it "surfaces an Office failure as an exporter error" do
      allow(client).to receive(:create_sheet_from_csv).and_raise(Office::Client::Error, "Could not reach Office")

      expect { described_class.new.create(dataset: "holdings", params: {}) }
        .to raise_error(described_class::Error, "Could not reach Office")
      expect(OfficeSheetExport.count).to eq(0)
    end
  end

  describe "#refresh" do
    let(:export) do
      create(:office_sheet_export, dataset: "transactions", document_id: 77, sheet_name: "Sheet1",
                                   row_count: 4, column_count: 13)
    end

    it "rewrites the same document from A1 with the stored filters" do
      account = create(:account)
      create(:cash_transaction, description: "KEEP", account: account)
      create(:cash_transaction, description: "DROP")
      export.update!(filters: { account_id: account.id.to_s })
      allow(client).to receive(:write_cells).and_return("range" => "A1:M4")

      described_class.new.refresh(export)

      expect(client).to have_received(:write_cells) do |document_id:, values:, start:, sheet:|
        expect(document_id).to eq(77)
        expect(start).to eq("A1")
        expect(sheet).to eq("Sheet1")
        expect(values[1][2]).to eq("KEEP")
        expect(values.flatten).not_to include("DROP")
      end
      expect(export.reload.row_count).to eq(2)
      expect(export.last_error).to be_nil
    end

    it "pads back to the previous extent so rows that shrank away are cleared" do
      create(:cash_transaction)
      allow(client).to receive(:write_cells).and_return({})

      described_class.new.refresh(export)

      expect(client).to have_received(:write_cells) do |values:, **|
        # Two real rows now, four written before: the tail goes out as nils.
        expect(values.size).to eq(4)
        expect(values.last).to eq(Array.new(13, nil))
      end
    end

    it "keeps the failure on the row and still raises" do
      allow(client).to receive(:write_cells).and_raise(Office::Client::ToolError, "You can't edit this spreadsheet")

      expect { described_class.new.refresh(export) }
        .to raise_error(described_class::Error, "You can't edit this spreadsheet")
      expect(export.reload.last_error).to eq("You can't edit this spreadsheet")
    end
  end

  describe ".to_csv" do
    it "writes dates ISO, blanks nils, and quotes embedded separators" do
      csv = described_class.to_csv([ [ "Date", "Note", "Amount" ], [ Date.new(2026, 1, 2), nil, BigDecimal("-3.5") ],
                                    [ nil, "a, b", 0 ] ])

      expect(csv).to eq("Date,Note,Amount\n2026-01-02,,-3.5\n,\"a, b\",0\n")
    end
  end

  describe ".pad" do
    it "squares ragged rows and grows to the previous extent" do
      padded = described_class.pad([ [ 1, 2, 3 ], [ 4 ] ], height: 3, width: 4)

      expect(padded).to eq([ [ 1, 2, 3, nil ], [ 4, nil, nil, nil ], [ nil, nil, nil, nil ] ])
    end

    it "keeps the new extent when it is the larger one" do
      padded = described_class.pad([ [ 1, 2 ], [ 3, 4 ] ], height: 1, width: 1)

      expect(padded).to eq([ [ 1, 2 ], [ 3, 4 ] ])
    end
  end
end
