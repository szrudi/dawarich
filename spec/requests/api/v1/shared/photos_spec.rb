# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Shared::Photos', type: :request do
  let(:owner) { create(:user) }
  let(:trip)  { create(:trip, user: owner) }

  context 'when show_photos is false' do
    let(:link) do
      create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                           settings: { 'show_photos' => false })
    end

    it 'returns empty array on index regardless of integration' do
      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'returns 404 for thumbnail requests' do
      get "/api/v1/shared/#{link.id}/photos/foo/thumbnail", params: { source: 'immich' }
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when show_photos is true but owner has no integration' do
    let(:link) do
      create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                           settings: { 'show_photos' => true })
    end

    it 'returns empty array' do
      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end

  context 'when show_photos is true and the trip has photos' do
    let(:link) do
      create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                           settings: { 'show_photos' => true })
    end
    let(:found_photos) do
      [{ id: 'asset-1', source: 'immich', latitude: 52.0, longitude: 13.0,
         localDateTime: '2026-04-02T14:30:00', capturedAt: '2026-04-02T13:30:00Z' }]
    end

    before do
      allow(Photos::Search).to receive(:new).and_return(instance_double(Photos::Search, call: found_photos))
    end

    it 'includes latitude and longitude so the map can place markers' do
      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
      photo = JSON.parse(response.body).first
      expect(photo).to include('id' => 'asset-1', 'latitude' => 52.0, 'longitude' => 13.0)
      expect(photo['thumbnail_url']).to be_present
    end

    it 'includes taken_at so replay can reveal photos by timestamp' do
      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).first['taken_at']).to eq('2026-04-02T13:30:00Z')
    end

    it 'includes the owner-timezone day so the map can group markers with the day rows' do
      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).first['day']).to eq('2026-04-02')
    end

    it 'serves thumbnails for photos belonging to the trip' do
      upstream = instance_double(HTTParty::Response, success?: true, body: 'jpeg-bytes')
      allow(Photos::Thumbnail).to receive(:new).with(owner, 'immich', 'asset-1').and_return(
        instance_double(Photos::Thumbnail, call: upstream)
      )

      get "/api/v1/shared/#{link.id}/photos/asset-1/thumbnail", params: { source: 'immich' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('jpeg-bytes')
    end

    it 'returns 404 for photo ids outside the trip without contacting the integration' do
      expect(Photos::Thumbnail).not_to receive(:new)

      get "/api/v1/shared/#{link.id}/photos/foreign-asset/thumbnail", params: { source: 'immich' }
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the trip has a photo album' do
    let(:owner) { create(:user, :with_immich_integration) }
    let(:trip) do
      create(:trip, user: owner,
                    photo_album_source: :immich,
                    photo_album_id: '0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c',
                    photo_album_name: 'Belgium trip 2026')
    end
    let(:link) do
      create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                           settings: { 'show_photos' => true })
    end

    before do
      stub_request(:post, 'https://immich.example.com/api/search/metadata')
        .to_return(status: 200, body: { assets: { items: [] } }.to_json,
                   headers: { 'content-type' => 'application/json' })
      stub_request(:get, %r{immich\.example\.com/api/albums/})
        .to_return(status: 200, body: { assets: [] }.to_json,
                   headers: { 'content-type' => 'application/json' })
    end

    it 'requests only photos from that album' do
      get "/api/v1/shared/#{link.id}/photos"

      expect(response).to have_http_status(:ok)
      expect(WebMock).to(
        have_requested(:post, 'https://immich.example.com/api/search/metadata')
          .with { |req| JSON.parse(req.body)['albumIds'] == ['0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c'] }
          .at_least_once
      )
    end

    it 'excludes photos the server returned that are not album members' do
      taken_at = (trip.started_at + 2.hours).utc.iso8601
      member = { 'id' => 'member-1', 'type' => 'IMAGE', 'fileCreatedAt' => taken_at,
                 'exifInfo' => { 'latitude' => 52.0, 'longitude' => 13.0 } }
      outsider = { 'id' => 'outsider-1', 'type' => 'IMAGE', 'fileCreatedAt' => taken_at,
                   'exifInfo' => { 'latitude' => 52.5, 'longitude' => 13.5 } }
      stub_request(:post, 'https://immich.example.com/api/search/metadata')
        .to_return(
          { status: 200, body: { assets: { items: [member, outsider] } }.to_json,
            headers: { 'content-type' => 'application/json' } },
          { status: 200, body: { assets: { items: [] } }.to_json,
            headers: { 'content-type' => 'application/json' } }
        )
      stub_request(:get, %r{immich\.example\.com/api/albums/})
        .to_return(status: 200, body: { assets: [{ id: 'member-1' }] }.to_json,
                   headers: { 'content-type' => 'application/json' })

      get "/api/v1/shared/#{link.id}/photos"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).map { |p| p['id'] }).to eq(['member-1'])
    end

    it 'returns no photos when the album asset list cannot be fetched' do
      stub_request(:get, %r{immich\.example\.com/api/albums/}).to_return(status: 500, body: '')

      get "/api/v1/shared/#{link.id}/photos"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end

  context 'when a photo falls inside a privacy zone' do
    let(:link) do
      create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                           settings: { 'show_photos' => true })
    end
    let(:found_photos) do
      [{ id: 'public-1', source: 'immich', latitude: 60.0, longitude: 10.0 },
       { id: 'private-1', source: 'immich', latitude: 52.0, longitude: 13.0 }]
    end

    before do
      allow(Photos::Search).to receive(:new).and_return(instance_double(Photos::Search, call: found_photos))
      home = create(:place, user: owner, latitude: 52.0, longitude: 13.0)
      tag = create(:tag, user: owner, privacy_radius_meters: 500)
      create(:tagging, tag: tag, taggable: home)
    end

    it 'excludes the masked photo from the index' do
      get "/api/v1/shared/#{link.id}/photos"
      ids = JSON.parse(response.body).map { |p| p['id'] }
      expect(ids).to eq(['public-1'])
    end

    it 'returns 404 for a masked photo thumbnail without contacting the integration' do
      expect(Photos::Thumbnail).not_to receive(:new)
      get "/api/v1/shared/#{link.id}/photos/private-1/thumbnail", params: { source: 'immich' }
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'for a track share with photos' do
    let(:track) do
      create(:track, user: owner, start_at: Time.utc(2026, 4, 1), end_at: Time.utc(2026, 4, 14))
    end
    let(:link) do
      create(:shared_link, user: owner, resource_type: :track, resource_id: track.id,
                           settings: { 'show_photos' => true })
    end
    let(:found_photos) { [{ id: 'asset-1', source: 'immich', latitude: 52.0, longitude: 13.0 }] }

    before do
      allow(Photos::Search).to receive(:new).and_return(instance_double(Photos::Search, call: found_photos))
    end

    it 'returns geotagged photos within the track window' do
      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).first).to include('id' => 'asset-1', 'latitude' => 52.0)
    end

    it 'searches photos within the track start_at..end_at range' do
      # Undo this context's Photos::Search stub — this test asserts the real
      # outgoing HTTP request.
      allow(Photos::Search).to receive(:new).and_call_original
      immich_owner = create(:user, :with_immich_integration)
      immich_track = create(:track, user: immich_owner,
                                    start_at: Time.utc(2026, 4, 1), end_at: Time.utc(2026, 4, 14))
      immich_link = create(:shared_link, user: immich_owner, resource_type: :track,
                                         resource_id: immich_track.id, settings: { 'show_photos' => true })
      stub_request(:post, 'https://immich.example.com/api/search/metadata')
        .to_return(status: 200, body: { assets: { items: [] } }.to_json,
                   headers: { 'content-type' => 'application/json' })

      get "/api/v1/shared/#{immich_link.id}/photos"

      expect(response).to have_http_status(:ok)
      expect(WebMock).to(
        have_requested(:post, 'https://immich.example.com/api/search/metadata')
          .with do |req|
            body = JSON.parse(req.body)
            body['takenAfter'] == '2026-04-01T00:00:00Z' && body['takenBefore'] == '2026-04-14T00:00:00Z'
          end
      )
    end
  end
end
