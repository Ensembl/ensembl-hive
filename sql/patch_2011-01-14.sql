-- Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
-- Copyright [2016-2022] EMBL-European Bioinformatics Institute
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

# Extend several fields in analysis to 255 characters:

ALTER TABLE analysis MODIFY COLUMN module       VARCHAR(255);
ALTER TABLE analysis MODIFY COLUMN db_file      VARCHAR(255);
ALTER TABLE analysis MODIFY COLUMN program      VARCHAR(255);
ALTER TABLE analysis MODIFY COLUMN program_file VARCHAR(255);

ALTER TABLE meta DROP INDEX species_key_value_idx;
ALTER TABLE meta DROP INDEX species_value_idx;
ALTER TABLE meta MODIFY COLUMN meta_value TEXT;
ALTER TABLE meta ADD UNIQUE KEY species_key_value_idx (species_id,meta_key,meta_value(255));
ALTER TABLE meta ADD        KEY species_value_idx (species_id,meta_value(255));

