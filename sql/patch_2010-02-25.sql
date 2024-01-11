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

# adding resource requirements:

ALTER TABLE analysis_stats ADD COLUMN rc_id int(10) unsigned default 0 NOT NULL;
ALTER TABLE analysis_stats_monitor ADD COLUMN rc_id int(10) unsigned default 0 NOT NULL;

CREATE TABLE resource_description (
    rc_id                 int(10) unsigned DEFAULT 0 NOT NULL,
    meadow_type           enum('LSF', 'LOCAL') DEFAULT 'LSF' NOT NULL,
    parameters            varchar(255) DEFAULT '' NOT NULL,
    description           varchar(255),
    PRIMARY KEY(rc_id, meadow_type)
) ENGINE=InnoDB;

