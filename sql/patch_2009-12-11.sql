# renaming hive_id into worker_id throughout the schema:

ALTER TABLE hive CHANGE COLUMN hive_id worker_id int(10) NOT NULL AUTO_INCREMENT;
ALTER TABLE analysis_job CHANGE COLUMN hive_id worker_id int(10) NOT NULL;
ALTER TABLE analysis_job_file CHANGE COLUMN hive_id worker_id int(10) NOT NULL;

    # there seems to be no way to rename an index
ALTER TABLE analysis_job DROP INDEX hive_id;
ALTER TABLE analysis_job ADD INDEX (worker_id);

    # there seems to be no way to rename an index
ALTER TABLE analysis_job_file DROP INDEX hive_id;
ALTER TABLE analysis_job_file ADD INDEX (worker_id);

