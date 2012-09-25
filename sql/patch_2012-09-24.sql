
# Record each Worker's log_dir in worker table (as opposed to recording each Job's output and error files)

ALTER TABLE worker ADD COLUMN log_dir          varchar(80) DEFAULT NULL;

