/*

DESCRIPTION

    FOREIGN KEY constraints are listed in a separate file so that they could be optionally switched on or off.

    A nice surprise is that the syntax for defining them is the same for MySQL and PostgreSQL.


LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

*/


ALTER TABLE analysis_ctrl_rule      ADD FOREIGN KEY (ctrled_analysis_id)        REFERENCES analysis_base(analysis_id);
ALTER TABLE analysis_stats          ADD FOREIGN KEY (analysis_id)               REFERENCES analysis_base(analysis_id);
ALTER TABLE analysis_stats_monitor  ADD FOREIGN KEY (analysis_id)               REFERENCES analysis_base(analysis_id);
ALTER TABLE dataflow_rule           ADD FOREIGN KEY (from_analysis_id)          REFERENCES analysis_base(analysis_id);
ALTER TABLE job                     ADD CONSTRAINT  job_analysis_id_fkey        FOREIGN KEY (analysis_id)           REFERENCES analysis_base(analysis_id);
ALTER TABLE role                    ADD FOREIGN KEY (analysis_id)               REFERENCES analysis_base(analysis_id);

ALTER TABLE dataflow_rule           ADD FOREIGN KEY (funnel_dataflow_rule_id)   REFERENCES dataflow_rule(dataflow_rule_id);
ALTER TABLE dataflow_target         ADD FOREIGN KEY (source_dataflow_rule_id)   REFERENCES dataflow_rule(dataflow_rule_id);

ALTER TABLE accu                    ADD FOREIGN KEY (sending_job_id)            REFERENCES job(job_id)                          ON DELETE CASCADE;
ALTER TABLE accu                    ADD FOREIGN KEY (receiving_job_id)          REFERENCES job(job_id)                          ON DELETE CASCADE;
ALTER TABLE job                     ADD CONSTRAINT  job_prev_job_id_fkey        FOREIGN KEY (prev_job_id)           REFERENCES job(job_id)                  ON DELETE CASCADE;
ALTER TABLE job                     ADD CONSTRAINT  job_semaphored_job_id_fkey  FOREIGN KEY (semaphored_job_id)     REFERENCES job(job_id)                  ON DELETE CASCADE;
ALTER TABLE job_file                ADD CONSTRAINT  job_file_job_id_fkey        FOREIGN KEY (job_id)                REFERENCES job(job_id)                  ON DELETE CASCADE;
ALTER TABLE log_message             ADD FOREIGN KEY (job_id)                    REFERENCES job(job_id)                          ON DELETE CASCADE;

ALTER TABLE analysis_base           ADD FOREIGN KEY (resource_class_id)         REFERENCES resource_class(resource_class_id);
ALTER TABLE resource_description    ADD FOREIGN KEY (resource_class_id)         REFERENCES resource_class(resource_class_id);
ALTER TABLE worker                  ADD FOREIGN KEY (resource_class_id)         REFERENCES resource_class(resource_class_id);

ALTER TABLE job                     ADD CONSTRAINT  job_role_id_fkey            FOREIGN KEY (role_id)               REFERENCES role(role_id)                ON DELETE CASCADE;
ALTER TABLE job_file                ADD CONSTRAINT  job_file_role_id_fkey       FOREIGN KEY (role_id)               REFERENCES role(role_id)                ON DELETE CASCADE;
ALTER TABLE log_message             ADD FOREIGN KEY (role_id)                   REFERENCES role(role_id)                        ON DELETE CASCADE;

ALTER TABLE log_message             ADD FOREIGN KEY (worker_id)                 REFERENCES worker(worker_id)                    ON DELETE CASCADE;
ALTER TABLE role                    ADD FOREIGN KEY (worker_id)                 REFERENCES worker(worker_id)                    ON DELETE CASCADE;
ALTER TABLE worker_resource_usage   ADD FOREIGN KEY (worker_id)                 REFERENCES worker(worker_id)                    ON DELETE CASCADE;

