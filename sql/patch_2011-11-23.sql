# extend the dataflow_rule table to add an optional semaphored funnel branch:

ALTER TABLE dataflow_rule ADD COLUMN funnel_branch_code int(10) default NULL;
