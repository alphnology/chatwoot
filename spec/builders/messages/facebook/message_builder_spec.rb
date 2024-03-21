require 'rails_helper'

FBMessage = Struct.new(:sender_id, :attachments, :content, :identifier, :in_reply_to_external_id)

describe Messages::Facebook::MessageBuilder do
  subject(:message_builder) { described_class.new(incoming_fb_text_message, facebook_channel.inbox).perform }

  before do
    stub_request(:post, /graph.facebook.com/)
  end

  let!(:account) { create(:account) }
  let!(:facebook_channel) { create(:channel_facebook_page) }
  let!(:facebook_inbox) { create(:inbox, channel: facebook_channel, account: account, greeting_enabled: false) }
  let(:contact) { create(:contact, name: 'Jane Dae') }
  let(:contact_inbox) { create(:contact_inbox, contact_id: contact.id, inbox_id: facebook_inbox.id) }
  let!(:message_object) { build(:incoming_fb_text_message).to_json }
  let!(:incoming_fb_text_message) { Integrations::Facebook::MessageParser.new(message_object) }
  let(:fb_object) { double }

  describe '#perform' do
    it 'creates contact and message for the facebook inbox' do
      allow(Koala::Facebook::API).to receive(:new).and_return(fb_object)
      allow(fb_object).to receive(:get_object).and_return(
        {
          first_name: 'Jane',
          last_name: 'Dae',
          account_id: facebook_channel.inbox.account_id,
          profile_pic: 'https://chatwoot-assets.local/sample.png'
        }.with_indifferent_access
      )
      message_builder

      contact = facebook_channel.inbox.contacts.first
      message = facebook_channel.inbox.messages.first

      expect(contact.name).to eq('Jane Dae')
      expect(message.content).to eq('facebook message')
    end

    it 'increments channel authorization_error_count when error is thrown' do
      allow(Koala::Facebook::API).to receive(:new).and_return(fb_object)
      allow(fb_object).to receive(:get_object).and_raise(Koala::Facebook::AuthenticationError.new(500, 'Error validating access token'))
      message_builder

      expect(facebook_channel.authorization_error_count).to eq(2)
    end

    it 'raises exception for non profile account' do
      allow(Koala::Facebook::API).to receive(:new).and_return(fb_object)
      allow(fb_object).to receive(:get_object).and_raise(Koala::Facebook::ClientError.new(400, '',
                                                                                          {
                                                                                            'type' => 'OAuthException',
                                                                                            'message' => '(#100) No profile available for this user.',
                                                                                            'error_subcode' => 2_018_218,
                                                                                            'code' => 100
                                                                                          }))
      message_builder

      contact = facebook_channel.inbox.contacts.first
      # Refer: https://github.com/chatwoot/chatwoot/pull/3016 for this check
      default_name = 'John Doe'

      expect(facebook_channel.inbox.reload.contacts.count).to eq(1)
      expect(contact.name).to eq(default_name)
    end

    context 'when lock to single conversation is disabled' do
      before do
        facebook_inbox.update!(lock_to_single_conversation: false)
        stub_request(:get, /graph.facebook.com/)
      end

      it 'creates a new conversation if existing conversation is not present' do
        message = FBMessage.new(contact_inbox.source_id, {}, '', '', '')
        facebook_inbox.reload
        described_class.new(message, facebook_inbox).perform

        facebook_inbox.reload
        contact_inbox.reload

        expect(facebook_inbox.conversations.count).to eq(1)
      end

      it 'will not create a new conversation if last conversation is not resolved' do
        existing_conversation = create(:conversation, account_id: account.id, inbox_id: facebook_inbox.id, contact_id: contact.id, status: :open)

        message = FBMessage.new(contact_inbox.source_id, {}, '', '', '')
        facebook_inbox.reload
        described_class.new(message, facebook_inbox).perform

        facebook_inbox.reload
        contact_inbox.reload

        expect(facebook_inbox.conversations.last.id).to eq(existing_conversation.id)
      end

      it 'creates a new conversation if last conversation is resolved' do
        existing_conversation = create(:conversation, account_id: account.id, inbox_id: facebook_inbox.id, contact_id: contact.id,
                                                      contact_inbox_id: contact_inbox.id, status: :resolved)

        inital_count = Conversation.count

        message = FBMessage.new(contact_inbox.source_id, {}, '', '', '')
        facebook_inbox.reload
        described_class.new(message, facebook_inbox).perform

        facebook_inbox.reload
        contact_inbox.reload

        expect(facebook_inbox.conversations.last.id).not_to eq(existing_conversation.id)
        expect(Conversation.count).to eq(inital_count + 1)
      end
    end

    context 'when lock to single conversation is enabled' do
      before do
        facebook_inbox.update!(lock_to_single_conversation: true)
        stub_request(:get, /graph.facebook.com/)
      end

      it 'creates a new conversation if existing conversation is not present' do
        message = FBMessage.new(contact_inbox.source_id, {}, '', '', '')
        facebook_inbox.reload
        described_class.new(message, facebook_inbox).perform

        facebook_inbox.reload
        contact_inbox.reload

        expect(facebook_inbox.conversations.count).to eq(1)
      end

      it 'will not create a new conversation if last conversation is not resolved' do
        existing_conversation = create(:conversation, account_id: account.id, inbox_id: facebook_inbox.id, contact_id: contact.id, status: :open)

        message = FBMessage.new(contact_inbox.source_id, {}, '', '', '')
        facebook_inbox.reload
        described_class.new(message, facebook_inbox).perform

        facebook_inbox.reload
        contact_inbox.reload

        expect(facebook_inbox.conversations.last.id).to eq(existing_conversation.id)
      end

      it 'reopens last conversation if last conversation is resolved' do
        existing_conversation = create(:conversation, account_id: account.id, inbox_id: facebook_inbox.id, contact_id: contact.id,
                                                      contact_inbox_id: contact_inbox.id, status: :resolved)

        inital_count = Conversation.count

        message = FBMessage.new(contact_inbox.source_id, {}, '', '', '')
        facebook_inbox.reload
        described_class.new(message, facebook_inbox).perform

        facebook_inbox.reload
        contact_inbox.reload

        expect(facebook_inbox.conversations.last.id).to eq(existing_conversation.id)
        expect(Conversation.count).to eq(inital_count)
      end
    end
  end
end
