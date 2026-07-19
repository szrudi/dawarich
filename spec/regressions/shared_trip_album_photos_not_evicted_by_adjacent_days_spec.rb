# frozen_string_literal: true

require 'rails_helper'

# Regression: the album fetch window is widened ±1 day for timezone tolerance,
# and Photos::Mappable caps shared-map photos at the first 100 in time order.
# Before the day-clamp in Photos::Search, a multi-day album linked to a shorter
# trip filled the cap with adjacent-day photos, evicting every actual trip-day
# photo: the shared page showed markers from days outside the trip while its
# day galleries were empty.
RSpec.describe 'Shared trip album photos are not evicted by adjacent-day album photos', type: :request do
  let(:owner) { create(:user, :with_immich_integration) }
  let(:trip) do
    create(:trip, user: owner,
                  started_at: Time.utc(2026, 7, 5, 8, 0, 0),
                  ended_at: Time.utc(2026, 7, 7, 20, 0, 0),
                  photo_album_source: :immich,
                  photo_album_id: '0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c',
                  photo_album_name: 'Belgium 2026')
  end
  let(:link) do
    create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                         settings: { 'show_photos' => true })
  end

  # 120 geotagged album photos on the day BEFORE the trip (inside the widened
  # fetch window) plus 2 on a trip day — more adjacent photos than the
  # Photos::Mappable cap of 100.
  let(:adjacent_day_photos) do
    Array.new(120) do |i|
      { 'id' => "adjacent-#{i}", 'type' => 'IMAGE',
        'fileCreatedAt' => "2026-07-04T#{format('%02d', i % 20)}:#{format('%02d', i % 60)}:00Z",
        'exifInfo' => { 'latitude' => 51.0 + (i * 0.001), 'longitude' => 4.0 } }
    end
  end
  let(:trip_day_photos) do
    [
      { 'id' => 'trip-day-1', 'type' => 'IMAGE', 'fileCreatedAt' => '2026-07-05T10:00:00Z',
        'exifInfo' => { 'latitude' => 50.8, 'longitude' => 4.4 } },
      { 'id' => 'trip-day-2', 'type' => 'IMAGE', 'fileCreatedAt' => '2026-07-07T12:00:00Z',
        'exifInfo' => { 'latitude' => 50.9, 'longitude' => 4.5 } }
    ]
  end

  before do
    stub_request(:post, 'https://immich.example.com/api/search/metadata')
      .to_return(
        { status: 200,
          body: { assets: { items: adjacent_day_photos + trip_day_photos } }.to_json,
          headers: { 'content-type' => 'application/json' } },
        { status: 200, body: { assets: { items: [] } }.to_json,
          headers: { 'content-type' => 'application/json' } }
      )
    stub_request(:get, %r{immich\.example\.com/api/albums/})
      .to_return(
        status: 200,
        body: { assets: (adjacent_day_photos + trip_day_photos).map { |p| { id: p['id'] } } }.to_json,
        headers: { 'content-type' => 'application/json' }
      )
  end

  it 'serves exactly the trip-day photos on the shared map, none from adjacent days' do
    get "/api/v1/shared/#{link.id}/photos"

    expect(response).to have_http_status(:ok)
    ids = response.parsed_body.map { |p| p['id'] }
    expect(ids).to contain_exactly('trip-day-1', 'trip-day-2')
  end
end
