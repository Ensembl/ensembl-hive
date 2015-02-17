
-- ---------------------------------------------------------------------------------------------------
-- Create   `worker_resource_usage` table to be a meadow-agnostic replacement for `lsf_report` (no data is copied over)
-- FKey     links `worker_resource_usage` to `worker` via worker_id (ON DELETE CASCADE)
-- Create   `resource_usage_stats` view as a meadow-agnostic substitute for `lsf_usage` view
-- Key      on `worker` table to speed up the worker_id<->process_id mapping
-- ---------------------------------------------------------------------------------------------------

\set expected_version 58

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

    -- add a new meadow-agnostic table for tracking the resource usage:
CREATE TABLE worker_resource_usage (
    worker_id               INTEGER         NOT NULL,
    exit_status             VARCHAR(255)    DEFAULT NULL,
    mem_megs                FLOAT           DEFAULT NULL,
    swap_megs               FLOAT           DEFAULT NULL,
    pending_sec             FLOAT           DEFAULT NULL,
    cpu_sec                 FLOAT           DEFAULT NULL,
    lifespan_sec            FLOAT           DEFAULT NULL,
    exception_status        VARCHAR(255)    DEFAULT NULL,

    PRIMARY KEY (worker_id)
);

    -- add a foreign key:
ALTER TABLE worker_resource_usage   ADD FOREIGN KEY (worker_id)                 REFERENCES worker(worker_id)                    ON DELETE CASCADE;

    -- add a stats view over the new table:
CREATE OR REPLACE VIEW resource_usage_stats AS
    SELECT a.logic_name || '(' || a.analysis_id || ')' analysis,
           w.meadow_type,
           rc.name || '(' || rc.resource_class_id || ')' resource_class,
           count(*) workers,
           min(mem_megs) AS min_mem_megs, avg(mem_megs) AS avg_mem_megs, max(mem_megs) AS max_mem_megs,
           min(swap_megs) AS min_swap_megs, avg(swap_megs) AS avg_swap_megs, max(swap_megs) AS max_swap_megs
    FROM analysis_base a
    JOIN resource_class rc USING(resource_class_id)
    LEFT JOIN worker w USING(analysis_id)
    LEFT JOIN worker_resource_usage USING (worker_id)
    GROUP BY analysis_id, w.meadow_type, rc.resource_class_id
    ORDER BY analysis_id, w.meadow_type;

    -- add a new key to worker table to speed up mapping between process_id and worker_id:
CREATE        INDEX ON worker (meadow_type, meadow_name, process_id);

-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';
