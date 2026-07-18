# frozen_string_literal: true

# Aggregates photo albums from every configured photo integration into a flat
# list of { source:, id:, name:, photo_count: } hashes. A failing integration
# is logged and skipped so the other source's albums still come through.
class Photos::Albums
  CACHE_TTL = 5.minutes

  def self.cached(user)
    Rails.cache.fetch("photos_albums/#{user.id}", expires_in: CACHE_TTL) do
      new(user).call
    end
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
