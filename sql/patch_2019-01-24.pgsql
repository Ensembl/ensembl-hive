-- Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
-- Copyright [2016-2024] EMBL-European Bioinformatics Institute
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.


-- ---------------------------------------------------------------------------------------------------

\set expected_version 94

\set ON_ERROR_STOP on

    -- warn that we detected the schema version mismatch:
SELECT ('The patch only applies to schema version '
    || CAST(:expected_version AS VARCHAR)
    || ', but the current schema version is '
    || meta_value
    || ', so skipping the rest.') as incompatible_msg
    FROM hive_meta WHERE meta_key='hive_sql_schema_version' AND meta_value!=CAST(:expected_version AS VARCHAR);

    -- cause division by zero only if current version differs from the expected one:
INSERT INTO hive_meta (meta_key, meta_value)
   SELECT 'this_should_never_be_inserted', 1 FROM hive_meta WHERE 1 != 1/CAST( (meta_key!='hive_sql_schema_version' OR meta_value=CAST(:expected_version AS VARCHAR)) AS INTEGER );

SELECT ('The patch seems to be compatible with schema version '
    || CAST(:expected_version AS VARCHAR)
    || ', applying the patch...') AS compatible_msg;


-- ----------------------------------<actual_patch> -------------------------------------------------

DROP VIEW IF EXISTS semaphore_job;
CREATE OR REPLACE VIEW semaphore_job AS
    SELECT
        job.job_id AS job_id,
        job.prev_job_id AS prev_job_id,
        job.analysis_id AS analysis_id,
        job.input_id AS input_id,
        job.param_id_stack AS param_id_stack,
        job.accu_id_stack AS accu_id_stack,
        job.role_id AS role_id,
        job.status AS status,
        job.retry_count AS retry_count,
        job.when_completed AS when_completed,
        job.runtime_msec AS runtime_msec,
        job.query_count AS query_count,
        semaphore.local_jobs_counter AS local_jobs_counter,
        semaphore.remote_jobs_counter AS remote_jobs_counter,
        semaphore.dependent_semaphore_url AS dependent_semaphore_url
    FROM job JOIN semaphore
    ON semaphore.dependent_job_id = job.job_id;


DROP VIEW resource_usage_stats;
CREATE OR REPLACE VIEW resource_usage_stats AS
    SELECT a.logic_name || '(' || a.analysis_id || ')' analysis,
           w.meadow_type,
           rc.name || '(' || rc.resource_class_id || ')' resource_class,
           u.exit_status,
           count(*) AS num_workers,
           min(mem_megs) AS min_mem_megs, round(avg(mem_megs)*100)/100 AS avg_mem_megs, max(mem_megs) AS max_mem_megs,
           round(min(cpu_sec/lifespan_sec)*100)/100 AS min_cpu_usage, round(avg(cpu_sec/lifespan_sec)*100)/100 AS avg_cpu_usage, round(max(cpu_sec/lifespan_sec)*100)/100 AS max_cpu_usage
    FROM resource_class rc
    JOIN analysis_base a USING(resource_class_id)
    LEFT JOIN role r USING(analysis_id)
    LEFT JOIN worker w USING(worker_id)
    LEFT JOIN worker_resource_usage u USING (worker_id)
    GROUP BY a.analysis_id, w.meadow_type, rc.resource_class_id, u.exit_status
    ORDER BY a.analysis_id, w.meadow_type, rc.resource_class_id, u.exit_status;

DROP VIEW live_roles;
CREATE OR REPLACE VIEW live_roles AS
    SELECT w.meadow_user, w.meadow_type, w.resource_class_id, rc.name resource_class_name, r.analysis_id, a.logic_name, count(*) AS num_workers
    FROM worker w
    JOIN role r USING(worker_id)
    LEFT JOIN resource_class rc ON w.resource_class_id=rc.resource_class_id
    LEFT JOIN analysis_base a USING(analysis_id)
    WHERE r.when_finished IS NULL
    GROUP BY w.meadow_user, w.meadow_type, w.resource_class_id, rc.name, r.analysis_id, a.logic_name;


-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one and register the patch:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';
INSERT INTO hive_meta (meta_key, meta_value) SELECT 'patched_to_' || meta_value, CURRENT_TIMESTAMP FROM hive_meta WHERE meta_key = 'hive_sql_schema_version';
