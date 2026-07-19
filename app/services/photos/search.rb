# frozen_string_literal: true

class Photos::Search
  attr_reader :user, :start_date, :end_date, :errors

  def self.cached(user, start_date: '1970-01-01', end_date: nil, album: nil, timezone: 'UTC', expires_in: 1.minute)
    key = "photos_search/#{user.id}/#{start_date}/#{end_date}/" \
          "#{album&.dig(:source)}/#{album&.dig(:id)}/#{album ? timezone : nil}"
    cached = Rails.cache.read(key)
    return cached if cached.present?

    result = new(user, start_date: start_date, end_date: end_date, album: album, timezone: timezone).call
    Rails.cache.write(key, result, expires_in: expires_in) if result.present?
    result
  end

  def initialize(user, start_date: '1970-01-01', end_date: nil, album: nil, timezone: 'UTC')
    @user = user
    @start_date = start_date
    @end_date = end_date
    @album_source = album&.dig(:source)&.to_s
    @album_id = album&.dig(:id)
    @timezone = timezone
    @errors = []
  end

  def call
    photos = []

    immich_photos = request_immich if search_immich?
    photoprism_photos = request_photoprism if search_photoprism?

    photos << immich_photos if immich_photos.present?
    photos << photoprism_photos if photoprism_photos.present?

    serialized = photos.flatten.map { |photo| Api::PhotoSerializer.new(photo, photo[:source]).call }
    album_id.present? ? clamp_to_days(serialized) : serialized
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

  # Album mode fetches a window widened by ±1 day (timezone tolerance for the
  # services' wall-clock timestamps), but only photos whose calendar day —
  # bucketed exactly like the trip page's day galleries — falls within the
  # requested days may surface. Without this clamp, adjacent-day album photos
  # (a multi-day album shared as a one-day trip) leak into maps and previews,
  # and can even evict same-day photos from capped views.
  def clamp_to_days(photos)
    zone = Time.find_zone(@timezone) || Time.find_zone('UTC')
    from = parse_date(start_date, zone)
    to   = parse_date(end_date, zone)
    return photos if from.nil? || to.nil?

    days = from..to
    photos.select do |photo|
      date = parse_date(photo[:capturedAt] || photo[:localDateTime], zone)
      date && days.cover?(date)
    end
  end

  def parse_date(raw, zone)
    return nil if raw.blank?

    zone.parse(raw.to_s)&.to_date
  rescue ArgumentError, TypeError
    nil
  end
end
