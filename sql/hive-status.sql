select analysis.analysis_id,logic_name, status, count(*) from analysis_job, analysis where analysis_job.analysis_id=analysis.analysis_id group by analysis_job.analysis_id, status;

