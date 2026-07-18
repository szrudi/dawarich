# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::RequestAlbums do
  describe '#call' do
    subject(:service) { described_class.new(user).call }

    let(:user) do
      create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => '123456' })
    end

    let(:albums_response) do
      [
        {
          'id' => '0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c',
          'albumName' => 'Belgium trip 2026',
          'assetCount' => 42,
          'shared' => false
        },
        {
          'id' => '1f325dce-7b30-4a3f-b55f-b2081cdfdg6d',
          'albumName' => 'Winter holidays',
          'assetCount' => 7,
          'shared' => true
        }
      ]
    end

    context 'with albums available' do
      before do
        stub_request(:get, 'http://immich.app/api/albums')
          .to_return(status: 200, body: albums_response.to_json,
                     headers: { 'content-type' => 'application/json' })
      end

      it 'returns albums normalized to source, id, name and photo count' do
        expect(service).to eq(
          [
            { source: 'immich', id: '0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c',
              name: 'Belgium trip 2026', photo_count: 42 },
            { source: 'immich', id: '1f325dce-7b30-4a3f-b55f-b2081cdfdg6d',
              name: 'Winter holidays', photo_count: 7 }
          ]
        )
      end
    end

    context 'when the request fails' do
      before do
        stub_request(:get, 'http://immich.app/api/albums').to_return(status: 500, body: '')
      end

      it 'returns an empty array' do
        expect(service).to eq([])
      end
    end

    context 'when credentials are missing' do
      let(:user) { create(:user, settings: {}) }

      it 'raises ArgumentError' do
        expect { service }.to raise_error(ArgumentError)
      end
    end
  end
end
