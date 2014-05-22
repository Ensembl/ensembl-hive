/*

DESCRIPTION

    Some stored functions, views and procedures used in eHive


LICENSE

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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
    LEFT JOIN job j ON (j.job_id=m.job_id)
    LEFT JOIN analysis_base a ON (a.analysis_id=j.analysis_id);


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

