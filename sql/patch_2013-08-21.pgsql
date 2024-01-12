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


    -- Documentation claims there is no performance gain from using fixed-width CHAR() types, changing them to TEXT:
ALTER TABLE job ALTER COLUMN input_id SET DATA TYPE TEXT;

    -- Add two new fields to job table to support parameter/accu stacks:
ALTER TABLE job ADD COLUMN param_id_stack          TEXT    NOT NULL DEFAULT '';
ALTER TABLE job ADD COLUMN accu_id_stack           TEXT    NOT NULL DEFAULT '';

    -- Extend the unique constraint to include both new fields:
ALTER TABLE job DROP CONSTRAINT job_input_id_analysis_id_key;
ALTER TABLE job ADD UNIQUE (input_id, param_id_stack, accu_id_stack, analysis_id);

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=52 WHERE meta_key='hive_sql_schema_version' AND meta_value='51';

