# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Photos::Albums', type: :request do
  describe 'GET /api/v1/photos/albums' do
    context 'when an integration is configured' do
      let(:user) { create(:user, :with_immich_integration) }

      let(:albums_response) do
        [{ 'id' => 'a-1', 'albumName' => 'Belgium trip 2026', 'assetCount' => 42 }]
      end

      before do
        stub_request(:get, 'https://immich.example.com/api/albums')
          .to_return(status: 200, body: albums_response.to_json,
                     headers: { 'content-type' => 'application/json' })
      end

      it 'returns the albums list' do
        get '/api/v1/photos/albums', params: { api_key: user.api_key }

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to eq(
          [{ 'source' => 'immich', 'id' => 'a-1',
             'name' => 'Belgium trip 2026', 'photo_count' => 42 }]
        )
      end
    end

    context 'when no integration is configured' do
      let(:user) { create(:user) }

      it 'returns unauthorized' do
        get '/api/v1/photos/albums', params: { api_key: user.api_key }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'without an api key' do
      it 'returns unauthorized' do
        get '/api/v1/photos/albums'

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
