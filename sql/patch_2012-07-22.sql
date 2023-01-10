-- Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
-- Copyright [2016-2023] EMBL-European Bioinformatics Institute
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


## At last rename GET_INPUT into FETCH_INPUT for consistency between the schema and the code (it seems to be harder to patch all the accumulated code):

ALTER TABLE worker      MODIFY COLUMN status enum('READY','COMPILATION','FETCH_INPUT','RUN','WRITE_OUTPUT','DEAD') DEFAULT 'READY' NOT NULL;
ALTER TABLE job         MODIFY COLUMN status enum('READY','BLOCKED','CLAIMED','COMPILATION','FETCH_INPUT','RUN','WRITE_OUTPUT','DONE','FAILED','PASSED_ON') DEFAULT 'READY' NOT NULL;
ALTER TABLE job_message MODIFY COLUMN status enum('UNKNOWN', 'COMPILATION', 'FETCH_INPUT', 'RUN', 'WRITE_OUTPUT', 'PASSED_ON') DEFAULT 'UNKNOWN';

