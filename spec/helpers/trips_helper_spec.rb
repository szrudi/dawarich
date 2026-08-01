# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TripsHelper, type: :helper do
  describe '#photo_album_url' do
    let(:settings) do
      {
        'immich_url' => 'https://immich.example.com/',
        'photoprism_url' => 'https://photos.example.com'
      }
    end

    it 'builds the Immich album URL, tolerating a trailing slash in the base' do
      expect(helper.photo_album_url('immich', settings, 'abc-123'))
        .to eq('https://immich.example.com/albums/abc-123')
    end

    it 'builds the PhotoPrism album URL' do
      expect(helper.photo_album_url('photoprism', settings, 'aqnzih81icziiyae'))
        .to eq('https://photos.example.com/library/albums/aqnzih81icziiyae/view')
    end

    it 'returns nil for an unknown source' do
      expect(helper.photo_album_url('other', settings, 'abc')).to be_nil
    end
  end
end
