class MatchDataJob < Struct.new(:match_id_ours)

  def perform
    match = Match.find_by_id(match_id_ours)
    if match.present? && match.processed.blank?
      match.process_stats()
    end
  end

  def self.queue_time
    last_job = Delayed::Job.where("handler LIKE '%MatchDataJob%'").order("run_at DESC").first()
    if last_job.present? && last_job.run_at > DateTime.now().utc - 10.seconds
      last_job.run_at + 10.seconds
    else
      DateTime.now().utc + 10.seconds
    end
  end

  def error(job, exception)
    @exception = exception
    if not_found?
      match = Match.find_by_id(match_id_ours)
      if match.present? && match.processed.blank?
        match.processed = true
        match.save()
      end
    end
  end

  def reschedule_at(attempts, time)
    if at_rate_limit?
      next_rate_limit_window
    end
  end

  def max_attempts
    if at_rate_limit?
      10
    elsif not_found?
      1
    else
      Delayed::Worker.max_attempts
    end
  end

  private

  def at_rate_limit?
    @exception.is_a?(Lol::TooManyRequests)
  end

  def not_found?
    @exception.is_a?(Lol::NotFound)
  end

  def next_rate_limit_window
    self.class.queue_time + 30.seconds
  end

end
