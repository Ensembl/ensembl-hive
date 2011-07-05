#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long qw(:config pass_through);
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::Utils ('script_usage', 'load_file_or_module', 'parse_cmdline_options', 'stringify', 'destringify');

use Data::Dumper;

my ($reg_conf, $help, $debug, $no_write, $flow_into);

my $module_or_file = shift @ARGV or script_usage();

GetOptions(
           'help'               => \$help,
           'debug=i'            => \$debug,
           'reg_conf|regfile=s' => \$reg_conf,
           'no_write|nowrite'   => \$no_write,
           'flow_into|flow=s'   => \$flow_into,
);

if ($help or !$module_or_file) {
    script_usage(0);
}

my $runnable_module = load_file_or_module( $module_or_file );

if($reg_conf) {
    Bio::EnsEMBL::Registry->load_all($reg_conf);
}

my $process = $runnable_module->new();
my $job = Bio::EnsEMBL::Hive::AnalysisJob->new();
my ($param_hash, $param_list) = parse_cmdline_options();
$job->param_init( 1, $process->param_defaults(), $param_hash );

$flow_into = $flow_into ? destringify($flow_into) : []; # empty dataflow for branch 1 by default
$flow_into = { 1 => $flow_into } unless(ref($flow_into) eq 'HASH'); # force non-hash into a hash
foreach my $branch_code (keys %$flow_into) {
    my $heirs = $flow_into->{$branch_code};

    $heirs = [ $heirs ] unless(ref($heirs)); # force scalar into an arrayref first

    my @dataflow_rules = map { Bio::EnsEMBL::Hive::DataflowRule->new( -to_analysis_url => $_ ) } @$heirs;

    $job->dataflow_rules( $branch_code, \@dataflow_rules );
}

my $input_id = stringify($param_hash);
$job->input_id( $input_id );
warn "\nRunning '$runnable_module' with '$input_id' :\n";

$process->input_job($job);
if($debug) {
    $process->debug($debug);
}

    # job's life cycle:
warn "\nFETCH_INPUT:\n";
$process->fetch_input();

warn "\nRUN:\n";
$process->run();

unless($no_write) {
    warn "\nWRITE_OUTPUT:\n";
    $process->write_output();
}
warn "\nDONE.\n";

exit(0);

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

        # Run a job and re-define its 'db_conn' parameter to allow it to perform some database-related operations:
    standaloneJob.pl RunnableDB/SqlCmd.pm -db_conn mysql://ensadmin:xxxxxxx@127.0.0.1:2912/lg4_compara_families_63 -sql 'INSERT INTO meta (meta_key,meta_value) VALUES ("hello", "world2")'

        # Run a job with given parameters, but skip the write_output() step:
    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::FailureTest -no_write -time_RUN=2 -time_WRITE_OUTPUT=3 -state=WRITE_OUTPUT -value=2

        # Run a job and re-direct its dataflow into tables:
    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::JobFactory -inputfile foo.txt -delimiter '\t' -column_names "[ 'name', 'age' ]" 
                        -flow_into "{ 2 => ['mysql://ensadmin:ensembl@127.0.0.1:2914/lg4_triggers/foo', 'mysql://ensadmin:ensembl@127.0.0.1:2914/lg4_triggers/bar'] }"

=head1 SCRIPT-SPECIFIC OPTIONS

    -help               : print this help
    -debug <level>      : turn on debug messages at <level>
    -no_write           : skip the execution of write_output() step this time
    -reg_conf <path>    : load registry entries from the given file (these entries may be needed by the RunnableDB itself)
    -flow_out "<hash>"  : defines the dataflow re-direction rules in a format similar to PipeConfig's - see the last example

    NB: all other options will be passed to the runnable (leading dashes removed) and will constitute the parameters for the job.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

