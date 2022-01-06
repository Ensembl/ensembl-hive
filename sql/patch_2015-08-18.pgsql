-- Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
-- Copyright [2016-2022] EMBL-European Bioinformatics Institute
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

\set expected_version 74

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

-- Need to drop and recreate progress because otherwise we get
--    ERROR:  cannot alter type of a column used by a view or rule

DROP VIEW progress;

ALTER TABLE  job  ALTER COLUMN  status  SET DATA TYPE  TEXT;    -- expected values: 'SEMAPHORED','READY','CLAIMED','COMPILATION','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_HEALTHCHECK','POST_CLEANUP','DONE','FAILED','PASSED_ON'
ALTER TABLE  job  ALTER COLUMN  status  SET DEFAULT 'READY';

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


-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';
