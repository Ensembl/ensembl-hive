
-- ---------------------------------------------------------------------------------------------------
-- Create   `role` table
-- Populate it by recreating the timeline of respecialization events from log_message and worker tables.
-- Copy     all the data from meta to pipeline_wide_parameters
-- Add      `log_message`.role_id column
-- FKeys    to establish a practical link via `role` table
-- Replace  some functions and procedures to work with the new `role` table
-- ---------------------------------------------------------------------------------------------------

\set expected_version 59

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

    -- Adding a new table for tracking Roles of multirole Workers:
CREATE TABLE role (
    role_id                 SERIAL PRIMARY KEY,
    worker_id               INTEGER     NOT NULL,
    analysis_id             INTEGER     NOT NULL,
    when_started            TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    when_finished           TIMESTAMP            DEFAULT NULL,
    attempted_jobs          INTEGER     NOT NULL DEFAULT 0,
    done_jobs               INTEGER     NOT NULL DEFAULT 0
);
CREATE        INDEX role_worker_id_idx ON role (worker_id);
CREATE        INDEX role_analysis_id_idx ON role (analysis_id);


    -- new column in log_message to log the role_id:
ALTER TABLE log_message ADD COLUMN role_id INTEGER DEFAULT NULL;

    -- add foreign keys linking the new table to the existing ones:
ALTER TABLE role                    ADD FOREIGN KEY (analysis_id)               REFERENCES analysis_base(analysis_id);
ALTER TABLE role                    ADD FOREIGN KEY (worker_id)                 REFERENCES worker(worker_id)                    ON DELETE CASCADE;
ALTER TABLE log_message             ADD FOREIGN KEY (role_id)                   REFERENCES role(role_id)                        ON DELETE CASCADE;


    -- replace affected views and procedures.
    --
    -- For some reason CREATE OR REPLACE VIEW didn't work,
    -- so we are doing it in two steps:
DROP VIEW IF EXISTS resource_usage_stats;

CREATE VIEW resource_usage_stats AS
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

-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';
