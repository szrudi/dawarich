# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photos::Search do
  let(:user) { create(:user) }
  let(:start_date) { '2024-01-01' }
  let(:end_date) { '2024-03-01' }
  let(:service) { described_class.new(user, start_date: start_date, end_date: end_date) }

  describe '#call' do
    context 'when user has no integrations configured' do
      before do
        allow(user).to receive(:immich_integration_configured?).and_return(false)
        allow(user).to receive(:photoprism_integration_configured?).and_return(false)
      end

      it 'returns an empty array' do
        expect(service.call).to eq([])
      end
    end

    context 'when user has Immich integration configured' do
      let(:immich_photo) { { 'type' => 'image', 'id' => '1' } }
      let(:serialized_photo) { { id: '1', source: 'immich' } }

      before do
        allow(user).to receive(:immich_integration_configured?).and_return(true)
        allow(user).to receive(:photoprism_integration_configured?).and_return(false)

        allow_any_instance_of(Immich::RequestPhotos).to receive(:call)
          .and_return([immich_photo])

        allow_any_instance_of(Api::PhotoSerializer).to receive(:call)
          .and_return(serialized_photo)
      end

      it 'fetches and transforms Immich photos' do
        expect(service.call).to eq([serialized_photo])
      end
    end

    context 'when user has Photoprism integration configured' do
      let(:photoprism_photo) { { 'Type' => 'image', 'id' => '2' } }
      let(:serialized_photo) { { id: '2', source: 'photoprism' } }

      before do
        allow(user).to receive(:immich_integration_configured?).and_return(false)
        allow(user).to receive(:photoprism_integration_configured?).and_return(true)

        allow_any_instance_of(Photoprism::RequestPhotos).to receive(:call)
          .and_return([photoprism_photo])

        allow_any_instance_of(Api::PhotoSerializer).to receive(:call)
          .and_return(serialized_photo)
      end

      it 'fetches and transforms Photoprism photos' do
        expect(service.call).to eq([serialized_photo])
      end
    end

    context 'when user has both integrations configured' do
      let(:immich_photo) { { 'type' => 'image', 'id' => '1' } }
      let(:photoprism_photo) { { 'Type' => 'image', 'id' => '2' } }
      let(:serialized_immich) do
        {
          id: '1',
          latitude: nil,
          longitude: nil,
          localDateTime: nil,
          capturedAt: nil,
          originalFileName: nil,
          city: nil,
          state: nil,
          country: nil,
          type: 'image',
          source: 'immich',
          orientation: 'landscape'
        }
      end
      let(:serialized_photoprism) do
        {
          id: '2',
          latitude: nil,
          longitude: nil,
          localDateTime: nil,
          capturedAt: nil,
          originalFileName: nil,
          city: nil,
          state: nil,
          country: nil,
          type: 'image',
          source: 'photoprism',
          orientation: 'landscape'
        }
      end

      before do
        allow(user).to receive(:immich_integration_configured?).and_return(true)
        allow(user).to receive(:photoprism_integration_configured?).and_return(true)

        allow_any_instance_of(Immich::RequestPhotos).to receive(:call)
          .and_return([immich_photo])
        allow_any_instance_of(Photoprism::RequestPhotos).to receive(:call)
          .and_return([photoprism_photo])
      end

      it 'fetches and transforms photos from both services' do
        expect(service.call).to eq([serialized_immich, serialized_photoprism])
      end
    end

    context 'when an album is given' do
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
      let(:immich_response) do
        {
          assets: {
            items: [{ 'id' => '1', 'type' => 'IMAGE', 'fileCreatedAt' => '2024-02-01T10:00:00Z' }],
            nextPage: nil
          }
        }
      end
      let(:empty_immich_response) { { assets: { items: [] } } }

      before do
        stub_request(:post, 'http://immich.app/api/search/metadata')
          .to_return(
            { status: 200, body: immich_response.to_json,
              headers: { 'content-type' => 'application/json' } },
            { status: 200, body: empty_immich_response.to_json,
              headers: { 'content-type' => 'application/json' } }
          )
        stub_request(:get, /photoprism\.local/)
          .to_return(status: 200, body: [].to_json,
                     headers: { 'Content-Type' => 'application/json' })
        stub_request(:get, %r{immich\.app/api/albums/})
          .to_return(status: 200, body: { assets: [{ id: '1' }] }.to_json,
                     headers: { 'content-type' => 'application/json' })
      end

      it 'queries only the album source and forwards the album id' do
        service = described_class.new(
          user,
          start_date: start_date,
          end_date: end_date,
          album: { source: 'immich', id: '0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c' }
        )

        result = service.call

        expect(result.map { _1[:source] }.uniq).to eq(['immich'])
        expect(WebMock).not_to have_requested(:get, /photoprism\.local/)
        expect(WebMock).to(
          have_requested(:post, 'http://immich.app/api/search/metadata')
            .with { |req| JSON.parse(req.body)['albumIds'] == ['0e214cbd-6a2f-4f2e-a44e-a1f70bcecf5c'] }
            .at_least_once
        )
      end

      it 'queries only Photoprism for a photoprism album' do
        service = described_class.new(
          user,
          start_date: start_date,
          end_date: end_date,
          album: { source: 'photoprism', id: 'aqnzih81icziiyae' }
        )

        service.call

        expect(WebMock).not_to have_requested(:post, 'http://immich.app/api/search/metadata')
        expect(WebMock).to have_requested(:get, /photoprism\.local/)
          .with(query: hash_including(s: 'aqnzih81icziiyae'))
      end
    end

    context 'when filtering out videos' do
      let(:immich_photo) { { 'type' => 'video', 'id' => '1' } }

      before do
        allow(user).to receive(:immich_integration_configured?).and_return(true)
        allow(user).to receive(:photoprism_integration_configured?).and_return(false)

        allow_any_instance_of(Immich::RequestPhotos).to receive(:call)
          .and_return([immich_photo])
      end

      it 'excludes video assets' do
        expect(service.call).to eq([])
      end
    end
  end

  describe '#initialize' do
    context 'with default parameters' do
      let(:service_default) { described_class.new(user) }

      it 'sets default start_date' do
        expect(service_default.start_date).to eq('1970-01-01')
      end

      it 'sets default end_date to nil' do
        expect(service_default.end_date).to be_nil
      end
    end

    context 'with custom parameters' do
      it 'sets custom dates' do
        expect(service.start_date).to eq(start_date)
        expect(service.end_date).to eq(end_date)
      end
    end
  end

  describe '.cached' do
    let(:immich_photo) { { 'type' => 'image', 'id' => '1' } }
    let(:serialized_photo) { { id: '1', source: 'immich' } }
    let(:args) { { start_date: '2024-01-01', end_date: '2024-03-01' } }

    before do
      allow(user).to receive(:immich_integration_configured?).and_return(true)
      allow(user).to receive(:photoprism_integration_configured?).and_return(false)
      allow_any_instance_of(Api::PhotoSerializer).to receive(:call).and_return(serialized_photo)
    end

    it 'returns the search results' do
      allow_any_instance_of(Immich::RequestPhotos).to receive(:call).and_return([immich_photo])

      expect(described_class.cached(user, **args)).to eq([serialized_photo])
    end

    it 'does not re-run the upstream search on a second call within the window' do
      call_count = 0
      allow_any_instance_of(Immich::RequestPhotos).to receive(:call) do
        call_count += 1
        [immich_photo]
      end

      described_class.cached(user, **args)
      described_class.cached(user, **args)

      expect(call_count).to eq(1)
    end

    it 'does not cache an empty result, so a transient empty re-queries upstream' do
      call_count = 0
      allow_any_instance_of(Immich::RequestPhotos).to receive(:call) do
        call_count += 1
        []
      end

      described_class.cached(user, **args)
      described_class.cached(user, **args)

      expect(call_count).to eq(2)
    end
  end
end
