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


## Introduce two more states, 'PRE_CLEANUP' (conditional, to clean up after previous failed run) and 'POST_CLEANUP' (unconditional, to clean up after the current run)

ALTER TABLE worker      MODIFY COLUMN status enum('READY','COMPILATION','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','DEAD') DEFAULT 'READY' NOT NULL;
ALTER TABLE job         MODIFY COLUMN status enum('READY','BLOCKED','CLAIMED','COMPILATION','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','DONE','FAILED','PASSED_ON') DEFAULT 'READY' NOT NULL;
ALTER TABLE job_message MODIFY COLUMN status enum('UNKNOWN','COMPILATION','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','PASSED_ON') DEFAULT 'UNKNOWN';

