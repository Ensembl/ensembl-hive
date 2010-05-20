    # relaxing this constraint we allow more than 1 template per from-to-branch combination:
    # (unfortunately, it does not make NULLs unique)

ALTER TABLE dataflow_rule DROP INDEX from_analysis_id;
ALTER TABLE dataflow_rule ADD UNIQUE KEY (from_analysis_id, to_analysis_url, branch_code, input_id_template(512));
