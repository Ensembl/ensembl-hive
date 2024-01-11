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

ALTER TABLE analysis_job_file ADD COLUMN retry int(10) default 0 NOT NULL after analysis_job_id, ADD COLUMN hive_id int(10) default 0 NOT NULL after analysis_job_id, drop index analysis_job_id;
CREATE UNIQUE INDEX job_hive_type on analysis_job_file (analysis_job_id, hive_id, type);

