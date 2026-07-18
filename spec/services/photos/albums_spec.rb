# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photos::Albums do
  describe '#call' do
    subject(:albums) { described_class.new(user).call }

    let(:user) do
      create(
        :user,
        settings: {
          'immich_url' => 'http://immich.app',
          'immich_api_key' => 'immich-key',
          'photoprism_url' => 'http://photoprism.local',
          'photoprism_api_key' => 'photoprism-key'
        }
      )
    end

    let(:immich_albums) do
      [{ 'id' => 'a-1', 'albumName' => 'Immich album', 'assetCount' => 3 }]
    end
    let(:photoprism_albums) do
      [{ 'UID' => 'p-1', 'Title' => 'Photoprism album', 'PhotoCount' => 5 }]
    end

    before do
      stub_request(:get, 'http://immich.app/api/albums')
        .to_return(status: 200, body: immich_albums.to_json,
                   headers: { 'content-type' => 'application/json' })
      stub_request(:get, %r{photoprism\.local/api/v1/albums})
        .to_return(status: 200, body: photoprism_albums.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'aggregates albums from all configured integrations' do
      expect(albums).to contain_exactly(
        { source: 'immich', id: 'a-1', name: 'Immich album', photo_count: 3 },
        { source: 'photoprism', id: 'p-1', name: 'Photoprism album', photo_count: 5 }
      )
    end

    context 'when one integration fails' do
      before do
        stub_request(:get, 'http://immich.app/api/albums').to_timeout
      end

      it 'still returns the albums of the other integration' do
        expect(albums).to eq(
          [{ source: 'photoprism', id: 'p-1', name: 'Photoprism album', photo_count: 5 }]
        )
      end
    end

    context 'when no integration is configured' do
      let(:user) { create(:user, settings: {}) }

      it 'returns an empty array' do
        expect(albums).to eq([])
      end
    end
  end
end
