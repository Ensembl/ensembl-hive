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


    -- Relax the restriction that each log_message entry has to have a non-NULL worker_id; allow a NULL there:
ALTER TABLE log_message  MODIFY COLUMN worker_id INTEGER DEFAULT NULL;

    -- Allow log_messages from 'SEMAPHORED' jobs:
ALTER TABLE log_message MODIFY COLUMN status ENUM('UNKNOWN','SPECIALIZATION','COMPILATION','SEMAPHORED','READY','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','PASSED_ON') DEFAULT 'UNKNOWN';

    -- LEFT JOIN with worker so that entries with worker_id=NULL would still be shown:
CREATE OR REPLACE VIEW msg AS
    SELECT a.analysis_id, a.logic_name, m.*
    FROM log_message m
    LEFT JOIN worker w USING (worker_id)
    LEFT JOIN job j ON (j.job_id=m.job_id)
    LEFT JOIN analysis_base a ON (a.analysis_id=j.analysis_id);

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=50 WHERE meta_key='hive_sql_schema_version' AND meta_value='49';

