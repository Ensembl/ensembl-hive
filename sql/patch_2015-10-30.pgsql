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


-- ---------------------------------------------------------------------------------------------------

\set expected_version 75

\set ON_ERROR_STOP on

    -- warn that we detected the schema version mismatch:
SELECT ('The patch only applies to schema version '
    || CAST(:expected_version AS VARCHAR)
    || ', but the current schema version is '
    || meta_value
    || ', so skipping the rest.') as incompatible_msg
    FROM hive_meta WHERE meta_key='hive_sql_schema_version' AND meta_value!=CAST(:expected_version AS VARCHAR);

    -- cause division by zero only if current version differs from the expected one:
INSERT INTO hive_meta (meta_key, meta_value)
   SELECT 'this_should_never_be_inserted', 1 FROM hive_meta WHERE 1 != 1/CAST( (meta_key!='hive_sql_schema_version' OR meta_value=CAST(:expected_version AS VARCHAR)) AS INTEGER );

SELECT ('The patch seems to be compatible with schema version '
    || CAST(:expected_version AS VARCHAR)
    || ', applying the patch...') AS compatible_msg;


-- ----------------------------------<actual_patch> -------------------------------------------------

-- dropping the UNIQUE constraint from the original dataflow_rule table:
ALTER TABLE dataflow_rule DROP CONSTRAINT dataflow_rule_from_analysis_id_branch_code_funnel_dataflow__key;

-- creating new table to hold the condition + dataflow target parameters:
CREATE TABLE dataflow_target (
    source_dataflow_rule_id INTEGER     NOT NULL,
    on_condition            VARCHAR(255)          DEFAULT NULL,
    input_id_template       TEXT                  DEFAULT NULL,
    to_analysis_url         VARCHAR(255) NOT NULL DEFAULT '',       -- to be renamed 'target_url'

    UNIQUE (source_dataflow_rule_id, on_condition, input_id_template, to_analysis_url)
);

-- adding a foreign key between targets and rules:
ALTER TABLE dataflow_target         ADD FOREIGN KEY (source_dataflow_rule_id)   REFERENCES dataflow_rule(dataflow_rule_id);

-- transferring the data:
INSERT INTO dataflow_target (source_dataflow_rule_id, on_condition, input_id_template, to_analysis_url)
    SELECT dataflow_rule_id, NULL, input_id_template, to_analysis_url FROM dataflow_rule;

-- removing the duplicated columns:
ALTER TABLE dataflow_rule DROP COLUMN to_analysis_url;
ALTER TABLE dataflow_rule DROP COLUMN input_id_template;



-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';
