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
    album_id.present? ? clamp_to_window(serialized) : serialized
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
  # services' wall-clock timestamps), so this clamp decides what actually
  # surfaces. Photos with an absolute capture instant (capturedAt: Immich
  # fileCreatedAt / PhotoPrism TakenAt) are compared against the exact
  # requested window — a photo taken the morning before an evening departure
  # is not part of the trip. Only wall-clock-only photos (localDateTime /
  # TakenAtLocal, which caused the original silent drops when compared
  # against UTC instants) fall back to a tolerant calendar-day match in the
  # owner's timezone. Without this clamp, adjacent-day album photos (a
  # multi-day album shared as a shorter trip) leak into maps and previews and
  # can even evict in-window photos from capped views.
  def clamp_to_window(photos)
    window_start = parse_time(start_date)
    window_end   = parse_time(end_date)
    return photos if window_start.nil? || window_end.nil?

    zone = Time.find_zone(@timezone) || Time.find_zone('UTC')
    days = window_start.in_time_zone(zone).to_date..window_end.in_time_zone(zone).to_date

    photos.select do |photo|
      if photo[:capturedAt].present?
        instant = parse_time(photo[:capturedAt])
        instant&.between?(window_start, window_end)
      else
        date = parse_wall_clock_date(photo[:localDateTime], zone)
        date && days.cover?(date)
      end
    end
  end

  def parse_time(raw)
    return nil if raw.blank?

    Time.parse(raw.to_s).utc
  rescue ArgumentError, TypeError
    nil
  end

  def parse_wall_clock_date(raw, zone)
    return nil if raw.blank?

    zone.parse(raw.to_s)&.to_date
  rescue ArgumentError, TypeError
    nil
  end
end
