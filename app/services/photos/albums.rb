# frozen_string_literal: true

# Aggregates photo albums from every configured photo integration into a flat
# list of { source:, id:, name:, photo_count: } hashes. A failing integration
# is logged and skipped so the other source's albums still come through.
class Photos::Albums
  CACHE_TTL = 5.minutes

  # Blank results are not cached: they can mean "integration briefly down",
  # and caching that would blank the album picker for the full TTL. The key
  # carries a fingerprint of the integration URLs so rewiring a server
  # doesn't serve the previous server's albums.
  def self.cached(user)
    key = cache_key(user)
    cached = Rails.cache.read(key)
    return cached if cached.present?

    result = new(user).call
    Rails.cache.write(key, result, expires_in: CACHE_TTL) if result.present?
    result
  end

  def self.cache_key(user)
    settings = user.safe_settings
    fingerprint = Digest::MD5.hexdigest(
      [
        settings.immich_url, settings.immich_api_key,
        settings.photoprism_url, settings.photoprism_api_key
      ].join('|')
    )
    "photos_albums/#{user.id}/#{fingerprint}"
  end

  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    albums = []
    albums.concat(request_immich) if user.immich_integration_configured?
    albums.concat(request_photoprism) if user.photoprism_integration_configured?
    albums
  end

  private

  def request_immich
    Immich::RequestAlbums.new(user).call
  rescue StandardError => e
    Rails.logger.error("Immich albums fetch failed: #{e.class} #{e.message}")
    []
  end

  def request_photoprism
    Photoprism::RequestAlbums.new(user).call
  rescue StandardError => e
    Rails.logger.error("Photoprism albums fetch failed: #{e.class} #{e.message}")
    []
  end
end
