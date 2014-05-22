
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


    -- replace affected views and procedures:
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


    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=60 WHERE meta_key='hive_sql_schema_version' AND meta_value='59';

