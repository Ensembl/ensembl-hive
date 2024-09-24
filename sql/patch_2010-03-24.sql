-- See the NOTICE file distributed with this work for additional information
-- regarding copyright ownership.
-- 
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
--      http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

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

