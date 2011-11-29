# Substitute funnel_branch_code column by funnel_dataflow_rule_id column
#
# Please note: this patch will *not* magically convert any data, just patch the schema.
# If you had any semaphored funnels done the old way, you'll have to convert them manually.

ALTER TABLE dataflow_rule DROP COLUMN funnel_branch_code;

ALTER TABLE dataflow_rule ADD COLUMN funnel_dataflow_rule_id  int(10) unsigned default NULL;
