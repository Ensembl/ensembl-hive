    # varchar(80) was too limiting, so let's extend it:

ALTER TABLE worker MODIFY COLUMN log_dir varchar(255) DEFAULT NULL;
