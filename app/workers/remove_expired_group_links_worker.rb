# frozen_string_literal: true

class RemoveExpiredGroupLinksWorker
  include ApplicationWorker
  include CronjobQueue

  def perform
    ProjectGroupLink.expired.destroy_all # rubocop: disable DestroyAll
  end
end
