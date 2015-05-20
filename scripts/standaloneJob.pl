#!/usr/bin/env perl

use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}


use Getopt::Long qw(:config pass_through);
use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::Utils ('script_usage', 'load_file_or_module', 'parse_cmdline_options', 'stringify', 'destringify');
use Bio::EnsEMBL::Hive::Scripts::StandaloneJob;


main();


sub main {
    my ($reg_conf, $help, $debug, $no_write, $no_cleanup, $flow_into, $input_id, $language);

    my $module_or_file = shift @ARGV or script_usage();

    GetOptions(
               'help'               => \$help,
               'debug=i'            => \$debug,
               'reg_conf|regfile=s' => \$reg_conf,
               'no_write'           => \$no_write,
               'no_cleanup'         => \$no_cleanup,
               'flow_into|flow=s'   => \$flow_into,
               'input_id=s'         => \$input_id,
               'language=s'         => \$language,
    );

    if ($help or !$module_or_file) {
        script_usage(0);
    }

    if($reg_conf) {
        require Bio::EnsEMBL::Registry;
        Bio::EnsEMBL::Registry->load_all($reg_conf);
    }

    unless($input_id) {
        my ($param_hash, $param_list) = parse_cmdline_options();
        $input_id = stringify($param_hash);
    }
    warn "\nRunning '$module_or_file' with input_id='$input_id' :\n";

    my %flags = (
        no_write    => $no_write,
        no_cleanup  => $no_cleanup,
        debug       => $debug,
    );
    my $job_successful = Bio::EnsEMBL::Hive::Scripts::StandaloneJob::standaloneJob($module_or_file, $input_id, \%flags, $flow_into, $language);
    exit(1) unless $job_successful;
}


__DATA__

=pod

=head1 NAME

    standaloneJob.pl

=head1 DESCRIPTION

    standaloneJob.pl is an eHive component script that
        1. takes in a RunnableDB module,
        2. creates a standalone job outside an eHive database by initializing parameters from command line arguments (ARRAY- and HASH- arguments can be passed+parsed too!)
        3. and runs that job outside the database.
        4. can optionally dataflow into tables fully defined by URLs
    Naturally, only certain RunnableDB modules can be run using this script, and some database-related functionality will be lost.

=head1 USAGE EXAMPLES

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
    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::LongMult::DigitFactory -input_id "{ 'a_multiplier' => '2222222222', 'b_multiplier' => '3434343434'}" \
        -flow_into "{ '2->A' => 'mysql://ensadmin:${ENSADMIN_PSW}@127.0.0.1/lg4_long_mult/analysis?logic_name=part_multiply', 'A->1' => 'mysql://ensadmin:${ENSADMIN_PSW}@127.0.0.1/lg4_long_mult/analysis?logic_name=add_together' }" 


=head1 SCRIPT-SPECIFIC OPTIONS

    -help               : print this help
    -debug <level>      : turn on debug messages at <level>
    -no_write           : skip the execution of write_output() step this time
    -reg_conf <path>    : load registry entries from the given file (these entries may be needed by the RunnableDB itself)
    -input_id "<hash>"  : specify the whole input_id parameter in one stringified hash
    -flow_out "<hash>"  : defines the dataflow re-direction rules in a format similar to PipeConfig's - see the last example

    NB: all other options will be passed to the runnable (leading dashes removed) and will constitute the parameters for the job.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

