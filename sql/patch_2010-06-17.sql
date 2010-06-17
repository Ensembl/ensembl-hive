    # Fixing the claim_analysis_status index:
ALTER TABLE analysis_job DROP INDEX claim_analysis_status;
ALTER TABLE analysis_job ADD INDEX claim_analysis_status  (job_claim, analysis_id, status, semaphore_count);
