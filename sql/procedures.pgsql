/*

DESCRIPTION

    Some stored functions, views and procedures used in eHive


LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2022] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

*/


-- show hive progress for analyses (turned into a view to give extra flexibility) ----------------
--
-- Thanks to Greg Jordan for the idea and the original version
--
-- Usage:
--       select * from progress;                                         # the whole table (may take ages to generate, depending on the size of your pipeline)
--       select * from progress where analysis_name_and_id like 'family_blast%';   # only show family_blast-related analyses
--       select * from progress where retry_count>1;                     # only show jobs that have been tried more than once

CREATE OR REPLACE VIEW progress AS
    SELECT a.logic_name || '(' || a.analysis_id || ')' analysis_name_and_id,
        MIN(rc.name) resource_class,
        j.status,
        j.retry_count,
        CASE WHEN j.status IS NULL THEN 0 ELSE count(*) END cnt,
        MIN(job_id) example_job_id
    FROM        analysis_base a
    LEFT JOIN   job j USING (analysis_id)
    LEFT JOIN   resource_class rc ON (a.resource_class_id=rc.resource_class_id)
    GROUP BY a.analysis_id, j.status, j.retry_count
    ORDER BY a.analysis_id, j.status;


-- a convenient view that also incorporates (otherwise redundant) analysis_id and logic_name ------------
--
-- Usage:
--       select * from msg;
--       select * from msg where analysis_id=18;
--       select * from msg where logic_name like 'family_blast%';

CREATE OR REPLACE VIEW msg AS
    SELECT a.analysis_id, a.logic_name, m.*
    FROM log_message m
    LEFT JOIN role USING (role_id)
    LEFT JOIN analysis_base a USING (analysis_id);


-- show the jobs with related semaphores -------
--
-- Usage:
--       select * from semaphore_job;

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


-- show statistics of Workers' real resource usage by analysis -------------------------------------------
--
-- Usage:
--       select * from resource_usage_stats;
--       select * from resource_usage_stats where logic_name like 'family_blast%';

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


-- show the roles that are currently live (grouped by meadow_users, resource_classes and analyses) -------
--
-- Usage:
--       select * from live_roles;
--       select * from live_roles where resource_class_id=12;

CREATE OR REPLACE VIEW live_roles AS
    SELECT w.meadow_user, w.meadow_type, w.resource_class_id, rc.name resource_class_name, r.analysis_id, a.logic_name, count(*) AS num_workers
    FROM worker w
    JOIN role r USING(worker_id)
    LEFT JOIN resource_class rc ON w.resource_class_id=rc.resource_class_id
    LEFT JOIN analysis_base a USING(analysis_id)
    WHERE r.when_finished IS NULL
    GROUP BY w.meadow_user, w.meadow_type, w.resource_class_id, rc.name, r.analysis_id, a.logic_name;

-- show activity of beekeepers in this hive
--
-- Usage:
--       select * from beekeeper_activity;
--
--       -- Find beekeepers that may have disappeared
--       select * from beekeeper_activity
--       where cause_of_death is null
--       and is_overdue;

CREATE OR REPLACE VIEW beekeeper_activity AS
    SELECT b.beekeeper_id, b.meadow_user, b.meadow_host, b.sleep_minutes, b.loop_limit, b.is_blocked,
           b.cause_of_death, COUNT(*) AS loops_executed,
           MAX(lm.when_logged) AS last_heartbeat,
           now() - max(lm.when_logged) AS time_since_last_heartbeat,
           JUSTIFY_INTERVAL( (sleep_minutes * 60|| 'seconds')::interval) -
               (now() - max(lm.when_logged)) < INTERVAL '0'  AS is_overdue
    FROM beekeeper b
    LEFT JOIN log_message lm
    ON b.beekeeper_id = lm.beekeeper_id
    GROUP BY b.beekeeper_id;

-- time an analysis or group of analyses (given by a name pattern) ----------------------------------------
--
-- Usage:
--      SELECT * FROM time_analysis();
--      SELECT * FROM time_analysis('alignment_chains%');

DROP FUNCTION IF EXISTS time_analysis(VARCHAR);
CREATE FUNCTION time_analysis(analyses_pattern VARCHAR DEFAULT '%')
RETURNS TABLE ( still_running BIGINT,
                measured_in_minutes DOUBLE PRECISION,
                measured_in_hours DOUBLE PRECISION,
                measured_in_days DOUBLE PRECISION)
AS $$
    SELECT  COUNT(*)-COUNT(when_finished),
            EXTRACT(EPOCH FROM (CASE WHEN COUNT(*)>COUNT(when_finished) THEN CURRENT_TIMESTAMP ELSE max(when_finished) END) - min(when_started))/60,
            EXTRACT(EPOCH FROM (CASE WHEN COUNT(*)>COUNT(when_finished) THEN CURRENT_TIMESTAMP ELSE max(when_finished) END) - min(when_started))/3600,
            EXTRACT(EPOCH FROM (CASE WHEN COUNT(*)>COUNT(when_finished) THEN CURRENT_TIMESTAMP ELSE max(when_finished) END) - min(when_started))/3600/24
    FROM role JOIN analysis_base USING (analysis_id)
    WHERE logic_name like $1;
$$ LANGUAGE SQL;

