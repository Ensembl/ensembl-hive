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



-- Split the former resource_description table into two:

-- Create a new auto-incrementing table:
DROP TABLE IF EXISTS resource_class;
CREATE TABLE resource_class (
    resource_class_id   int(10) unsigned NOT NULL AUTO_INCREMENT,     # unique internal id
    name                varchar(40) NOT NULL,

    PRIMARY KEY(resource_class_id),
    UNIQUE KEY(name)
) COLLATE=latin1_swedish_ci ENGINE=InnoDB;

-- Populate it with data from resource_description (unfortunately, id<=0 will be ignored - let's hope they were not used!)
INSERT INTO resource_class (resource_class_id, name) SELECT rc_id, description from resource_description WHERE rc_id>0;

-- The population command may crash if the original "description" contained non-unique values -
--   just fix the original table and reapply the patch.

-- Now drop the name/description column:
ALTER TABLE resource_description DROP COLUMN description;


