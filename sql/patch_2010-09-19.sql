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


## A new 'PASSED_ON' state is added to the Job to make it possible to dataflow from resource-overusing jobs recovered from dead workers:

ALTER TABLE analysis_job MODIFY COLUMN status enum('READY','BLOCKED','CLAIMED','COMPILATION','GET_INPUT','RUN','WRITE_OUTPUT','DONE','FAILED','PASSED_ON') DEFAULT 'READY' NOT NULL;

