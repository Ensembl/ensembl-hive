-- Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
-- Copyright [2016-2020] EMBL-European Bioinformatics Institute
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

    # a new limiter column for the scheduler:
ALTER TABLE analysis_base ADD COLUMN analysis_capacity int(10) DEFAULT NULL;

    # allow NULL to be a valid value for hive_capacity (however not yet default) :
ALTER TABLE analysis_stats          MODIFY COLUMN hive_capacity int(10) DEFAULT 1;
ALTER TABLE analysis_stats_monitor  MODIFY COLUMN hive_capacity int(10) DEFAULT 1;
