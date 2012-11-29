    # renaming job_message into a more generic log_message:

CREATE TABLE log_message (
  log_message_id            int(10) NOT NULL AUTO_INCREMENT,
  job_id                    int(10) DEFAULT NULL,
  worker_id                 int(10) unsigned NOT NULL,
  time                      timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  retry                     int(10) DEFAULT NULL,
  status                    enum('UNKNOWN','SPECIALIZATION','COMPILATION','READY','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','PASSED_ON') DEFAULT 'UNKNOWN',
  msg                       text,
  is_error                  TINYINT,

  PRIMARY KEY               (log_message_id),
  INDEX worker_id           (worker_id),
  INDEX job_id              (job_id)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;

INSERT INTO log_message (log_message_id, job_id, worker_id, time, retry, status, msg, is_error) SELECT * from job_message;

CREATE OR REPLACE VIEW msg AS
    SELECT a.analysis_id, a.logic_name, m.*
    FROM log_message m
    JOIN worker w USING (worker_id)
    LEFT JOIN analysis_base a ON (a.analysis_id=w.analysis_id)
    LEFT JOIN job j ON (j.job_id=m.job_id);

