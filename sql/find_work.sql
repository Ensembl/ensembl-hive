select logic_name, analysis.analysis_id, status, count(*) from analysis_job, analysis where analysis_job.analysis_id=analysis.analysis_id and status='READY' group by analysis_job.analysis_id;
