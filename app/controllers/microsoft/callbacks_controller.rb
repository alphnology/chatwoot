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

  # [ALPHNOLOGY] Azure AD requires specifying a single resource's scope when exchanging an auth
  # code that was authorized with multi-resource scopes (IMAP + Graph API).
  # Without this, the token endpoint returns an error and the channel is never saved.
  def token_exchange_params
    { scope: 'offline_access https://outlook.office.com/IMAP.AccessAsUser.All openid profile email' }
  end

  # Exchange Online's SMTP AUTH (XOAUTH2) rejects proxy addresses in the SASL `user=` field;
  # it must match the token's UPN. `preferred_username` is the documented v2.0 claim;
  # `upn` is the v1.0 fallback.
  def imap_login_identity
    users_data['preferred_username'] || users_data['upn'] || super
  end
end
