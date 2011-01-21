# introducing the FOREIGN KEY constraints as a separate file (so that they could be optionally switched on or off):

ALTER TABLE analysis_description    ADD FOREIGN KEY (analysis_id) REFERENCES analysis(analysis_id);
ALTER TABLE hive                    ADD FOREIGN KEY (analysis_id) REFERENCES analysis(analysis_id);
ALTER TABLE dataflow_rule           ADD FOREIGN KEY (from_analysis_id) REFERENCES analysis(analysis_id);
ALTER TABLE analysis_ctrl_rule      ADD FOREIGN KEY (ctrled_analysis_id) REFERENCES analysis(analysis_id);
ALTER TABLE analysis_job            ADD FOREIGN KEY (analysis_id) REFERENCES analysis(analysis_id);
ALTER TABLE job_message             ADD FOREIGN KEY (analysis_id) REFERENCES analysis(analysis_id);
ALTER TABLE analysis_stats          ADD FOREIGN KEY (analysis_id) REFERENCES analysis(analysis_id);
ALTER TABLE analysis_stats_monitor  ADD FOREIGN KEY (analysis_id) REFERENCES analysis(analysis_id);

ALTER TABLE analysis_job            ADD FOREIGN KEY (worker_id)   REFERENCES hive(worker_id);
ALTER TABLE job_message             ADD FOREIGN KEY (worker_id)   REFERENCES hive(worker_id);
ALTER TABLE analysis_job_file       ADD FOREIGN KEY (worker_id)   REFERENCES hive(worker_id);

ALTER TABLE analysis_job            ADD FOREIGN KEY (prev_analysis_job_id) REFERENCES analysis_job(analysis_job_id);
ALTER TABLE analysis_job            ADD FOREIGN KEY (semaphored_job_id) REFERENCES analysis_job(analysis_job_id);
ALTER TABLE job_message             ADD FOREIGN KEY (analysis_job_id) REFERENCES analysis_job(analysis_job_id);
ALTER TABLE analysis_job_file       ADD FOREIGN KEY (analysis_job_id) REFERENCES analysis_job(analysis_job_id);

## The following are not unique keys in the original table, so cannot be used as foreign keys.
# ALTER TABLE analysis_stats            ADD FOREIGN KEY (rc_id) REFERENCES resource_description(rc_id);
# ALTER TABLE analysis_stats_monitor    ADD FOREIGN KEY (rc_id) REFERENCES resource_description(rc_id);

