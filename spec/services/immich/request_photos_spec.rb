# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::RequestPhotos do
  describe '#call' do
    subject(:service) { described_class.new(user).call }

    let(:user) do
      create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => '123456' })
    end
    let(:mock_immich_data) do
      {
        "albums": {
          "total": 0,
          "count": 0,
          "items": [],
          "facets": []
        },
        "assets": {
          "total": 2,
          "count": 2,
          "items": [
            {
              "id": '7fe486e3-c3ba-4b54-bbf9-1281b39ed15c',
              "deviceAssetId": 'IMG_9913.jpeg-1168914',
              "ownerId": 'f579f328-c355-438c-a82c-fe3390bd5f08',
              "deviceId": 'CLI',
              "libraryId": nil,
              "type": 'IMAGE',
              "originalPath": 'upload/library/admin/2023/2023-06-08/IMG_9913.jpeg',
              "originalFileName": 'IMG_9913.jpeg',
              "originalMimeType": 'image/jpeg',
              "thumbhash": '4RgONQaZqYaH93g3h3p3d6RfPPrG',
              "fileCreatedAt": '2023-06-08T07:58:45.637Z',
              "fileModifiedAt": '2023-06-08T09:58:45.000Z',
              "localDateTime": '2023-06-08T09:58:45.637Z',
              "updatedAt": '2024-08-24T18:20:47.965Z',
              "isFavorite": false,
              "isArchived": false,
              "isTrashed": false,
              "duration": '0:00:00.00000',
              "exifInfo": {
                "make": 'Apple',
                "model": 'iPhone 12 Pro',
                "exifImageWidth": 4032,
                "exifImageHeight": 3024,
                "fileSizeInByte": 1_168_914,
                "orientation": '6',
                "dateTimeOriginal": '2023-06-08T07:58:45.637Z',
                "modifyDate": '2023-06-08T07:58:45.000Z',
                "timeZone": 'Europe/Berlin',
                "lensModel": 'iPhone 12 Pro back triple camera 4.2mm f/1.6',
                "fNumber": 1.6,
                "focalLength": 4.2,
                "iso": 320,
                "exposureTime": '1/60',
                "latitude": 52.11,
                "longitude": 13.22,
                "city": 'Johannisthal',
                "state": 'Berlin',
                "country": 'Germany',
                "description": '',
                "projectionType": nil,
                "rating": nil
              },
              "livePhotoVideoId": nil,
              "people": [],
              "checksum": 'aL1edPVg4ZpEnS6xCRWNUY0pUS8=',
              "isOffline": false,
              "hasMetadata": true,
              "duplicateId": '88a34bee-783d-46e4-aa52-33b75ffda375',
              "resized": true
            },
            {
              "id": '7fe486e3-c3ba-4b54-bbf9-1281b39ed15c2',
              "deviceAssetId": 'IMG_9913.jpeg-1168914',
              "ownerId": 'f579f328-c355-438c-a82c-fe3390bd5f08',
              "deviceId": 'CLI',
              "libraryId": nil,
              "type": 'VIDEO',
              "originalPath": 'upload/library/admin/2023/2023-06-08/IMG_9913.jpeg',
              "originalFileName": 'IMG_9913.jpeg',
              "originalMimeType": 'image/jpeg',
              "thumbhash": '4RgONQaZqYaH93g3h3p3d6RfPPrG',
              "fileCreatedAt": '2023-06-08T07:58:45.637Z',
              "fileModifiedAt": '2023-06-08T09:58:45.000Z',
              "localDateTime": '2023-06-08T09:58:45.637Z',
              "updatedAt": '2024-08-24T18:20:47.965Z',
              "isFavorite": false,
              "isArchived": false,
              "isTrashed": false,
              "duration": '0:00:00.00000',
              "exifInfo": {
                "make": 'Apple',
                "model": 'iPhone 12 Pro',
                "exifImageWidth": 4032,
                "exifImageHeight": 3024,
                "fileSizeInByte": 1_168_914,
                "orientation": '6',
                "dateTimeOriginal": '2023-06-08T07:58:45.637Z',
                "modifyDate": '2023-06-08T07:58:45.000Z',
                "timeZone": 'Europe/Berlin',
                "lensModel": 'iPhone 12 Pro back triple camera 4.2mm f/1.6',
                "fNumber": 1.6,
                "focalLength": 4.2,
                "iso": 320,
                "exposureTime": '1/60',
                "latitude": 52.11,
                "longitude": 13.22,
                "city": 'Johannisthal',
                "state": 'Berlin',
                "country": 'Germany',
                "description": '',
                "projectionType": nil,
                "rating": nil
              },
              "livePhotoVideoId": nil,
              "people": [],
              "checksum": 'aL1edPVg4ZpEnS6xCRWNUY0pUS8=',
              "isOffline": false,
              "hasMetadata": true,
              "duplicateId": '88a34bee-783d-46e4-aa52-33b75ffda375',
              "resized": true
            }
          ],
          nextPage: nil
        }
      }.to_json
    end

    context 'when user has immich_url and immich_api_key' do
      before do
        stub_request(
          :any,
          'http://immich.app/api/search/metadata'
        ).to_return(status: 200, body: mock_immich_data, headers: { 'content-type' => 'application/json' })
      end

      it 'returns images and videos' do
        expect(service.map { _1['type'] }.uniq).to eq(%w[IMAGE VIDEO])
      end

      it 'does not send an album filter' do
        service

        expect(WebMock).not_to(
          have_requested(:post, 'http://immich.app/api/search/metadata')
            .with { |req| JSON.parse(req.body).key?('albumIds') }
        )
      end
    end

    context 'when an album id is given' do
      subject(:service) do
        described_class.new(
          user,
          start_date: '2023-06-07T10:00:00Z',
          end_date: '2023-06-09T12:00:00Z',
          album_id: '0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c'
        ).call
      end

      let(:empty_immich_data) do
        { assets: { total: 0, count: 0, items: [], facets: [] } }.to_json
      end

      before do
        stub_request(:any, 'http://immich.app/api/search/metadata')
          .to_return(
            { status: 200, body: mock_immich_data, headers: { 'content-type' => 'application/json' } },
            { status: 200, body: empty_immich_data, headers: { 'content-type' => 'application/json' } }
          )
        stub_request(:get, 'http://immich.app/api/albums/0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c')
          .to_return(
            status: 200,
            body: { assets: [{ id: '7fe486e3-c3ba-4b54-bbf9-1281b39ed15c' }] }.to_json,
            headers: { 'content-type' => 'application/json' }
          )
      end

      it 'requests only assets from that album' do
        service

        expect(WebMock).to(
          have_requested(:post, 'http://immich.app/api/search/metadata')
            .with { |req| JSON.parse(req.body)['albumIds'] == ['0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c'] }
            .at_least_once
        )
      end

      it 'keeps only photos that belong to the album, even if the server returned more' do
        expect(service.map { _1['id'] }).to eq(['7fe486e3-c3ba-4b54-bbf9-1281b39ed15c'])
      end

      it 'widens the date window to whole days plus one day on each side' do
        service

        expect(WebMock).to(
          have_requested(:post, 'http://immich.app/api/search/metadata')
            .with do |req|
              body = JSON.parse(req.body)
              body['takenAfter'] == '2023-06-06T00:00:00Z' && body['takenBefore'] == '2023-06-10T23:59:59Z'
            end
            .at_least_once
        )
      end

      it 'fails closed when the album cannot be fetched' do
        stub_request(:get, 'http://immich.app/api/albums/0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c')
          .to_return(status: 500, body: '')

        expect(service).to be_nil
      end
    end

    context 'when user has no immich_url' do
      before do
        user.settings['immich_url'] = nil
        user.save
      end

      it 'raises ArgumentError' do
        expect { service }.to raise_error(ArgumentError, 'Immich URL is missing')
      end
    end

    context 'when user has no immich_api_key' do
      before do
        user.settings['immich_api_key'] = nil
        user.save
      end

      it 'raises ArgumentError' do
        expect { service }.to raise_error(ArgumentError, 'Immich API key is missing')
      end
    end
  end
end
