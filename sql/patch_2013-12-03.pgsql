
-- drop all foreign keys and re-create some of them with "ON DELETE CASCADE" rule:

ALTER TABLE accu                    DROP CONSTRAINT accu_receiving_job_id_fkey, DROP CONSTRAINT accu_sending_job_id_fkey;
ALTER TABLE analysis_base           DROP CONSTRAINT analysis_base_resource_class_id_fkey;
ALTER TABLE analysis_ctrl_rule      DROP CONSTRAINT analysis_ctrl_rule_ctrled_analysis_id_fkey;
ALTER TABLE analysis_stats          DROP CONSTRAINT analysis_stats_analysis_id_fkey;
ALTER TABLE analysis_stats_monitor  DROP CONSTRAINT analysis_stats_monitor_analysis_id_fkey;
ALTER TABLE dataflow_rule           DROP CONSTRAINT dataflow_rule_from_analysis_id_fkey, DROP CONSTRAINT dataflow_rule_funnel_dataflow_rule_id_fkey;
ALTER TABLE job                     DROP CONSTRAINT job_analysis_id_fkey, DROP CONSTRAINT job_prev_job_id_fkey, DROP CONSTRAINT job_semaphored_job_id_fkey, DROP CONSTRAINT job_worker_id_fkey;
ALTER TABLE job_file                DROP CONSTRAINT job_file_job_id_fkey, DROP CONSTRAINT job_file_worker_id_fkey;
ALTER TABLE log_message             DROP CONSTRAINT log_message_job_id_fkey, DROP CONSTRAINT log_message_worker_id_fkey;
ALTER TABLE resource_description    DROP CONSTRAINT resource_description_resource_class_id_fkey;
ALTER TABLE worker                  DROP CONSTRAINT worker_analysis_id_fkey, DROP CONSTRAINT worker_resource_class_id_fkey;


-- now just replay foreign_keys.sql :

ALTER TABLE worker                  ADD FOREIGN KEY (analysis_id)               REFERENCES analysis_base(analysis_id);
ALTER TABLE dataflow_rule           ADD FOREIGN KEY (from_analysis_id)          REFERENCES analysis_base(analysis_id);
ALTER TABLE analysis_ctrl_rule      ADD FOREIGN KEY (ctrled_analysis_id)        REFERENCES analysis_base(analysis_id);
ALTER TABLE job                     ADD FOREIGN KEY (analysis_id)               REFERENCES analysis_base(analysis_id);
ALTER TABLE analysis_stats          ADD FOREIGN KEY (analysis_id)               REFERENCES analysis_base(analysis_id);
ALTER TABLE analysis_stats_monitor  ADD FOREIGN KEY (analysis_id)               REFERENCES analysis_base(analysis_id);

ALTER TABLE dataflow_rule           ADD FOREIGN KEY (funnel_dataflow_rule_id)   REFERENCES dataflow_rule(dataflow_rule_id);

ALTER TABLE resource_description    ADD FOREIGN KEY (resource_class_id)         REFERENCES resource_class(resource_class_id);
ALTER TABLE analysis_base           ADD FOREIGN KEY (resource_class_id)         REFERENCES resource_class(resource_class_id);
ALTER TABLE worker                  ADD FOREIGN KEY (resource_class_id)         REFERENCES resource_class(resource_class_id);

ALTER TABLE job                     ADD FOREIGN KEY (worker_id)                 REFERENCES worker(worker_id)                    ON DELETE CASCADE;
ALTER TABLE log_message             ADD FOREIGN KEY (worker_id)                 REFERENCES worker(worker_id)                    ON DELETE CASCADE;
ALTER TABLE job_file                ADD FOREIGN KEY (worker_id)                 REFERENCES worker(worker_id)                    ON DELETE CASCADE;

ALTER TABLE job                     ADD FOREIGN KEY (prev_job_id)               REFERENCES job(job_id)                          ON DELETE CASCADE;
ALTER TABLE job                     ADD FOREIGN KEY (semaphored_job_id)         REFERENCES job(job_id)                          ON DELETE CASCADE;
ALTER TABLE log_message             ADD FOREIGN KEY (job_id)                    REFERENCES job(job_id)                          ON DELETE CASCADE;
ALTER TABLE job_file                ADD FOREIGN KEY (job_id)                    REFERENCES job(job_id)                          ON DELETE CASCADE;
ALTER TABLE accu                    ADD FOREIGN KEY (sending_job_id)            REFERENCES job(job_id)                          ON DELETE CASCADE;
ALTER TABLE accu                    ADD FOREIGN KEY (receiving_job_id)          REFERENCES job(job_id)                          ON DELETE CASCADE;

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=56 WHERE meta_key='hive_sql_schema_version' AND meta_value='55';

