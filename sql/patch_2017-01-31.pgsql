-- Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
-- Copyright [2016-2021] EMBL-European Bioinformatics Institute
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

\set expected_version 88

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

CREATE TABLE semaphore (
    semaphore_id                SERIAL PRIMARY KEY,
    local_jobs_counter          INTEGER             DEFAULT 0,
    remote_jobs_counter         INTEGER             DEFAULT 0,
    dependent_job_id            INTEGER             DEFAULT NULL,                                   -- Both should never be NULLs at the same time,
    dependent_semaphore_url     VARCHAR(255)        DEFAULT NULL,                                   --  we expect either one or the other to be set.

    UNIQUE (dependent_job_id)                                                                       -- make sure two semaphores do not block the same job
);


ALTER TABLE job ADD COLUMN controlled_semaphore_id INTEGER  DEFAULT NULL;


INSERT INTO semaphore (semaphore_id, local_jobs_counter, dependent_job_id)
( SELECT fan.semaphored_job_id, count(*), fan.semaphored_job_id
    FROM job fan
    JOIN job funnel
      ON (fan.semaphored_job_id=funnel.job_id)
GROUP BY fan.semaphored_job_id
);


UPDATE job SET controlled_semaphore_id = semaphored_job_id;


ALTER TABLE job     DROP CONSTRAINT job_semaphored_job_id_fkey;
ALTER TABLE job     DROP COLUMN semaphore_count;
ALTER TABLE job     DROP COLUMN semaphored_job_id;


ALTER TABLE semaphore               ADD CONSTRAINT  semaphore_dependent_job_id_fkey     FOREIGN KEY (dependent_job_id)          REFERENCES job(job_id)              ON DELETE CASCADE;
ALTER TABLE job                     ADD CONSTRAINT job_controlled_semaphore_id_fkey     FOREIGN KEY (controlled_semaphore_id)   REFERENCES semaphore(semaphore_id)  ON DELETE CASCADE;

-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one and register the patch:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';
INSERT INTO hive_meta (meta_key, meta_value) SELECT 'patched_to_' || meta_value, CURRENT_TIMESTAMP FROM hive_meta WHERE meta_key = 'hive_sql_schema_version';
