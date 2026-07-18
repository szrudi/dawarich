# frozen_string_literal: true

# Fetches the asset ids belonging to one Immich album. Used to verify album
# membership of search results: older Immich servers silently strip unknown
# search params (their ValidationPipe whitelists DTO fields), so a search
# filtered by albumIds can quietly return every photo in the date range.
# Cross-checking against the album's own asset list guarantees the filter.
#
# Returns an Array of asset id strings, or nil when the album can't be
# fetched — callers must treat nil as "fail closed", not as an empty album.
class Immich::RequestAlbumAssets
  include SslConfigurable

  attr_reader :user, :album_id

  def initialize(user, album_id)
    @user = user
    @album_id = album_id
  end

  def call
    raise ArgumentError, 'Immich API key is missing' if api_key.blank?
    raise ArgumentError, 'Immich URL is missing'     if base_url.blank?

    response = HTTParty.get(
      "#{base_url}/api/albums/#{ERB::Util.url_encode(album_id)}",
      http_options_with_ssl(user, :immich, { headers: headers, timeout: 10 })
    )

    result = Immich::ResponseValidator.validate_and_parse(response)

    unless result[:success]
      Rails.logger.error("Immich album assets fetch failed: #{result[:error]}")
      return nil
    end

    Array(result[:data]['assets']).map { |asset| asset['id'] }
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Immich album assets fetch failed: #{e.message}")
    nil
  end

  private

  def base_url
    user.safe_settings.immich_url
  end

  def api_key
    user.safe_settings.immich_api_key
  end

  def headers
    {
      'x-api-key' => api_key,
      'accept' => 'application/json'
    }
  end
end
