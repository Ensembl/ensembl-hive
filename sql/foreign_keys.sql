/*
    FOREIGN KEY constraints are listed in a separate file so that they could be optionally switched on or off.

    A nice surprise is that the syntax for defining them is the same for MySQL and PostgreSQL.
*/


ALTER TABLE worker                  ADD FOREIGN KEY (analysis_id)               REFERENCES analysis_base(analysis_id);
ALTER TABLE dataflow_rule           ADD FOREIGN KEY (from_analysis_id)          REFERENCES analysis_base(analysis_id);
ALTER TABLE analysis_ctrl_rule      ADD FOREIGN KEY (ctrled_analysis_id)        REFERENCES analysis_base(analysis_id);
ALTER TABLE job                     ADD FOREIGN KEY (analysis_id)               REFERENCES analysis_base(analysis_id);
ALTER TABLE analysis_stats          ADD FOREIGN KEY (analysis_id)               REFERENCES analysis_base(analysis_id);
ALTER TABLE analysis_stats_monitor  ADD FOREIGN KEY (analysis_id)               REFERENCES analysis_base(analysis_id);

ALTER TABLE job                     ADD FOREIGN KEY (worker_id)                 REFERENCES worker(worker_id);
ALTER TABLE log_message             ADD FOREIGN KEY (worker_id)                 REFERENCES worker(worker_id);
ALTER TABLE job_file                ADD FOREIGN KEY (worker_id)                 REFERENCES worker(worker_id);

ALTER TABLE job                     ADD FOREIGN KEY (prev_job_id)               REFERENCES job(job_id);
ALTER TABLE job                     ADD FOREIGN KEY (semaphored_job_id)         REFERENCES job(job_id);
ALTER TABLE log_message             ADD FOREIGN KEY (job_id)                    REFERENCES job(job_id);
ALTER TABLE job_file                ADD FOREIGN KEY (job_id)                    REFERENCES job(job_id);
ALTER TABLE accu                    ADD FOREIGN KEY (sending_job_id)            REFERENCES job(job_id);
ALTER TABLE accu                    ADD FOREIGN KEY (receiving_job_id)          REFERENCES job(job_id);

ALTER TABLE resource_description    ADD FOREIGN KEY (resource_class_id)         REFERENCES resource_class(resource_class_id);
ALTER TABLE analysis_base           ADD FOREIGN KEY (resource_class_id)         REFERENCES resource_class(resource_class_id);
ALTER TABLE worker                  ADD FOREIGN KEY (resource_class_id)         REFERENCES resource_class(resource_class_id);

ALTER TABLE dataflow_rule           ADD FOREIGN KEY (funnel_dataflow_rule_id)   REFERENCES dataflow_rule(dataflow_rule_id);
