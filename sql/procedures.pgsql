-- ------------------------------------------------------------------------
--
-- Some stored functions, views and procedures used in hive:
--


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
    LEFT JOIN worker w USING (worker_id)
    LEFT JOIN job j ON (j.job_id=m.job_id)
    LEFT JOIN analysis_base a ON (a.analysis_id=j.analysis_id);

