/*

DESCRIPTION

    Some stored functions, views and procedures used in eHive


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


-- show hive progress for analyses (turned into a view to give extra flexibility) ----------------
--
-- Thanks to Greg Jordan for the idea and the original version
--
-- Usage:
--       select * from progress;                                         # the whole table (may take ages to generate, depending on the size of your pipeline)
--       select * from progress where logic_name like 'family_blast%';   # only show family_blast-related analyses
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
           count(*) workers,
           min(mem_megs) AS min_mem_megs, round(avg(mem_megs)*100)/100 AS avg_mem_megs, max(mem_megs) AS max_mem_megs,
           min(swap_megs) AS min_swap_megs, round(avg(swap_megs)*100)/100 AS avg_swap_megs, max(swap_megs) AS max_swap_megs
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
    SELECT w.meadow_user, w.meadow_type, w.resource_class_id, rc.name resource_class_name, r.analysis_id, a.logic_name, count(*)
    FROM worker w
    JOIN role r USING(worker_id)
    LEFT JOIN resource_class rc ON w.resource_class_id=rc.resource_class_id
    LEFT JOIN analysis_base a USING(analysis_id)
    WHERE r.when_finished IS NULL
    GROUP BY w.meadow_user, w.meadow_type, w.resource_class_id, rc.name, r.analysis_id, a.logic_name;


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

