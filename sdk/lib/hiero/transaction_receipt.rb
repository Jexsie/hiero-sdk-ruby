# frozen_string_literal: true

module Hiero
  # The outcome of a transaction that reached consensus.
  #
  # A receipt exists whether the transaction succeeded or failed. If it failed,
  # fees were still charged -- consensus was reached, and the network did the work
  # of deciding the answer was no.
  class TransactionReceipt
    attr_reader :status, :account_id, :file_id, :contract_id, :topic_id, :token_id,
                :schedule_id, :serial_numbers, :topic_sequence_number, :new_total_supply

    def initialize(status:, **entities)
      @status = status
      @account_id = entities[:account_id]
      @file_id = entities[:file_id]
      @contract_id = entities[:contract_id]
      @topic_id = entities[:topic_id]
      @token_id = entities[:token_id]
      @schedule_id = entities[:schedule_id]
      @serial_numbers = (entities[:serial_numbers] || []).freeze
      @topic_sequence_number = entities[:topic_sequence_number]
      @new_total_supply = entities[:new_total_supply]
      freeze
    end

    def self.from_protobuf(proto)
      new(
        status: Status[proto.status],
        # Each of these is set only by the transaction type that creates that
        # entity, so a receipt from a transfer has all of them nil.
        account_id: proto.accountID && AccountId.new(shard: proto.accountID.shardNum,
                                                     realm: proto.accountID.realmNum,
                                                     num: proto.accountID.accountNum),
        file_id: proto.fileID && FileId.new(shard: proto.fileID.shardNum,
                                            realm: proto.fileID.realmNum, num: proto.fileID.fileNum),
        contract_id: proto.contractID && ContractId.new(shard: proto.contractID.shardNum,
                                                        realm: proto.contractID.realmNum,
                                                        num: proto.contractID.contractNum),
        topic_id: proto.topicID && TopicId.new(shard: proto.topicID.shardNum,
                                               realm: proto.topicID.realmNum, num: proto.topicID.topicNum),
        token_id: proto.tokenID && TokenId.new(shard: proto.tokenID.shardNum,
                                               realm: proto.tokenID.realmNum, num: proto.tokenID.tokenNum),
        schedule_id: proto.scheduleID && ScheduleId.new(shard: proto.scheduleID.shardNum,
                                                        realm: proto.scheduleID.realmNum,
                                                        num: proto.scheduleID.scheduleNum),
        serial_numbers: proto.serialNumbers.to_a,
        topic_sequence_number: proto.topicSequenceNumber.zero? ? nil : proto.topicSequenceNumber,
        new_total_supply: proto.newTotalSupply.zero? ? nil : proto.newTotalSupply
      )
    end

    def success? = @status.success?

    # @raise [ReceiptStatusError] unless the transaction succeeded
    def validate_status!(transaction_id = nil)
      return self if success?

      raise ReceiptStatusError.new(status: @status, transaction_id: transaction_id)
    end

    def to_s = @status.to_s

    def inspect
      created = { account: @account_id, file: @file_id, contract: @contract_id,
                  topic: @topic_id, token: @token_id, schedule: @schedule_id }.compact
      "#<#{self.class} #{@status}#{created.empty? ? '' : " #{created.map { |k, v| "#{k}=#{v}" }.join(' ')}"}>"
    end
  end
end
