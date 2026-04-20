
require_relative 'config/environment'

# Setup
account = Account.first || Account.create!(name: 'Test Account')
channel = Channel::Email.create!(
  account: account,
  email: 'test@example.com',
  imap_address: 'localhost',
  imap_port: 993,
  imap_enabled: true,
  imap_login: 'test',
  imap_password: 'password'
)
inbox = channel.inbox
contact = Contact.create!(account: account, email: 'sender@example.com', name: 'Sender')
contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: 'sender@example.com')

conversation = Conversation.create!(
  account: account,
  inbox: inbox,
  contact: contact,
  contact_inbox: contact_inbox
)

# Create an outgoing message with a source_id (no brackets)
message_id = 'test-message-id'
Message.create!(
  account: account,
  inbox: inbox,
  conversation: conversation,
  message_type: 'outgoing',
  content: 'Original message',
  source_id: message_id
)

puts "Conversation ID: #{conversation.id}"
puts "Outgoing Message source_id: #{message_id}"

# Simulate a reply with brackets in In-Reply-To
reply_mail = Mail.new do
  from 'sender@example.com'
  to 'test@example.com'
  subject 'Re: Original message'
  message_id 'reply-id'
  in_reply_to "<#{message_id}>"
  body 'Reply content'
end

puts "Incoming In-Reply-To: #{reply_mail.in_reply_to}"

mailbox = Imap::ImapMailbox.new
mailbox.process(reply_mail, channel)

last_conversation = Conversation.last
if last_conversation.id == conversation.id
  puts "SUCCESS: Appended to existing conversation"
else
  puts "FAILURE: Created new conversation #{last_conversation.id}"
end

# Test MESSAGE_PATTERN which is currently missing in ImapMailbox
conversation_uuid = conversation.uuid
msg_id_with_uuid = "conversation/#{conversation_uuid}/messages/123@example.com"

reply_mail_uuid = Mail.new do
  from 'sender@example.com'
  to 'test@example.com'
  subject 'Re: Original message'
  message_id 'reply-id-uuid'
  in_reply_to "<#{msg_id_with_uuid}>"
  body 'Reply content with UUID pattern'
end

puts "Incoming In-Reply-To with UUID pattern: #{reply_mail_uuid.in_reply_to}"
mailbox.process(reply_mail_uuid, channel)

last_conversation = Conversation.last
if last_conversation.id == conversation.id
  puts "SUCCESS (UUID pattern): Appended to existing conversation"
else
  puts "FAILURE (UUID pattern): Created new conversation #{last_conversation.id}"
end
