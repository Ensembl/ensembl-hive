# removing the unused branch_code column from analysis_job table:

ALTER TABLE analysis_job DROP COLUMN branch_code;

# Explanation:
#
# Branching using branch_codes is a very important and powerful mechanism,
# but it is completely defined in dataflow_rule table.
#
# branch_code() was at some point a getter/setter method in AnalysisJob,
# but it was only used to pass parameters around in the code (now obsolete),
# and this information was never reflected in the database,
# so analysis_job.branch_code was always 1 no matter what.

