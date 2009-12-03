############################################################################################################################
#
#    Bio::EnsEMBL::Hive::RunnableDB::LongMult is an example eHive pipeline that demonstates the following features:
#
# A) A pipeline can have multiple analyses (this one has three: 'start', 'part_multiply' and 'add_together').
#
# B) A job of one analysis can create jobs of another analysis (one 'start' job creates up to 8 'part_multiply' jobs).
#
# C) A job of one analysis can "flow the data" into another analysis (a 'start' job "flows into" an 'add_together' job).
#
# D) Execution of one analysis can be blocked until all jobs of another analysis have been successfully completed
#    ('add_together' is blocked both by 'start' and 'part_multiply').
#
# E) As filesystems are frequently a bottleneck for big pipelines, it is advised that eHive processes store intermediate
#    and final results in a database (in this pipeline, 'intermediate_result' and 'final_result' tables are used).
#
############################################################################################################################

# 0. Cache MySQL connection parameters in a variable (they will work as eHive connection parameters as well) :
export MYCONN="--host=hostname --port=port_number --user=username --password=secret"

# 1. Create an empty database:
mysql $MYCONN -e 'DROP DATABASE IF EXISTS long_mult_test'
mysql $MYCONN -e 'CREATE DATABASE long_mult_test'

# 2. Create eHive infrastructure:
mysql $MYCONN long_mult_test <~lg4/work/ensembl-hive/sql/tables.sql

# 3. Create analyses/control_rules/dataflow_rules of the LongMult pipeline:
mysql $MYCONN long_mult_test <~lg4/work/ensembl-hive/sql/create_long_mult.sql

# 4. "Load" the pipeline with a multiplication task:
mysql $MYCONN long_mult_test <~lg4/work/ensembl-hive/sql/load_long_mult.sql
#
# or you can add your own task(s). Several tasks can be added at once:
mysql $MYCONN long_mult_test <<EoF
INSERT INTO analysis_job (analysis_id, input_id) VALUES ( 1, "{ 'a_multiplier' => '9750516269', 'b_multiplier' => '327358788' }");
INSERT INTO analysis_job (analysis_id, input_id) VALUES ( 1, "{ 'a_multiplier' => '327358788', 'b_multiplier' => '9750516269' }");
EoF

# 5. Initialize the newly created eHive for the first time:
beekeeper.pl $MYCONN --database=long_mult_test -sync

# 6. You can either execute three individual workers (each picking one analysis of the pipeline):
runWorker.pl $MYCONN --database=long_mult_test
#
#
# ... or run an automatic loop that will run workers for you:
beekeeper.pl $MYCONN --database=long_mult_test -loop

# 7. The results of the computations are to be found in 'final_result' table:
mysql $MYCONN long_mult_test -e 'SELECT * FROM final_result'

# 8. You can add more multiplication tasks by repeating from step 4.

