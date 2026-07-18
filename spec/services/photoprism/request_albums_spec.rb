# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photoprism::RequestAlbums do
  describe '#call' do
    subject(:service) { described_class.new(user).call }

    let(:user) do
      create(
        :user,
        settings: {
          'photoprism_url' => 'http://photoprism.local',
          'photoprism_api_key' => 'test_api_key'
        }
      )
    end

    let(:albums_response) do
      [
        { 'UID' => 'aqnzih81icziiyae', 'Title' => 'Belgium trip 2026', 'PhotoCount' => 42 },
        { 'UID' => 'brmzjh92jdzjjzbf', 'Title' => 'Winter holidays', 'PhotoCount' => 7 }
      ]
    end

    context 'with albums available' do
      before do
        stub_request(:get, 'http://photoprism.local/api/v1/albums')
          .with(query: hash_including(type: 'album'))
          .to_return(status: 200, body: albums_response.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns albums normalized to source, id, name and photo count' do
        expect(service).to eq(
          [
            { source: 'photoprism', id: 'aqnzih81icziiyae',
              name: 'Belgium trip 2026', photo_count: 42 },
            { source: 'photoprism', id: 'brmzjh92jdzjjzbf',
              name: 'Winter holidays', photo_count: 7 }
          ]
        )
      end
    end

    context 'when the request fails' do
      before do
        stub_request(:get, /photoprism\.local/).to_return(status: 401, body: '')
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
