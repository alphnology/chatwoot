require 'rails_helper'

describe Messages::Instagram::MessageBuilder do
  subject(:instagram_message_builder) { described_class }

  before do
    stub_request(:post, /graph.facebook.com/)
    stub_request(:get, 'https://www.example.com/test.jpeg')
  end

  let!(:account) { create(:account) }
  let!(:instagram_channel) { create(:channel_instagram_fb_page, account: account, instagram_id: 'chatwoot-app-user-id-1') }
  let!(:instagram_inbox) { create(:inbox, channel: instagram_channel, account: account, greeting_enabled: false) }
  let!(:dm_params) { build(:instagram_message_create_event).with_indifferent_access }
  let!(:story_mention_params) { build(:instagram_story_mention_event).with_indifferent_access }
  let!(:instagram_story_reply_event) { build(:instagram_story_reply_event).with_indifferent_access }
  let!(:instagram_message_reply_event) { build(:instagram_message_reply_event).with_indifferent_access }
  let(:fb_object) { double }
  let(:contact) { create(:contact, id: 'Sender-id-1', name: 'Jane Dae') }
  let(:contact_inbox) { create(:contact_inbox, contact_id: contact.id, inbox_id: instagram_inbox.id, source_id: 'Sender-id-1') }
  let(:conversation) do
    create(:conversation, account_id: account.id, inbox_id: instagram_inbox.id, contact_id: contact.id,
                          additional_attributes: { type: 'instagram_direct_message', conversation_language: 'en' })
  end
  let(:message) do
    create(:message, account_id: account.id, inbox_id: instagram_inbox.id, conversation_id: conversation.id, message_type: 'outgoing',
                     source_id: 'message-id-1')
  end

  describe '#perform' do
    it 'creates contact and message for the facebook inbox' do
      allow(Koala::Facebook::API).to receive(:new).and_return(fb_object)
      allow(fb_object).to receive(:get_object).and_return(
        {
          name: 'Jane',
          id: 'Sender-id-1',
          account_id: instagram_inbox.account_id,
          profile_pic: 'https://chatwoot-assets.local/sample.png'
        }.with_indifferent_access
      )
      messaging = dm_params[:entry][0]['messaging'][0]
      contact_inbox
      described_class.new(messaging, instagram_inbox).perform

      instagram_inbox.reload

      expect(instagram_inbox.conversations.count).to be 1
      expect(instagram_inbox.messages.count).to be 1

      contact = instagram_channel.inbox.contacts.first
      message = instagram_channel.inbox.messages.first

      expect(contact.name).to eq('Jane Dae')
      expect(message.content).to eq('This is the first message from the customer')
    end

    it 'discard echo message already sent by chatwoot' do
      message

      expect(instagram_inbox.conversations.count).to be 1
      expect(instagram_inbox.messages.count).to be 1

      allow(Koala::Facebook::API).to receive(:new).and_return(fb_object)
      allow(fb_object).to receive(:get_object).and_return(
        {
          name: 'Jane',
          id: 'Sender-id-1',
          account_id: instagram_inbox.account_id,
          profile_pic: 'https://chatwoot-assets.local/sample.png'
        }.with_indifferent_access
      )
      messaging = dm_params[:entry][0]['messaging'][0]
      contact_inbox
      described_class.new(messaging, instagram_inbox, outgoing_echo: true).perform

      instagram_inbox.reload

      expect(instagram_inbox.conversations.count).to be 1
      expect(instagram_inbox.messages.count).to be 1
    end

    it 'creates message with for reply with story id' do
      allow(Koala::Facebook::API).to receive(:new).and_return(fb_object)
      allow(fb_object).to receive(:get_object).and_return(
        {
          name: 'Jane',
          id: 'Sender-id-1',
          account_id: instagram_inbox.account_id,
          profile_pic: 'https://chatwoot-assets.local/sample.png'
        }.with_indifferent_access
      )
      messaging = instagram_story_reply_event[:entry][0]['messaging'][0]
      contact_inbox

      described_class.new(messaging, instagram_inbox).perform

      message = instagram_channel.inbox.messages.first

      expect(message.content).to eq('This is the story reply')
      expect(message.content_attributes[:story_sender]).to eq(instagram_inbox.channel.instagram_id)
      expect(message.content_attributes[:story_id]).to eq('chatwoot-app-user-id-1')
      expect(message.content_attributes[:story_url]).to eq('https://chatwoot-assets.local/sample.png')
    end

    it 'creates message with for reply with mid' do
      allow(Koala::Facebook::API).to receive(:new).and_return(fb_object)
      allow(fb_object).to receive(:get_object).and_return(
        {
          name: 'Jane',
          id: 'Sender-id-1',
          account_id: instagram_inbox.account_id,
          profile_pic: 'https://chatwoot-assets.local/sample.png'
        }.with_indifferent_access
      )
      # create first message to ensure reply to is valid
      first_message = dm_params[:entry][0]['messaging'][0]
      contact_inbox
      described_class.new(first_message, instagram_inbox).perform

      # create the second message with the reply to mid set
      messaging = instagram_message_reply_event[:entry][0]['messaging'][0]
      contact_inbox

      described_class.new(messaging, instagram_inbox).perform
      first_message = instagram_channel.inbox.messages.first
      message = instagram_channel.inbox.messages.last

      expect(message.content).to eq('This is message with replyto mid')
      expect(message.content_attributes[:in_reply_to_external_id]).to eq(first_message.source_id)
      expect(message.content_attributes[:in_reply_to]).to eq(first_message.id)
    end

    it 'raises exception on deleted story' do
      allow(Koala::Facebook::API).to receive(:new).and_return(fb_object)
      allow(fb_object).to receive(:get_object).and_raise(Koala::Facebook::ClientError.new(
                                                           190,
                                                           'This Message has been deleted by the user or the business.'
                                                         ))

      messaging = story_mention_params[:entry][0][:messaging][0]
      contact_inbox
      described_class.new(messaging, instagram_inbox, outgoing_echo: false).perform

      instagram_inbox.reload

      # we would have contact created, message created but the empty message because the story mention has been deleted later
      # As they show it in instagram that this story is no longer available
      # and external attachments link would be reachable
      expect(instagram_inbox.conversations.count).to be 1
      expect(instagram_inbox.messages.count).to be 1

      contact = instagram_channel.inbox.contacts.first
      message = instagram_channel.inbox.messages.first

      expect(contact.name).to eq('Jane Dae')
      expect(message.content).to eq('This story is no longer available.')
      expect(message.attachments.count).to eq(0)
    end

    it 'does not create message for unsupported file type' do
      allow(Koala::Facebook::API).to receive(:new).and_return(fb_object)
      allow(fb_object).to receive(:get_object).and_return(
        {
          name: 'Jane',
          id: 'Sender-id-1',
          account_id: instagram_inbox.account_id,
          profile_pic: 'https://chatwoot-assets.local/sample.png'
        }.with_indifferent_access
      )
      story_mention_params[:entry][0][:messaging][0]['message']['attachments'][0]['type'] = 'unsupported_type'
      messaging = story_mention_params[:entry][0][:messaging][0]
      contact_inbox
      described_class.new(messaging, instagram_inbox, outgoing_echo: false).perform

      instagram_inbox.reload

      # we would have contact created but message and attachments won't be created
      expect(instagram_inbox.conversations.count).to be 0
      expect(instagram_inbox.messages.count).to be 0

      contact = instagram_channel.inbox.contacts.first

      expect(contact.name).to eq('Jane Dae')
    end
  end

  context 'when lock to single conversation is disabled' do
    before do
      instagram_inbox.update!(lock_to_single_conversation: false)
      stub_request(:get, /graph.facebook.com/)
    end

    it 'creates a new conversation if existing conversation is not present' do
      message = dm_params[:entry][0]['messaging'][0]
      contact_inbox

      instagram_inbox.reload
      described_class.new(message, instagram_inbox).perform

      instagram_inbox.reload
      contact_inbox.reload

      expect(instagram_inbox.conversations.count).to eq(1)
    end

    it 'will not create a new conversation if last conversation is not resolved' do
      existing_conversation = create(:conversation, account_id: account.id, inbox_id: instagram_inbox.id, contact_id: contact.id, status: :open,
                                                    additional_attributes: { type: 'instagram_direct_message', conversation_language: 'en' })

      message = dm_params[:entry][0]['messaging'][0]
      contact_inbox

      instagram_inbox.reload
      described_class.new(message, instagram_inbox).perform

      instagram_inbox.reload
      contact_inbox.reload

      puts "instagram_inbox.conversations: #{instagram_inbox.conversations.last.inspect}"

      expect(instagram_inbox.conversations.last.id).to eq(existing_conversation.id)
    end

    it 'creates a new conversation if last conversation is resolved' do
      existing_conversation = create(:conversation, account_id: account.id, inbox_id: instagram_inbox.id, contact_id: contact.id, status: :resolved,
                                                    additional_attributes: { type: 'instagram_direct_message', conversation_language: 'en' })

      inital_count = Conversation.count
      message = dm_params[:entry][0]['messaging'][0]
      contact_inbox

      instagram_inbox.reload
      described_class.new(message, instagram_inbox).perform

      instagram_inbox.reload
      contact_inbox.reload

      expect(instagram_inbox.conversations.last.id).not_to eq(existing_conversation.id)
      expect(Conversation.count).to eq(inital_count + 1)
    end
  end

  context 'when lock to single conversation is enabled' do
    before do
      instagram_inbox.update!(lock_to_single_conversation: true)
      stub_request(:get, /graph.facebook.com/)
    end

    it 'creates a new conversation if existing conversation is not present' do
      message = dm_params[:entry][0]['messaging'][0]
      contact_inbox

      instagram_inbox.reload
      described_class.new(message, instagram_inbox).perform

      instagram_inbox.reload
      contact_inbox.reload

      expect(instagram_inbox.conversations.count).to eq(1)
    end

    it 'will not create a new conversation if last conversation is not resolved' do
      existing_conversation = create(:conversation, account_id: account.id, inbox_id: instagram_inbox.id, contact_id: contact.id, status: :open,
                                                    additional_attributes: { type: 'instagram_direct_message', conversation_language: 'en' })

      message = dm_params[:entry][0]['messaging'][0]
      contact_inbox

      instagram_inbox.reload
      described_class.new(message, instagram_inbox).perform

      instagram_inbox.reload
      contact_inbox.reload

      expect(instagram_inbox.conversations.last.id).to eq(existing_conversation.id)
    end

    it 'reopens last conversation if last conversation is resolved' do
      existing_conversation = create(:conversation, account_id: account.id, inbox_id: instagram_inbox.id, contact_id: contact.id, status: :resolved,
                                                    additional_attributes: { type: 'instagram_direct_message', conversation_language: 'en' })

      inital_count = Conversation.count

      message = dm_params[:entry][0]['messaging'][0]
      contact_inbox

      instagram_inbox.reload
      described_class.new(message, instagram_inbox).perform

      instagram_inbox.reload
      contact_inbox.reload

      expect(instagram_inbox.conversations.last.id).to eq(existing_conversation.id)
      expect(Conversation.count).to eq(inital_count)
    end
  end
end
