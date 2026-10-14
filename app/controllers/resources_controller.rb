class ResourcesController < ApplicationController
  # Nil when Kubernetes can't be reached (e.g. locally, with no cluster) -
  # the page says so rather than failing.
  def show
    @usage = ResourceUsage.new
  rescue KubernetesApi::Error, *KubernetesApi::CONNECTION_ERRORS => e
    Rails.logger.warn("ResourcesController: couldn't read resource usage: #{e.message}")
    @usage = nil
  end
end
