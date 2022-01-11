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

    # allow job_id and retry to be NULL by default, to make it possible for jobless workers to leave messages:
ALTER TABLE job_message MODIFY COLUMN job_id                    int(10) DEFAULT NULL;
ALTER TABLE job_message MODIFY COLUMN retry                     int(10) DEFAULT NULL;

    # re-route getting analysis_id/logic_name via worker table, so that it would work in the absence of the job:
CREATE OR REPLACE VIEW msg AS
    SELECT a.analysis_id, a.logic_name, m.*
    FROM job_message m
    JOIN worker w USING (worker_id)
    LEFT JOIN analysis_base a ON (a.analysis_id=w.analysis_id)
    LEFT JOIN job j ON (j.job_id=m.job_id);

