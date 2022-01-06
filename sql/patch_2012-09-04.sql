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


# Substitute the legacy 'analysis' table with the slimmer version 'analysis_base',
# but do not bother deleting the original table in the patch
# because of the many already established foreign key relationships.

CREATE TABLE analysis_base (
  analysis_id                 int(10) unsigned NOT NULL AUTO_INCREMENT,
  logic_name                  VARCHAR(40) NOT NULL,
  module                      VARCHAR(255),
  parameters                  TEXT,

  PRIMARY KEY (analysis_id),
  UNIQUE KEY logic_name_idx (logic_name)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;

INSERT INTO analysis_base (analysis_id, logic_name, module, parameters) SELECT analysis_id, logic_name, module, parameters FROM analysis;

