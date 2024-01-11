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

\set expected_version 80

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

CREATE TYPE beekeeper_stat AS ENUM ('ALIVE', 'ANALYSIS_FAILED', 'DISAPPEARED', 'JOB_FAILED', 'LOOP_LIMIT', 'NO_WORK', 'TASK_FAILED');
CREATE TYPE beekeeper_lu   AS ENUM ('ANALYSIS_FAILURE', 'FOREVER', 'JOB_FAILURE', 'NO_WORK');
CREATE TABLE beekeeper (
       beekeeper_id             SERIAL          PRIMARY KEY,
       meadow_host              VARCHAR(255)    NOT NULL,
       meadow_user              VARCHAR(255)    NOT NULL,
       process_id               INTEGER         NOT NULL,
       status                   beekeeper_stat  NOT NULL,
       sleep_minutes            REAL            NULL,
       analyses_pattern         TEXT            NULL,
       loop_limit               INTEGER         NULL,
       loop_until               beekeeper_lu    NOT NULL,
       options                  TEXT            NULL,
       meadow_signatures        TEXT            NULL
);
CREATE INDEX ON beekeeper (meadow_host, meadow_user, process_id);

ALTER TABLE worker ADD COLUMN beekeeper_id INTEGER DEFAULT NULL,
      ADD FOREIGN KEY (beekeeper_id) REFERENCES beekeeper(beekeeper_id) ON DELETE CASCADE;

ALTER TABLE log_message ADD COLUMN beekeeper_id INTEGER DEFAULT NULL,
      ADD FOREIGN KEY (beekeeper_id) REFERENCES beekeeper(beekeeper_id) ON DELETE CASCADE;
CREATE INDEX ON log_message (beekeeper_id);

-- Same SELECT but the resulting view has different columns since log_message has changed
CREATE OR REPLACE VIEW msg AS
    SELECT a.analysis_id, a.logic_name, m.*
    FROM log_message m
    LEFT JOIN role USING (role_id)
    LEFT JOIN analysis_base a USING (analysis_id);

-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';
INSERT INTO hive_meta (meta_key, meta_value) SELECT 'patched_to_' || meta_value, CURRENT_TIMESTAMP FROM hive_meta WHERE meta_key = 'hive_sql_schema_version';
