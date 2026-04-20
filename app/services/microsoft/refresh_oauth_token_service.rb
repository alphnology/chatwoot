# Refer: https://learn.microsoft.com/en-us/entra/identity-platform/configurable-token-lifetimes
class Microsoft::RefreshOauthTokenService < BaseRefreshOauthTokenService
  IMAP_SCOPE = 'offline_access https://outlook.office.com/IMAP.AccessAsUser.All'.freeze

  private

  def build_oauth_strategy
    ::MicrosoftGraphAuth.new(nil, GlobalConfigService.load('AZURE_APP_ID', ''), GlobalConfigService.load('AZURE_APP_SECRET', ''))
  end

  # Microsoft v2.0 requires an explicit scope on refresh requests.
  # Without it the returned access_token may not include IMAP.AccessAsUser.All,
  # causing XOAUTH2 authentication to fail after the token expires (~1 hour).
  def refresh_tokens
    oauth_strategy = build_oauth_strategy
    token_service = build_token_service(oauth_strategy)
    new_tokens = token_service.refresh!(scope: IMAP_SCOPE).to_hash.slice(:access_token, :refresh_token, :expires_at)
    update_channel_provider_config(new_tokens)
    channel.reload.provider_config
  end

  # Merge instead of replace so Graph-specific keys (graph_access_token, graph_expires_on)
  # are preserved across IMAP token refreshes.
  def update_channel_provider_config(new_tokens)
    existing = channel.provider_config.with_indifferent_access
    channel.provider_config = existing.merge(
      access_token: new_tokens[:access_token],
      refresh_token: new_tokens[:refresh_token] || existing[:refresh_token],
      expires_on: Time.at(new_tokens[:expires_at]).utc.to_s
    )
    channel.save!
  end
end
