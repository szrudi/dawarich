# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::Photos::AlbumsController', type: :request do
  let(:user) { create(:user, :with_immich_integration) }
  let(:api_key) { user.api_key }

  path '/api/v1/photos/albums' do
    get 'Lists photo albums' do
      tags 'Photos'
      description 'Returns albums from connected photo services (Immich, PhotoPrism). ' \
                  'Albums can be attached to a trip to limit its photos to that album.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'albums found' do
        before do
          stub_request(:get, "#{user.settings['immich_url']}/api/albums")
            .to_return(
              status: 200,
              body: [
                { 'id' => '0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c', 'albumName' => 'Belgium trip 2026',
                  'assetCount' => 42 }
              ].to_json,
              headers: { 'content-type' => 'application/json' }
            )
        end

        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   source: { type: :string, enum: %w[immich photoprism], description: 'Photo source service' },
                   id: { type: :string, description: 'Album ID in the source service' },
                   name: { type: :string, description: 'Album title' },
                   photo_count: { type: :integer, nullable: true, description: 'Number of photos in the album' }
                 },
                 required: %w[source id name]
               }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to be_an(Array)
          expect(data.first['source']).to eq('immich')
        end
      end

      response '401', 'no photo integration configured' do
        let(:user) { create(:user) }

        run_test!
      end

      response '403', 'pro plan required (cloud lite users)' do
        schema type: :object,
               properties: {
                 error: { type: :string },
                 message: { type: :string },
                 upgrade_url: { type: :string }
               }

        let(:user) { create(:user, :with_immich_integration, plan: :lite) }

        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        end

        run_test!
      end
    end
  end
end
