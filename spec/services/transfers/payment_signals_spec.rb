require "rails_helper"

RSpec.describe Transfers::PaymentSignals do
  describe ".normalize_description" do
    {
      "APPLECARD GSBANK PAYMENT 100001 WEB ID: 9999999999"     => "APPLECARD GSBANK PAYMENT",
      "Online Payment 10000000001 To Auto Loan 1111 09/02"     => "Online Payment To Auto Loan 1111",
      "Online Payment 10000000002 To Auto Loan 1111 04/02"     => "Online Payment To Auto Loan 1111",
      "CHASE CREDIT CRD AUTOPAY 0000XXXXX123456 PPD ID: 12345" => "CHASE CREDIT CRD AUTOPAY",
      "Payment to Chase card ending in 4321 08/26"             => "Payment to Chase card ending in 4321",
      "Zelle payment to Jordan Smith 10000000003"             => "Zelle payment to Jordan Smith",
      "AUTOMATIC PAYMENT - THANK"                              => "AUTOMATIC PAYMENT - THANK",
      "SQ *CAFE 0042"                                          => "SQ *CAFE 0042",
      ""                                                       => "",
      nil                                                      => ""
    }.each do |raw, stable|
      it "turns #{raw.inspect} into #{stable.inspect}" do
        expect(described_class.normalize_description(raw)).to eq(stable)
      end
    end
  end

  describe ".payment_shaped?" do
    it "accepts the Payment type, a loan-payment category, or a signature" do
      expect(described_class.payment_shaped?(build(:cash_transaction, transaction_type: "Payment"))).to be(true)
      expect(described_class.payment_shaped?(build(:cash_transaction, raw_category: "LOAN_PAYMENTS_CAR_PAYMENT"))).to be(true)
      expect(described_class.payment_shaped?(build(:cash_transaction, description: "APPLECARD GSBANK PAYMENT"))).to be(true)
    end

    it "rejects an ordinary charge" do
      expect(described_class.payment_shaped?(build(:cash_transaction, description: "Zelle payment to Jordan"))).to be(false)
    end
  end
end
