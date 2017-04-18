================
standaloneJob.pl
================

NAME
----

::

        standaloneJob.pl

DESCRIPTION
-----------

::

        standaloneJob.pl is an eHive component script that
            1. takes in a RunnableDB module,
            2. creates a standalone job outside an eHive database by initializing parameters from command line arguments
            3. and runs that job outside of any eHive database. WARNING: the RunnableDB code may still access databases
               provided as arguments and even harm them !
            4. can optionally dataflow into tables fully defined by URLs
        Naturally, only certain RunnableDB modules can be run using this script, and some database-related functionality will be lost.

        There are several ways of initializing the job parameters:
            1. Module::Name -input_id. The simplest one: just provide a stringified hash
            2. Module::Name -param1 value1 -param2 value2 (...). Enumerate all the arguments on the command-line. ARRAY- and HASH-
               arguments can be passed+parsed too!
            3. -url $ehive_url job_id XXX. The reference to an existing job from which the parameters will be pulled. It is
               a convenient way of gathering all the parameters (the job's input_id, the job's accu, the analysis parameters
               and the pipeline-wide parameters).  Further parameters can be added with -param1 value1 -param2 value2 (...)
               and they take priority over the existing job's parameters. The RunnableDB is also found in the database.
               NOTE: the standaloneJob will *not* interact any further with this eHive database. There won't be any updates
                     to the job, worker, log_message etc tables.

USAGE EXAMPLES
--------------

::

            # Run a job with default parameters, specify module by its package name:
        standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::FailureTest

            # Run the same job with default parameters, but specify module by its relative filename:
        standaloneJob.pl RunnableDB/FailureTest.pm

            # Run a job and re-define some of the default parameters:
        standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::FailureTest -time_RUN=2 -time_WRITE_OUTPUT=3 -state=WRITE_OUTPUT -value=2
        standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::SystemCmd -cmd 'ls -l'
        standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::SystemCmd -input_id "{ 'cmd' => 'ls -l' }"

            # Run a job and re-define its 'db_conn' parameter to allow it to perform some database-related operations:
        standaloneJob.pl RunnableDB/SqlCmd.pm -db_conn mysql://ensadmin:xxxxxxx@127.0.0.1:2912/lg4_compara_families_63 -sql 'INSERT INTO meta (meta_key,meta_value) VALUES ("hello", "world2")'

            # Run a job initialized from the parameters of an existing job topped-up with extra ones.
            # In this particular example the RunnableDB needs a "compara_db" parameter which defaults to the eHive database.
            # Since there is no eHive database here we need to define -compara_db on the command-line
        standaloneJob.pl -url mysql://ensro@compara1.internal.sanger.ac.uk:3306/mm14_pecan_24way_86b -job_id 16781 -compara_db mysql://ensro@compara1.internal.sanger.ac.uk:3306/mm14_pecan_24way_86b

            # Run a job with given parameters, but skip the write_output() step:
        standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::FailureTest -no_write -time_RUN=2 -time_WRITE_OUTPUT=3 -state=WRITE_OUTPUT -value=2

            # Run a job and re-direct its dataflow into tables:
        standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::JobFactory -inputfile foo.txt -delimiter '\t' -column_names "[ 'name', 'age' ]" \
                            -flow_into "{ 2 => ['mysql://ensadmin:xxxxxxx@127.0.0.1:2914/lg4_triggers/foo', 'mysql://ensadmin:xxxxxxx@127.0.0.1:2914/lg4_triggers/bar'] }"

            # Run a Compara job that needs a connection to Compara database:
        standaloneJob.pl Bio::EnsEMBL::Compara::RunnableDB::ObjectFactory -compara_db 'mysql://ensadmin:xxxxxxx@127.0.0.1:2911/sf5_ensembl_compara_master' \
                            -adaptor_name MethodLinkSpeciesSetAdaptor -adaptor_method fetch_all_by_method_link_type -method_param_list "[ 'ENSEMBL_ORTHOLOGUES' ]" \
                            -column_names2getters "{ 'name' => 'name', 'mlss_id' => 'dbID' }" -flow_into "{ 2 => 'mysql://ensadmin:xxxxxxx@127.0.0.1:2914/lg4_triggers/baz' }"

            # Create a new job in a database using automatic dataflow from a database-less Dummy job:
        standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::Dummy -a_multiplier 1234567 -b_multiplier 9876543 \
                            -flow_into "{ 1 => 'mysql://ensadmin:xxxxxxx@127.0.0.1/lg4_long_mult/analysis?logic_name=start' }"

            # Produce a semaphore group of jobs from a database-less DigitFactory job:
        standaloneJob.pl Bio::EnsEMBL::Hive::Examples::LongMult::RunnableDB::DigitFactory -input_id "{ 'a_multiplier' => '2222222222', 'b_multiplier' => '3434343434'}" \
            -flow_into "{ '2->A' => 'mysql://ensadmin:${ENSADMIN_PSW}@127.0.0.1/lg4_long_mult/analysis?logic_name=part_multiply', 'A->1' => 'mysql://ensadmin:${ENSADMIN_PSW}@127.0.0.1/lg4_long_mult/analysis?logic_name=add_together' }" 

SCRIPT-SPECIFIC OPTIONS
-----------------------

::

        -help               : print this help
        -debug <level>      : turn on debug messages at <level>
        -no_write           : skip the execution of write_output() step this time
        -no_cleanup         : do not cleanup temporary files
        -reg_conf <path>    : load registry entries from the given file (these entries may be needed by the RunnableDB itself)
        -input_id "<hash>"  : specify the whole input_id parameter in one stringified hash
        -flow_out "<hash>"  : defines the dataflow re-direction rules in a format similar to PipeConfig's - see the last example
        -language           : language in which the runnable is written

        NB: all other options will be passed to the runnable (leading dashes removed) and will constitute the parameters for the job.

LICENSE
-------

::

        Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
        Copyright [2016-2017] EMBL-European Bioinformatics Institute

        Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
        You may obtain a copy of the License at

             http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software distributed under the License
        is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and limitations under the License.

CONTACT
-------

::

        Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates
