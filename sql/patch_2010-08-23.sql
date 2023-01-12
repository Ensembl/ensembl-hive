-- Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
-- Copyright [2016-2023] EMBL-European Bioinformatics Institute
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


# rename job_errors into job_messages to enable succeeding jobs to register their messages

CREATE TABLE job_message (
  analysis_job_id           int(10) NOT NULL,
  worker_id                 int(10) NOT NULL,
  moment                    timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  retry_count               int(10) DEFAULT 0 NOT NULL,
  status                    enum('UNKNOWN', 'COMPILATION', 'GET_INPUT', 'RUN', 'WRITE_OUTPUT') DEFAULT 'UNKNOWN',
  msg                       text,
  is_error                  boolean,

  PRIMARY KEY               (analysis_job_id, worker_id, moment),
  INDEX worker_id           (worker_id),
  INDEX analysis_job_id     (analysis_job_id)
) ENGINE=InnoDB;

INSERT INTO job_message (analysis_job_id, worker_id, moment, retry_count, status, msg, is_error)
    SELECT analysis_job_id, worker_id, died, retry_count, status, error_msg, 1 FROM job_error;

DROP TABLE job_error ;

