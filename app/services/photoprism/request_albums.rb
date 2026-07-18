# frozen_string_literal: true

class Photoprism::RequestAlbums
  include SslConfigurable

  MAX_ALBUMS = 1000

  attr_reader :user, :photoprism_api_base_url, :photoprism_api_key

  def initialize(user)
    @user = user
    @photoprism_api_base_url = "#{user.safe_settings.photoprism_url}/api/v1/albums"
    @photoprism_api_key = user.safe_settings.photoprism_api_key
  end

  def call
    raise ArgumentError, 'Photoprism URL is missing' if user.safe_settings.photoprism_url.blank?
    raise ArgumentError, 'Photoprism API key is missing' if photoprism_api_key.blank?

    response = HTTParty.get(
      photoprism_api_base_url,
      http_options_with_ssl(
        user, :photoprism, {
          headers: headers,
          query: { type: 'album', count: MAX_ALBUMS },
          timeout: 10
        }
      )
    )

    result = Photoprism::ResponseValidator.validate_and_parse(response)

    unless result[:success]
      Rails.logger.error("Photoprism albums fetch failed: #{result[:error]}")
      return []
    end

    Array(result[:data]).map do |album|
      {
        source: 'photoprism',
        id: album['UID'],
        name: album['Title'],
        photo_count: album['PhotoCount']
      }
    end
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Photoprism albums fetch failed: #{e.message}")
    []
  end

  private

  def headers
    {
      'Authorization' => "Bearer #{photoprism_api_key}",
      'accept' => 'application/json'
    }
  end
end
