require "rails_helper"

RSpec.describe ResourcesHelper do
  def row(used, hard, resource: "requests.memory")
    ResourceUsage::QuotaRow.new(resource:, used:, hard:)
  end

  describe "#format_mi" do
    it "shows MiB below 1 GiB, and GiB to one decimal place from there" do
      expect(helper.format_mi(176)).to eq("176 MiB")
      expect(helper.format_mi(1024)).to eq("1 GiB")
      expect(helper.format_mi(5325)).to eq("5.2 GiB")
    end
  end

  describe "#quota_summary" do
    it "says how much of the limit is used, in its own units" do
      expect(helper.quota_summary(row(5325, 7168))).to eq("5.2 GiB of 7 GiB (74%)")
      expect(helper.quota_summary(row(9, 150, resource: "pods"))).to eq("9 of 150 (6%)")
    end
  end

  describe "#quota_level" do
    it "is a warning from 75%, and danger from 90%" do
      expect(helper.quota_level(row(74, 100))).to eq(:normal)
      expect(helper.quota_level(row(75, 100))).to eq(:warning)
      expect(helper.quota_level(row(90, 100))).to eq(:danger)
    end

    it "caps the percentage at 100, and copes with a zero limit" do
      expect(helper.quota_percent(row(150, 100))).to eq(100)
      expect(helper.quota_percent(row(0, 0))).to eq(0)
    end
  end
end
