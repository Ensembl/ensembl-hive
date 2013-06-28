#!/usr/bin/env perl

use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} = File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}


use Getopt::Long qw(:config pass_through);
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::Utils ('script_usage', 'load_file_or_module', 'parse_cmdline_options', 'stringify', 'destringify');

my ($reg_conf, $help, $debug, $no_write, $no_cleanup, $flow_into, $input_id);

my $module_or_file = shift @ARGV or script_usage();

GetOptions(
           'help'               => \$help,
           'debug=i'            => \$debug,
           'reg_conf|regfile=s' => \$reg_conf,
           'no_write'           => \$no_write,
           'no_cleanup'         => \$no_cleanup,
           'flow_into|flow=s'   => \$flow_into,
           'input_id=s'         => \$input_id,
);

if ($help or !$module_or_file) {
    script_usage(0);
}

my $runnable_module = load_file_or_module( $module_or_file );

if($reg_conf) {
    Bio::EnsEMBL::Registry->load_all($reg_conf);
}

my $runnable_object = $runnable_module->new();
my $job = Bio::EnsEMBL::Hive::AnalysisJob->new( -dbID => -1 );
unless($input_id) {
    my ($param_hash, $param_list) = parse_cmdline_options();
    $input_id = stringify($param_hash);
}
$job->input_id( $input_id );
warn "\nRunning '$runnable_module' with input_id='$input_id' :\n";

$job->param_init( $runnable_object->strict_hash_format(), $runnable_object->param_defaults(), $job->input_id() );

$flow_into = $flow_into ? destringify($flow_into) : []; # empty dataflow for branch 1 by default
$flow_into = { 1 => $flow_into } unless(ref($flow_into) eq 'HASH'); # force non-hash into a hash
foreach my $branch_code (keys %$flow_into) {
    my $heirs = $flow_into->{$branch_code};

    $heirs = [ $heirs ] unless(ref($heirs)); # force scalar into an arrayref first
    $heirs = { map { ($_ => undef) } @$heirs } if(ref($heirs) eq 'ARRAY'); # now force it into a hash if it wasn't

    my @dataflow_rules = ();

    while(my ($heir_url, $input_id_template_list) = each %$heirs) {

        $input_id_template_list = [ $input_id_template_list ] unless(ref($input_id_template_list) eq 'ARRAY');  # allow for more than one template per analysis

        foreach my $input_id_template (@$input_id_template_list) {

            push @dataflow_rules, Bio::EnsEMBL::Hive::DataflowRule->new(
                -to_analysis_url            => $heir_url,
                -input_id_template          => $input_id_template,
            );
        }
    }

    $job->dataflow_rules( $branch_code, \@dataflow_rules );
}

$runnable_object->input_job($job);
if($debug) {
    $runnable_object->debug($debug);
}
$runnable_object->execute_writes( not $no_write );

$runnable_object->life_cycle();

unless($no_cleanup) {
    $runnable_object->cleanup_worker_temp_directory();
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


=head1 SCRIPT-SPECIFIC OPTIONS

    -help               : print this help
    -debug <level>      : turn on debug messages at <level>
    -no_write           : skip the execution of write_output() step this time
    -reg_conf <path>    : load registry entries from the given file (these entries may be needed by the RunnableDB itself)
    -input_id "<hash>"  : specify the whole input_id parameter in one stringified hash
    -flow_out "<hash>"  : defines the dataflow re-direction rules in a format similar to PipeConfig's - see the last example

    NB: all other options will be passed to the runnable (leading dashes removed) and will constitute the parameters for the job.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

