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

use Getopt::Long qw(:config pass_through no_auto_abbrev);
use Pod::Usage;

use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module', 'parse_cmdline_options', 'stringify', 'destringify');
use Bio::EnsEMBL::Hive::Utils::URL;
use Bio::EnsEMBL::Hive::Scripts::StandaloneJob;

Bio::EnsEMBL::Hive::Utils::URL::hide_url_password();

main();


sub main {
    my ($reg_conf,
	$url,
	$job_id,
	$input_id,
	$flow_into,
	$no_write,
	$no_cleanup,
	$debug,
	$language,
	$help);

    GetOptions (
		   # connection parameters
		'reg_conf|regfile|reg_file=s'    => \$reg_conf,

                   # Seed options
		'input_id=s'        => \$input_id,
		'url=s'             => \$url,
		'job_id=i'          => \$job_id,

                   # flow control
                'flow_into|flow=s'  => \$flow_into,

                   # debugging
		'no_write'      => \$no_write,
		'no_cleanup'    => \$no_cleanup,
		'debug=i'       => \$debug,

                  # other commands/options
                'language=s'    => \$language,
		'h|help!'       => \$help,
	       );

    if ($help) {
        pod2usage({-exitvalue => 0, -verbose => 2});
    }

    my $module_or_file;

    if($reg_conf) {
        require Bio::EnsEMBL::Registry;
        Bio::EnsEMBL::Registry->load_all($reg_conf);
    }

    if ($input_id && ($job_id || $url)) {
        die "Error: -input_id cannot be given at the same time as -job_id or -url\n";

    } elsif ($job_id && $url) {
        my $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new( -url => $url, -no_sql_schema_version_check => 1 );
        unless($pipeline->hive_dba) {
            die "ERROR : no database connection\n\n";
        }
        my $job = $pipeline->hive_dba->get_AnalysisJobAdaptor->fetch_by_dbID($job_id)
                    || die "ERROR: No Job with jo_id=$job_id\n";
        $job->load_parameters();
        my ($param_hash, $param_list) = parse_cmdline_options();
        if (@$param_list) {
            die "ERROR: There are invalid arguments on the command-line: ". join(" ", @$param_list). "\n";
        }
        $input_id = stringify( {%{$job->{'_unsubstituted_param_hash'}}, %$param_hash} );
        $module_or_file = $job->analysis->module;
        my $status = $job->status;
        warn "\nTaken parameters from job_id $job_id (status $status) @ $url\n";
        warn "Will now disconnect from it. Be aware that the original Job will NOT be updated with the outcome of this standalone. Use runWorker.pl if you want to register your run.\n";
        $pipeline->hive_dba->dbc->disconnect_if_idle;

    } elsif (!$input_id) {
        $module_or_file = shift @ARGV;
        my ($param_hash, $param_list) = parse_cmdline_options();
        if (@$param_list) {
            die "ERROR: There are invalid arguments on the command-line: ". join(" ", @$param_list). "\n";
        }
        $input_id = stringify($param_hash);
    } else {
        $module_or_file = shift @ARGV;
        if (@ARGV) {
            die "ERROR: There are invalid arguments on the command-line: ". join(" ", @ARGV). "\n";
        }
    }

    if (!$module_or_file) {
        die "ERROR: need to provide a module name to run\n";
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

=over

=item 1.

takes in a Runnable module,

=item 2.

creates a standalone Job outside an eHive database by initialising parameters from command line arguments

=item 3.

and runs that Job outside of any eHive database.

I<WARNING> the Runnable code may still access databases provided
as arguments and even harm them!

=item 4.

can optionally dataflow into tables fully defined by URLs

=back

Naturally, only certain Runnable modules can be run using this script, and some database-related functionality will be lost.

There are several ways of initialising the Job parameters:

=over

=item 1.

C<Module::Name -input_id>. The simplest one: just provide a stringified hash

=item 2.

C<Module::Name -param1 value1 -param2 value2 (...)>. Enumerate all the arguments on the command-line. ARRAY- and HASH-
arguments can be passed+parsed too!

=item 3.

C<-url $ehive_url job_id XXX>. The reference to an existing Job from which the parameters will be pulled. It is
a convenient way of gathering all the parameters (the Job's input_id, the Job's accu, the Analysis parameters
and the pipeline-wide parameters).  Further parameters can be added with C<-param1 value1 -param2 value2 (...)>
and they take priority over the existing Job's parameters. The Runnable is also found in the database.

<NOTE> the standaloneJob will *not* interact any further with this eHive database. There won't be any updates
to the C<job>, C<worker>, C<log_message> etc tables.

=back

=head1 USAGE EXAMPLES

        # Run a Job with default parameters, specify module by its package name:
    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::FailureTest

        # Run the same Job with default parameters, but specify module by its relative filename:
    standaloneJob.pl RunnableDB/FailureTest.pm

        # Run a Job and re-define some of the default parameters:
    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::FailureTest -time_RUN=2 -time_WRITE_OUTPUT=3 -state=WRITE_OUTPUT -value=2
    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::SystemCmd -cmd 'ls -l'
    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::SystemCmd -input_id "{ 'cmd' => 'ls -l' }"

        # Run a Job and re-define its "db_conn" parameter to allow it to perform some database-related operations:
    standaloneJob.pl RunnableDB/SqlCmd.pm -db_conn mysql://ensadmin:xxxxxxx@127.0.0.1:2912/lg4_compara_families_63 -sql 'INSERT INTO meta (meta_key,meta_value) VALUES ("hello", "world2")'

        # Run a Job initialised from the parameters of an existing Job topped-up with extra ones.
        # In this particular example the Runnable needs a "compara_db" parameter which defaults to the eHive database.
        # Since there is no eHive database here we need to define -compara_db on the command-line
    standaloneJob.pl -url mysql://ensro@compara1.internal.sanger.ac.uk:3306/mm14_pecan_24way_86b -job_id 16781 -compara_db mysql://ensro@compara1.internal.sanger.ac.uk:3306/mm14_pecan_24way_86b

        # Run a Job with given parameters, but skip the write_output() step:
    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::FailureTest -no_write -time_RUN=2 -time_WRITE_OUTPUT=3 -state=WRITE_OUTPUT -value=2

        # Run a Job and re-direct its dataflow into tables:
    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::JobFactory -inputfile foo.txt -delimiter '\t' -column_names "[ 'name', 'age' ]" \
                        -flow_into "{ 2 => ['mysql://ensadmin:xxxxxxx@127.0.0.1:2914/lg4_triggers/foo', 'mysql://ensadmin:xxxxxxx@127.0.0.1:2914/lg4_triggers/bar'] }"

        # Run a Compara Job that needs a connection to Compara database:
    standaloneJob.pl Bio::EnsEMBL::Compara::RunnableDB::ObjectFactory -compara_db 'mysql://ensadmin:xxxxxxx@127.0.0.1:2911/sf5_ensembl_compara_master' \
                        -adaptor_name MethodLinkSpeciesSetAdaptor -adaptor_method fetch_all_by_method_link_type -method_param_list "[ 'ENSEMBL_ORTHOLOGUES' ]" \
                        -column_names2getters "{ 'name' => 'name', 'mlss_id' => 'dbID' }" -flow_into "{ 2 => 'mysql://ensadmin:xxxxxxx@127.0.0.1:2914/lg4_triggers/baz' }"

        # Create a new Job in a database using automatic dataflow from a database-less Dummy Job:
    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::Dummy -a_multiplier 1234567 -b_multiplier 9876543 \
                        -flow_into "{ 1 => 'mysql://ensadmin:xxxxxxx@127.0.0.1/lg4_long_mult/analysis?logic_name=start' }"

        # Produce a Semaphore group of Jobs from a database-less DigitFactory Job:
    standaloneJob.pl Bio::EnsEMBL::Hive::Examples::LongMult::RunnableDB::DigitFactory -input_id "{ 'a_multiplier' => '2222222222', 'b_multiplier' => '3434343434'}" \
        -flow_into "{ '2->A' => 'mysql://ensadmin:${ENSADMIN_PSW}@127.0.0.1/lg4_long_mult/analysis?logic_name=part_multiply', 'A->1' => 'mysql://ensadmin:${ENSADMIN_PSW}@127.0.0.1/lg4_long_mult/analysis?logic_name=add_together' }" 


=head1 SCRIPT-SPECIFIC OPTIONS

=over

=item --help

print this help

=item --debug <level>

turn on debug messages at <level>

=item --no_write

skip the execution of write_output() step this time

=item --no_cleanup

do not cleanup temporary files

=item --reg_conf <path>

load registry entries from the given file (these entries may be needed by the Runnable itself)

=item --input_id <hash>

specify the whole input_id parameter in one stringified hash

=item --flow_out <hash>

defines the dataflow re-direction rules in a format similar to PipeConfig's - see the last example

=item --language <name>

language in which the Runnable is written

=back

All other options will be passed to the Runnable (leading dashes removed) and will constitute the parameters for the Job.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2021] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

Please subscribe to the eHive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss eHive-related questions or to be notified of our updates

=cut

