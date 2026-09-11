# frozen_string_literal: true

RSpec.describe Hiero::EntityId do
  # Every shard.realm.num identifier shares this behaviour, so it is checked once
  # against all of them rather than repeated per class.
  ID_CLASSES = [Hiero::AccountId, Hiero::ContractId, Hiero::FileId,
                Hiero::TokenId, Hiero::TopicId, Hiero::ScheduleId].freeze

  describe "parsing" do
    ID_CLASSES.each do |klass|
      it "#{klass} parses shard.realm.num" do
        id = klass.from_string("1.2.3")

        expect([id.shard, id.realm, id.num]).to eq([1, 2, 3])
        expect(id.to_s).to eq("1.2.3")
      end

      it "#{klass} parses a bare entity number as 0.0.n" do
        expect(klass.from_string("123").to_s).to eq("0.0.123")
      end

      it "#{klass} rejects malformed input" do
        ["", "1.2", "1.2.3.4", "a.b.c", "-1.0.0"].each do |bad|
          expect { klass.from_string(bad) }.to raise_error(Hiero::BadEntityIdError), bad.inspect
        end
      end
    end
  end

  describe "checksums" do
    # The same entity checksums differently on each network. This is the whole
    # reason checksums exist: it turns a mainnet identifier pasted into a testnet
    # application from a transfer to the wrong entity into a loud failure.
    {
      "mainnet" => "vfmkw",
      "testnet" => "esxsf",
      "previewnet" => "ogizo"
    }.each do |network, checksum|
      it "computes #{checksum} for 0.0.123 on #{network}" do
        expect(Hiero::AccountId.from_string("0.0.123").checksum_for(network)).to eq(checksum)
      end
    end

    it "renders an identifier with its checksum" do
      expect(Hiero::AccountId.from_string("0.0.123").to_string_with_checksum(:mainnet))
        .to eq("0.0.123-vfmkw")
    end

    it "keeps a checksum it was parsed with" do
      expect(Hiero::AccountId.from_string("0.0.123-vfmkw").checksum).to eq("vfmkw")
    end

    it "leaves the checksum nil when none was given" do
      expect(Hiero::AccountId.from_string("0.0.123").checksum).to be_nil
    end

    it "accepts a matching checksum" do
      expect(Hiero::AccountId.from_string("0.0.123-vfmkw").validate_checksum!(:mainnet))
        .to be_a(Hiero::AccountId)
    end

    it "rejects an identifier used against the wrong network" do
      expect { Hiero::AccountId.from_string("0.0.123-vfmkw").validate_checksum!(:testnet) }
        .to raise_error(Hiero::BadEntityIdError, /different network/)
    end

    it "says nothing when there is no checksum to check" do
      expect(Hiero::AccountId.from_string("0.0.123").validate_checksum!(:testnet))
        .to be_a(Hiero::AccountId)
    end

    it "offers a predicate form" do
      id = Hiero::AccountId.from_string("0.0.123-vfmkw")

      expect(id.valid_checksum?(:mainnet)).to be(true)
      expect(id.valid_checksum?(:testnet)).to be(false)
    end

    it "needs a ledger" do
      expect { Hiero::AccountId.from_string("0.0.123").checksum_for(nil) }
        .to raise_error(ArgumentError, /ledger is required/)
    end
  end

  describe "solidity addresses" do
    it "encodes as 20 bytes of shard, realm and num" do
      expect(Hiero::AccountId.from_string("0.0.123").to_solidity_address)
        .to eq("000000000000000000000000000000000000007b")
    end

    it "round-trips" do
      id = Hiero::TokenId.from_string("1.2.3")

      expect(Hiero::TokenId.from_solidity_address(id.to_solidity_address)).to eq(id)
    end

    it "rejects a wrongly sized address" do
      expect { Hiero::TokenId.from_solidity_address("00" * 19) }
        .to raise_error(Hiero::BadEntityIdError, /20 bytes/)
    end
  end

  describe "coercion" do
    it "accepts the identifier, a string or a bare number" do
      forms = [Hiero::TokenId.from_string("0.0.5"), "0.0.5", 5, "5"]

      expect(forms.map { |f| Hiero::TokenId.coerce(f) }.uniq.length).to eq(1)
    end

    it "passes nil through" do
      expect(Hiero::TokenId.coerce(nil)).to be_nil
    end

    it "accepts an object that knows how to become one" do
      wrapper = Class.new { def to_token_id = Hiero::TokenId.new(num: 9) }.new

      expect(Hiero::TokenId.coerce(wrapper)).to eq(Hiero::TokenId.new(num: 9))
    end

    it "rejects anything else" do
      expect { Hiero::TokenId.coerce(Object.new) }.to raise_error(Hiero::BadEntityIdError)
    end
  end

  describe "equality and ordering" do
    it "ignores the checksum, which describes how an id was written, not what it points at" do
      expect(Hiero::AccountId.from_string("0.0.123")).to eq(Hiero::AccountId.from_string("0.0.123-vfmkw"))
    end

    it "hashes consistently, so ids work as Hash keys" do
      expect({ Hiero::TokenId.from_string("0.0.1") => :ok }[Hiero::TokenId.new(num: 1)]).to eq(:ok)
    end

    it "never equates different identifier types" do
      # A TokenId and a TopicId with the same numbers address entirely different
      # things; conflating them would be a silent, expensive bug.
      expect(Hiero::TokenId.from_string("0.0.1")).not_to eq(Hiero::TopicId.from_string("0.0.1"))
      expect(Hiero::TokenId.from_string("0.0.1") <=> Hiero::TopicId.from_string("0.0.1")).to be_nil
    end

    it "sorts numerically rather than lexically" do
      ids = ["0.0.10", "0.0.2", "1.0.0"].map { |s| Hiero::TokenId.from_string(s) }

      expect(ids.sort.map(&:to_s)).to eq(["0.0.2", "0.0.10", "1.0.0"])
    end
  end

  it "supports pattern matching, being a Data type" do
    result = case Hiero::AccountId.from_string("0.0.7")
             in { shard: 0, realm: 0, num: Integer => n } then n
             end

    expect(result).to eq(7)
  end

  it "is immutable" do
    expect(Hiero::TokenId.new(num: 1)).to be_frozen
  end
end
