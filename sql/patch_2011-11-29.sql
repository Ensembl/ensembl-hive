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

# Substitute funnel_branch_code column by funnel_dataflow_rule_id column
#
# Please note: this patch will *not* magically convert any data, just patch the schema.
# If you had any semaphored funnels done the old way, you'll have to convert them manually.

ALTER TABLE dataflow_rule DROP COLUMN funnel_branch_code;

ALTER TABLE dataflow_rule ADD COLUMN funnel_dataflow_rule_id  int(10) unsigned default NULL;
