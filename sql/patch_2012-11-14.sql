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

    # add 'SPECIALIZATION' both to worker.status and job_message.status (as job_message now also records messages from jobless workers) :
ALTER TABLE worker MODIFY COLUMN status           enum('SPECIALIZATION','COMPILATION','READY','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','DEAD') DEFAULT 'READY' NOT NULL;
ALTER TABLE job_message MODIFY COLUMN status      enum('UNKNOWN','SPECIALIZATION','COMPILATION','READY','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','PASSED_ON') DEFAULT 'UNKNOWN';

    # add 'SEE_MSG' cause_of_death for causes that cannot be expressed in one word:
ALTER TABLE worker MODIFY COLUMN cause_of_death   enum('NO_WORK', 'JOB_LIMIT', 'HIVE_OVERLOAD', 'LIFESPAN', 'CONTAMINATED', 'KILLED_BY_USER', 'MEMLIMIT', 'RUNLIMIT', 'SEE_MSG', 'UNKNOWN') DEFAULT NULL;

