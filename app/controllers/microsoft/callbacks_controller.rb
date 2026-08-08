class Microsoft::CallbacksController < OauthCallbackController
  include MicrosoftConcern

  private

  def oauth_client
    microsoft_client
  end

  def provider_name
    'microsoft'
  end

  def imap_address
    'outlook.office365.com'
  end

  # Azure AD requires specifying a single resource's scope when exchanging an auth code
  # that was authorized with multi-resource scopes (IMAP + Graph API).
  # Without this, the token endpoint returns an error and the channel is never saved.
  def token_exchange_params
    { scope: 'offline_access https://outlook.office.com/IMAP.AccessAsUser.All openid profile email' }
  end
end
