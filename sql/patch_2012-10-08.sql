
# replace unique keys with proper primary keys in two tables (BaseAdaptor needs this) :

ALTER TABLE analysis_stats DROP KEY `analysis_id`, ADD PRIMARY KEY (analysis_id);
ALTER TABLE job_file DROP KEY `job_retry`, ADD PRIMARY KEY (job_id, retry);

