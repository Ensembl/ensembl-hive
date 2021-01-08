-- Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
-- Copyright [2016-2021] EMBL-European Bioinformatics Institute
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

    # relaxing this constraint we allow more than 1 template per from-to-branch combination:
    # (unfortunately, it does not make NULLs unique)

ALTER TABLE dataflow_rule DROP INDEX from_analysis_id;
ALTER TABLE dataflow_rule ADD UNIQUE KEY (from_analysis_id, to_analysis_url, branch_code, input_id_template(512));
