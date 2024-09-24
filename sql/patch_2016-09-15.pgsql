-- See the NOTICE file distributed with this work for additional information
-- regarding copyright ownership.
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

\set expected_version 81

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

ALTER TYPE beekeeper_stat RENAME TO beekeeper_stat__;
CREATE TYPE beekeeper_cod AS ENUM('ANALYSIS_FAILED', 'DISAPPEARED', 'JOB_FAILED', 'LOOP_LIMIT', 'NO_WORK', 'TASK_FAILED');
ALTER TABLE beekeeper ALTER COLUMN status DROP NOT NULL;
UPDATE beekeeper SET status = NULL WHERE status = 'ALIVE';
ALTER TABLE beekeeper ALTER COLUMN status TYPE beekeeper_cod USING status::text::beekeeper_cod;
ALTER TABLE beekeeper RENAME status TO cause_of_death;
DROP TYPE beekeeper_stat__;

CREATE OR REPLACE VIEW beekeeper_activity AS
    SELECT b.beekeeper_id, b.meadow_host, b.sleep_minutes, b.loop_limit,
           b.cause_of_death, COUNT(*) AS loops_executed,
           MAX(lm.when_logged) AS last_heartbeat,
           now() - max(lm.when_logged) AS time_since_last_heartbeat,
           JUSTIFY_INTERVAL( (sleep_minutes * 60|| 'seconds')::interval) -
               (now() - max(lm.when_logged)) < INTERVAL '0'  AS is_overdue
    FROM beekeeper b
    LEFT JOIN log_message lm
    ON b.beekeeper_id = lm.beekeeper_id
    GROUP BY b.beekeeper_id;

-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';
INSERT INTO hive_meta (meta_key, meta_value) SELECT 'patched_to_' || meta_value, CURRENT_TIMESTAMP FROM hive_meta WHERE meta_key = 'hive_sql_schema_version';
