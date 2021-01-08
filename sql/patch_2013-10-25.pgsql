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

    -- first drop the views that depend on these types

DROP VIEW progress;
DROP VIEW msg;

    -- extend all VARCHAR fields to 255 (this will not affect neither storage nor performance) :

ALTER TABLE analysis_base           ALTER COLUMN logic_name  SET DATA TYPE VARCHAR(255);
ALTER TABLE analysis_base           ALTER COLUMN meadow_type SET DATA TYPE VARCHAR(255);
ALTER TABLE resource_class          ALTER COLUMN name        SET DATA TYPE VARCHAR(255);
ALTER TABLE resource_description    ALTER COLUMN meadow_type SET DATA TYPE VARCHAR(255);
ALTER TABLE hive_meta               ALTER COLUMN meta_key    SET DATA TYPE VARCHAR(255);
ALTER TABLE meta                    ALTER COLUMN meta_key    SET DATA TYPE VARCHAR(255);
ALTER TABLE worker                  ALTER COLUMN meadow_type SET DATA TYPE VARCHAR(255);
ALTER TABLE worker                  ALTER COLUMN meadow_name SET DATA TYPE VARCHAR(255);
ALTER TABLE worker                  ALTER COLUMN host        SET DATA TYPE VARCHAR(255);
ALTER TABLE worker                  ALTER COLUMN process_id  SET DATA TYPE VARCHAR(255);

    -- recreate the views
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

CREATE OR REPLACE VIEW msg AS
    SELECT a.analysis_id, a.logic_name, m.*
    FROM log_message m
    LEFT JOIN worker w USING (worker_id)
    LEFT JOIN job j ON (j.job_id=m.job_id)
    LEFT JOIN analysis_base a ON (a.analysis_id=j.analysis_id);

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=53 WHERE meta_key='hive_sql_schema_version' AND meta_value='52';

