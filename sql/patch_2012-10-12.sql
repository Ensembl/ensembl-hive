
# allow the analysis_id to be NULL before specialization:

ALTER TABLE worker MODIFY COLUMN analysis_id int(10) unsigned DEFAULT NULL;

# since it is a life-long property of the worker, let's keep it in the DB:

ALTER TABLE worker ADD COLUMN    resource_class_id   int(10) unsigned NOT NULL;
