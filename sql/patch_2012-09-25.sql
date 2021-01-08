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


## Dropping 'BLOCKED' state (of Jobs) and adding 'SEMAPHORED' state that should simplify several things.

ALTER TABLE job MODIFY COLUMN status enum('SEMAPHORED','READY','CLAIMED','COMPILATION','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','DONE','FAILED','PASSED_ON') DEFAULT 'READY' NOT NULL;


## Add a more efficient 3-part index instead of older 4-part index (based on the schema/API change):

ALTER TABLE job ADD INDEX analysis_status_retry (analysis_id, status, retry_count);
