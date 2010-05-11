    # Adding optional input_id_template to the dataflow_rule table:
ALTER tABLE dataflow_rule ADD COLUMN input_id_template TEXT DEFAULT NULL;

    # Curiously enough, this bug has never been discovered before, probably due to underuse of dataflow mechanism:
ALTER TABLE dataflow_rule DROP INDEX from_analysis_id;
ALTER TABLE dataflow_rule ADD UNIQUE KEY (from_analysis_id, to_analysis_url, branch_code);
