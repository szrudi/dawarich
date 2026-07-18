# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::RequestAlbumAssets do
  describe '#call' do
    subject(:service) { described_class.new(user, album_id).call }

    let(:user) do
      create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => '123456' })
    end
    let(:album_id) { '0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c' }

    context 'when the album exists' do
      before do
        stub_request(:get, "http://immich.app/api/albums/#{album_id}")
          .to_return(
            status: 200,
            body: {
              id: album_id,
              albumName: 'Belgium trip 2026',
              assets: [{ id: 'asset-1' }, { id: 'asset-2' }]
            }.to_json,
            headers: { 'content-type' => 'application/json' }
          )
      end

      it 'returns the album asset ids' do
        expect(service).to eq(%w[asset-1 asset-2])
      end
    end

    context 'when the album request fails' do
      before do
        stub_request(:get, "http://immich.app/api/albums/#{album_id}").to_return(status: 404, body: '')
      end

      it 'returns nil so callers fail closed' do
        expect(service).to be_nil
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
