class Microsoft::SendMailService
  pattr_initialize [:channel!, :message!, :to_emails!, :cc_emails, :bcc_emails, :subject!, :html_body!, :text_body,
                    :in_reply_to, :references]

  GRAPH_API_BASE = 'https://graph.microsoft.com/v1.0'.freeze
  MAX_ATTACHMENT_SIZE = 20.megabytes

  def perform
    response = send_mail_via_graph_api
    handle_response(response)
  end

  private

  def send_mail_via_graph_api
    uri = URI("#{GRAPH_API_BASE}/me/sendMail")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'text/plain'
    request.body = Base64.strict_encode64(build_mime_message)

    http.request(request)
  end

  def access_token
    @graph_token_service ||= Microsoft::GraphTokenService.new(channel: channel)
    @graph_token_service.access_token
  end

  def build_mime_message
    mail = Mail.new
    apply_mail_headers(mail)
    apply_threading_headers(mail)
    apply_mail_body(mail)
    apply_attachments(mail)
    mail.to_s
  end

  def apply_mail_headers(mail)
    mail.to = Array(to_emails).compact
    mail.from = channel.email
    mail.subject = subject
    mail.message_id = "<#{generate_message_id}>"
    mail.cc = Array(cc_emails).compact if cc_emails.present?
    mail.bcc = Array(bcc_emails).compact if bcc_emails.present?
  end

  # Graph API blocks In-Reply-To/References via internetMessageHeaders, but MIME allows them
  def apply_threading_headers(mail)
    mail.in_reply_to = ensure_angle_brackets(in_reply_to) if in_reply_to.present?

    # Always include a stable conversation identifier in References.
    # Microsoft Graph API often overwrites the Message-ID of outgoing emails,
    # which can break threading on replies. Including the conversation UUID
    # ensures that Chatwoot can still link the reply back via the References header.
    conversation = message.conversation
    fallback_id = "<account/#{conversation.account_id}/conversation/#{conversation.uuid}@#{email_domain}>"

    refs = Array.wrap(references).join(' ').split
    refs << in_reply_to if in_reply_to.present?
    refs << fallback_id

    mail.references = refs.flatten.compact.map { |r| ensure_angle_brackets(r) }.uniq.join(' ')
  end

  def apply_mail_body(mail)
    html_content = html_body
    text_content = text_body

    mail.html_part = Mail::Part.new do
      content_type 'text/html; charset=UTF-8'
      body html_content
    end

    return if text_content.blank?

    mail.text_part = Mail::Part.new do
      content_type 'text/plain; charset=UTF-8'
      body text_content
    end
  end

  def apply_attachments(mail)
    return if message.attachments.blank?

    total_size = 0
    message.attachments.each do |attachment|
      blob = attachment.file.blob
      next if blob.blank?
      next if (total_size + blob.byte_size) > MAX_ATTACHMENT_SIZE

      total_size += blob.byte_size
      blob.open do |file|
        mail.add_file filename: attachment.file.filename.to_s, content: file.read
      end
    end
  end

  def ensure_angle_brackets(value)
    return nil if value.blank?

    value = value.to_s.strip
    return value if value.start_with?('<') && value.end_with?('>')

    "<#{value.gsub(/^<|>$/, '')}>"
  end

  def handle_response(response)
    case response.code.to_i
    when 202
      Rails.logger.info("Microsoft Graph API: Email sent successfully via MIME for message #{message.id}")
      OpenStruct.new(success: true, message_id: generate_message_id)
    when 401
      raise_graph_error('Authentication failed - token may be expired or invalid')
    when 403
      raise_graph_error('Permission denied - Mail.Send scope may be missing')
    else
      error_body = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        { 'error' => { 'message' => response.body } }
      end
      raise StandardError, "Microsoft Graph API error (#{response.code}): #{error_body.dig('error', 'message') || 'Unknown error'}"
    end
  end

  def raise_graph_error(msg)
    Rails.logger.error("Microsoft Graph API: #{msg}")
    raise StandardError, msg
  end

  def generate_message_id
    conversation = message.conversation
    "conversation/#{conversation.uuid}/messages/#{message.id}@#{email_domain}"
  end

  def email_domain
    channel.email.split('@').last
  end
end
