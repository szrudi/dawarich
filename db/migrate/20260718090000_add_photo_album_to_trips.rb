# frozen_string_literal: true

class AddPhotoAlbumToTrips < ActiveRecord::Migration[8.0]
  def change
    add_column :trips, :photo_album_source, :integer
    add_column :trips, :photo_album_id, :string
    add_column :trips, :photo_album_name, :string
  end
end
