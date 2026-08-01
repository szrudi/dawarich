# frozen_string_literal: true

class Api::V1::Photos::AlbumsController < ApiController
  before_action :require_pro_api!
  before_action :check_integration_configured

  def index
    albums = ::Photos::Albums.cached(current_api_user)

    render json: albums, status: :ok
  rescue StandardError => e
    Rails.logger.error("Photo albums fetch failed: #{e.message}")
    render json: { error: 'Failed to fetch albums' }, status: :bad_gateway
  end

  private

  def check_integration_configured
    return if current_api_user.immich_integration_configured? ||
              current_api_user.photoprism_integration_configured?

    render json: { error: 'No photo integration configured' }, status: :unauthorized
  end
end
