# frozen_string_literal: true

class Photos::Search
  attr_reader :user, :start_date, :end_date, :errors

  def self.cached(user, start_date: '1970-01-01', end_date: nil, album: nil, expires_in: 1.minute)
    key = "photos_search/#{user.id}/#{start_date}/#{end_date}/#{album&.dig(:source)}/#{album&.dig(:id)}"
    cached = Rails.cache.read(key)
    return cached if cached.present?

    result = new(user, start_date: start_date, end_date: end_date, album: album).call
    Rails.cache.write(key, result, expires_in: expires_in) if result.present?
    result
  end

  def initialize(user, start_date: '1970-01-01', end_date: nil, album: nil)
    @user = user
    @start_date = start_date
    @end_date = end_date
    @album_source = album&.dig(:source)&.to_s
    @album_id = album&.dig(:id)
    @errors = []
  end

  def call
    photos = []

    immich_photos = request_immich if search_immich?
    photoprism_photos = request_photoprism if search_photoprism?

    photos << immich_photos if immich_photos.present?
    photos << photoprism_photos if photoprism_photos.present?

    photos.flatten.map { |photo| Api::PhotoSerializer.new(photo, photo[:source]).call }
  end

  private

  attr_reader :album_source, :album_id

  # A selected album pins the search to its source: only that integration is
  # queried, so an Immich album never gets mixed with Photoprism photos.
  def search_immich?
    user.immich_integration_configured? && (album_id.blank? || album_source == 'immich')
  end

  def search_photoprism?
    user.photoprism_integration_configured? && (album_id.blank? || album_source == 'photoprism')
  end

  def request_immich
    assets = Immich::RequestPhotos.new(
      user,
      start_date: start_date,
      end_date: end_date,
      album_id: album_source == 'immich' ? album_id : nil
    ).call
    if assets.nil?
      errors << :immich
      return nil
    end

    assets.map { |asset| transform_asset(asset, 'immich') }.compact
  end

  def request_photoprism
    Photoprism::RequestPhotos.new(
      user,
      start_date: start_date,
      end_date: end_date,
      album_uid: album_source == 'photoprism' ? album_id : nil
    ).call.map { |asset| transform_asset(asset, 'photoprism') }.compact
  end

  def transform_asset(asset, source)
    asset_type = asset['type'] || asset['Type']
    return if asset_type.downcase == 'video'

    asset.merge(source: source)
  end
end
