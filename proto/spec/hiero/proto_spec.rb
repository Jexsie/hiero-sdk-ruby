# frozen_string_literal: true

# These are smoke tests for the generated protobuf layer, not tests of protobuf
# itself. They exist to catch a bad regeneration: a missing service, a namespace
# that stopped loading, or an upstream rename that silently drops a message the
# SDK is built on.
RSpec.describe Hiero::Proto do
  it "records the upstream tags it was generated from" do
    expect(described_class::HAPI_VERSION).to match(/\Av\d+\.\d+\.\d+/)
    expect(described_class::MIRROR_VERSION).to match(/\Av\d+\.\d+\.\d+/)
  end

  describe "every namespace loads on its own" do
    %w[block fees mirror platform sdk services streams].each do |namespace|
      it namespace do
        expect { require "hiero/proto/#{namespace}" }.not_to raise_error
      end
    end
  end

  describe "the HAPI services" do
    # The ten consensus node services the SDK's Channel exposes. RPC counts are
    # deliberately not asserted -- those move with every HAPI release, and a
    # service disappearing entirely is the failure worth catching.
    %w[
      CryptoService SmartContractService FileService ConsensusService
      TokenService ScheduleService FreezeService NetworkService
      UtilService AddressBookService
    ].each do |name|
      it "defines #{name} with a service definition and a client stub" do
        expect(Proto.const_get(name)::Service.rpc_descs).not_to be_empty
        expect(Proto.const_get(name)::Stub).to be < GRPC::ClientStub
      end
    end
  end

  describe "the mirror services" do
    let(:mirror) { Com::Hedera::Mirror::Api::Proto }

    it "exposes subscribeTopic, which only the mirror node repository defines" do
      expect(mirror::ConsensusService::Service.rpc_descs).to have_key(:subscribeTopic)
    end

    it "exposes getNodes for address book streaming" do
      expect(mirror::NetworkService::Service.rpc_descs).to have_key(:getNodes)
    end
  end

  describe "the messages the SDK is built on" do
    it "round-trips a TransactionBody" do
      body = Proto::TransactionBody.new(
        transactionID: Proto::TransactionID.new(
          transactionValidStart: Proto::Timestamp.new(seconds: 1_724_764_800, nanos: 42),
          accountID: Proto::AccountID.new(accountNum: 1234)
        ),
        nodeAccountID: Proto::AccountID.new(accountNum: 3),
        transactionFee: 200_000_000,
        cryptoTransfer: Proto::CryptoTransferTransactionBody.new
      )

      expect(Proto::TransactionBody.decode(Proto::TransactionBody.encode(body))).to eq(body)
    end

    it "reports the transaction body oneof, which keys the deserialization registry" do
      body = Proto::TransactionBody.new(cryptoTransfer: Proto::CryptoTransferTransactionBody.new)

      # Note the casing: HAPI declares this field as cryptoTransfer, so that -- not
      # :crypto_transfer -- is the registry key Transaction.from_bytes must look up.
      expect(body.data).to eq(:cryptoTransfer)
    end

    it "decodes int64 fields as arbitrary-precision Integers" do
      body = Proto::TransactionBody.new(transactionFee: 2**62)

      expect(body.transactionFee).to be_a(Integer)
      expect(Proto::TransactionBody.decode(Proto::TransactionBody.encode(body)).transactionFee)
        .to eq(2**62)
    end

    it "defines TransactionList, the multi-transaction serialization envelope" do
      list = Proto::TransactionList.new(transaction_list: [Proto::Transaction.new])

      expect(Proto::TransactionList.decode(Proto::TransactionList.encode(list))).to eq(list)
    end

    it "defines the full response code enum" do
      expect(Proto::ResponseCodeEnum.resolve(:SUCCESS)).to eq(22)
      expect(Proto::ResponseCodeEnum.descriptor.to_a.length).to be > 300
    end
  end
end
