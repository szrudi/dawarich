# frozen_string_literal: true

class Immich::RequestPhotos
  include SslConfigurable

  attr_reader :user, :immich_api_base_url, :immich_api_key, :start_date, :end_date, :album_id

  def initialize(user, start_date: '1970-01-01', end_date: nil, album_id: nil)
    @user = user
    @immich_api_base_url = "#{user.safe_settings.immich_url}/api/search/metadata"
    @immich_api_key = user.safe_settings.immich_api_key
    @start_date = start_date
    @end_date = end_date
    @album_id = album_id
  end

  def call
    raise ArgumentError, 'Immich API key is missing' if immich_api_key.blank?
    raise ArgumentError, 'Immich URL is missing'     if user.safe_settings.immich_url.blank?

    data = retrieve_immich_data
    return nil if data.nil?

    return time_framed_data(data) if album_id.blank?

    only_album_members(data)
  end

  private

  def retrieve_immich_data
    page = 1
    data = []
    max_pages = 10_000 # Prevent infinite loop

    # TODO: Handle pagination using nextPage
    while page <= max_pages
      response = HTTParty.post(
        immich_api_base_url,
        http_options_with_ssl(
          @user, :immich, {
            headers: headers,
            body: request_body(page).to_json,
            timeout: 10
          }
        )
      )

      result = Immich::ResponseValidator.validate_and_parse(response)

      unless result[:success]
        Rails.logger.error("Immich photo fetch failed: #{result[:error]}")
        return nil
      end

      Rails.logger.debug('==== IMMICH RESPONSE ====')
      Rails.logger.debug(result[:data])
      items = result[:data].dig('assets', 'items')

      break if items.blank?

      data << items

      page += 1
    end

    data.flatten
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Immich photo fetch failed: #{e.message}")
    nil
  end

  def headers
    {
      'x-api-key' => immich_api_key,
      'accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end

  def request_body(page)
    body = {
      takenAfter: taken_after,
      size: 1000,
      page: page,
      order: 'asc',
      withExif: true
    }

    body[:albumIds] = [album_id] if album_id.present?

    return body unless end_date

    body.merge(takenBefore: taken_before)
  end

  # Album mode deliberately loosens the date handling (both bounds widened to
  # whole UTC days ±1 day, and the client-side re-filter skipped in #call):
  # photo timestamps mix absolute instants (fileCreatedAt) with wall-clock
  # strings (localDateTime), so an exact trip window shifted by the photos'
  # timezone can silently drop an entire album (e.g. a 2h trip photographed
  # in a timezone 4h away). The album membership check is the real filter;
  # the widened window only bounds the fetch, and the trip page still renders
  # photos grouped onto the trip's own calendar days.
  def taken_after
    return normalize_date(start_date) if album_id.blank?

    date = parse_time(start_date)&.to_date
    date ? "#{date.prev_day.iso8601}T00:00:00Z" : normalize_date(start_date)
  end

  def taken_before
    return normalize_date(end_date) if album_id.blank?

    date = parse_time(end_date)&.to_date
    date ? "#{date.next_day.iso8601}T23:59:59Z" : normalize_date(end_date)
  end

  # Guarantees "only photos from this album" regardless of server version:
  # older Immich strips unknown search params (albumIds) without an error,
  # which would silently expose every photo in the window on shared pages.
  # Fails closed (nil, treated as an error upstream) when the album's asset
  # list can't be fetched. The id set is briefly cached because this runs on
  # every uncached trip-page render; failures are never cached.
  def only_album_members(data)
    asset_ids = Rails.cache.fetch("immich_album_assets/#{user.id}/#{album_id}", expires_in: 5.minutes) do
      Immich::RequestAlbumAssets.new(user, album_id).call
    end
    return nil if asset_ids.nil?
    # Album confirmed to exist, but this server doesn't inline the asset list
    # — only 2026-era Immich versions do that, and they all support albumIds
    # search filtering natively, so the server-side filter can be trusted.
    return data if asset_ids == :unavailable

    member_ids = asset_ids.to_set
    data.select { |photo| member_ids.include?(photo['id']) }
  end

  def time_framed_data(data)
    start_time = parse_time(start_date)
    end_time = parse_time(end_date)
    return data unless start_time

    data.select do |photo|
      photo_time = parse_time(photo['fileCreatedAt'] || photo['localDateTime'])
      next false unless photo_time

      photo_time >= start_time && (end_time.nil? || photo_time <= end_time)
    end
  end

  def normalize_date(value)
    parsed = parse_time(value)
    parsed ? parsed.iso8601 : value
  end

  def parse_time(value)
    return if value.blank?

    Time.parse(value.to_s).utc
  rescue ArgumentError, TypeError
    nil
  end
end
