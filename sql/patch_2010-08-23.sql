
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

