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

# renaming hive_id into worker_id throughout the schema:

ALTER TABLE hive CHANGE COLUMN hive_id worker_id int(10) NOT NULL AUTO_INCREMENT;
ALTER TABLE analysis_job CHANGE COLUMN hive_id worker_id int(10) NOT NULL;
ALTER TABLE analysis_job_file CHANGE COLUMN hive_id worker_id int(10) NOT NULL;

    # there seems to be no way to rename an index
ALTER TABLE analysis_job DROP INDEX hive_id;
ALTER TABLE analysis_job ADD INDEX (worker_id);

    # there seems to be no way to rename an index
ALTER TABLE analysis_job_file DROP INDEX hive_id;
ALTER TABLE analysis_job_file ADD INDEX (worker_id);

