
# In case of running runWorker.pl manually it is better not to set the resource_class_id in the Worker:

ALTER TABLE worker MODIFY COLUMN resource_class_id   int(10) unsigned DEFAULT NULL;
