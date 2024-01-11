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


    -- Rename resource_description.parameters to stop confusion with job/analysis/pipeline parameters:
ALTER TABLE resource_description RENAME COLUMN parameters TO submission_cmd_args;

    -- Add resource-specific worker_cmd_args :
ALTER TABLE resource_description ADD COLUMN worker_cmd_args VARCHAR(255) NOT NULL DEFAULT '';

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=54 WHERE meta_key='hive_sql_schema_version' AND meta_value='53';

