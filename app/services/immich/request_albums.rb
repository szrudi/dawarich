# frozen_string_literal: true

class Immich::RequestAlbums
  include SslConfigurable

  attr_reader :user, :immich_api_base_url, :immich_api_key

  def initialize(user)
    @user = user
    @immich_api_base_url = "#{user.safe_settings.immich_url}/api/albums"
    @immich_api_key = user.safe_settings.immich_api_key
  end

  def call
    raise ArgumentError, 'Immich API key is missing' if immich_api_key.blank?
    raise ArgumentError, 'Immich URL is missing'     if user.safe_settings.immich_url.blank?

    response = HTTParty.get(
      immich_api_base_url,
      http_options_with_ssl(user, :immich, { headers: headers, timeout: 10 })
    )

    result = Immich::ResponseValidator.validate_and_parse(response)

    unless result[:success]
      Rails.logger.error("Immich albums fetch failed: #{result[:error]}")
      return []
    end

    Array(result[:data]).map do |album|
      {
        source: 'immich',
        id: album['id'],
        name: album['albumName'],
        photo_count: album['assetCount']
      }
    end
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Immich albums fetch failed: #{e.message}")
    []
  end

  private

  def headers
    {
      'x-api-key' => immich_api_key,
      'accept' => 'application/json'
    }
  end
end
