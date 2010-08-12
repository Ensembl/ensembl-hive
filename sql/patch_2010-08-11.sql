
## A new table was introduced to track jobs' termination error messages:

CREATE TABLE job_error (
  analysis_job_id           int(10) NOT NULL,
  worker_id                 int(10) NOT NULL,
  died                      timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  retry_count               int(10) DEFAULT 0 NOT NULL,
  status                    enum('UNKNOWN','COMPILATION','GET_INPUT','RUN','WRITE_OUTPUT') DEFAULT 'UNKNOWN',
  error_msg                 text,

  PRIMARY KEY               (analysis_job_id, worker_id, died),
  INDEX worker_id           (worker_id),
  INDEX analysis_job_id     (analysis_job_id)
) ENGINE=InnoDB;

## Workers now do not die by default when the job that was being run dies.
## However a job can signal to the Worker that the latter's life is not worth living anymore.
## The Worker then dies with cause_of_death='CONTAMINATED'

ALTER TABLE hive MODIFY COLUMN cause_of_death enum('', 'NO_WORK', 'JOB_LIMIT', 'HIVE_OVERLOAD', 'LIFESPAN', 'CONTAMINATED', 'FATALITY') DEFAULT '' NOT NULL;

## A new 'COMPILATION' state was added to both Worker and Job:

ALTER TABLE hive MODIFY COLUMN status         enum('READY','COMPILATION','GET_INPUT','RUN','WRITE_OUTPUT','DEAD') DEFAULT 'READY' NOT NULL;
ALTER TABLE analysis_job MODIFY COLUMN status enum('READY','BLOCKED','CLAIMED','COMPILATION','GET_INPUT','RUN','WRITE_OUTPUT','DONE','FAILED') DEFAULT 'READY' NOT NULL;

## Time flies... :

DELETE FROM meta WHERE meta_key='schema_version';
INSERT IGNORE INTO meta (species_id, meta_key, meta_value) VALUES (NULL, "schema_version", "59");
