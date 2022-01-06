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

use Getopt::Long qw(:config no_auto_abbrev);
use Pod::Usage;

use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;
use Bio::EnsEMBL::Hive::Utils ('destringify', 'stringify');
use Bio::EnsEMBL::Hive::Utils::URL;

Bio::EnsEMBL::Hive::Utils::URL::hide_url_password();

sub show_seedable_analyses {
    my ($pipeline) = @_;

    my $job_adaptor = $pipeline->hive_dba->get_AnalysisJobAdaptor;

    foreach my $source_analysis ( @{ $pipeline->get_source_analyses } ) {
        my $logic_name = $source_analysis->logic_name;
        my $analysis_id = $source_analysis->dbID;
        my ($example_job) = @{ $job_adaptor->fetch_some_by_analysis_id_limit( $analysis_id, 1 ) };
        print "\t$logic_name ($analysis_id)\t\t".($example_job ? "Example input_id:   '".$example_job->input_id."'" : "[not populated yet]")."\n";
    }
}


sub main {
    my ($url, 
	$reg_conf, 
	$reg_type, 
	$reg_alias, 
	$nosqlvc, 
	$analyses_pattern, 
	$analysis_id, 
	$logic_name, 
	$input_id,
    $wrap_in_semaphore,
        $help);

    GetOptions(
                # connect to the database:
            'url=s'                        => \$url,
            'reg_conf|regfile|reg_file=s'  => \$reg_conf,
            'reg_type=s'                   => \$reg_type,
            'reg_alias|regname|reg_name=s' => \$reg_alias,
            'nosqlvc'                      => \$nosqlvc,      # using "nosqlvc" instead of "sqlvc!" for consistency with scripts where it is a propagated option

                # identify the analysis:
            'analyses_pattern=s'    => \$analyses_pattern,
            'analysis_id=i'         => \$analysis_id,
            'logic_name=s'          => \$logic_name,

            'input_id=s'            => \$input_id,          # specify the Job's input parameters (as a stringified hash)
            'wrap|semaphored!'      => \$wrap_in_semaphore, # wrap the job into a funnel semaphore (provide a stable_id for the whole execution stream)

	        # other commands/options
	    'h|help!'               => \$help,
    ) or die "Error in command line arguments\n";

    if (@ARGV) {
        die "ERROR: There are invalid arguments on the command-line: ". join(" ", @ARGV). "\n";
    }

    if ($help) {
        pod2usage({-exitvalue => 0, -verbose => 2});
    }

    my $pipeline;
    if($url or $reg_alias) {
        $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
                -url                            => $url,
                -reg_conf                       => $reg_conf,
                -reg_type                       => $reg_type,
                -reg_alias                      => $reg_alias,
                -no_sql_schema_version_check    => $nosqlvc,
        );
        $pipeline->hive_dba()->dbc->requires_write_access();
    } else {
        die "\nERROR: Connection parameters (url or reg_conf+reg_alias) need to be specified\n";
    }

    my $analysis;
    if($analyses_pattern ||= $analysis_id || $logic_name) {

        my $candidate_analyses = $pipeline->collection_of( 'Analysis' )->find_all_by_pattern( $analyses_pattern );

        if( scalar(@$candidate_analyses) > 1 ) {
            die "Too many analyses matching pattern '$analyses_pattern', please specify\n";
        } elsif( !scalar(@$candidate_analyses) ) {
            die "Analysis matching the pattern '$analyses_pattern' could not be found\n";
        }

        ($analysis) = @$candidate_analyses;

    } else {

        print "\nYou haven't specified -logic_name nor -analysis_id of the Analysis being seeded.\n";
        print "\nSeedable analyses without incoming dataflow:\n";
        show_seedable_analyses($pipeline);
        exit(0);
    }

    unless($input_id) {
        $input_id = '{}';
        warn "Since -input_id has not been set, assuming input_id='$input_id'\n";
    }
    my $dinput_id = destringify($input_id);
    if (!ref($dinput_id)) {
        die "'$input_id' cannot be eval'ed, likely because of a syntax error\n";
    }
    if (ref($dinput_id) ne 'HASH') {
        die "'$input_id' is not a hash\n";
    }

    my $job = Bio::EnsEMBL::Hive::AnalysisJob->new(
        'hive_pipeline' => $pipeline,
        'prev_job'      => undef,           # This job has been created by the seed_pipeline.pl script, not by another job
        'analysis'      => $analysis,
        'input_id'      => $dinput_id,      # Make sure all job creations undergo re-stringification to avoid alternative "spellings" of the same input_id hash
    );

    my $job_adaptor = $pipeline->hive_dba->get_AnalysisJobAdaptor;
    my ($semaphore_id, $job_id);

    if( $wrap_in_semaphore ) {
        my $dummy;
        ($semaphore_id, $dummy, $job_id) = $job_adaptor->store_a_semaphored_group_of_jobs( undef, [ $job ], undef );
    } else {
        ($job_id) = @{ $job_adaptor->store_jobs_and_adjust_counters( [ $job ] ) };
    }

    if($job_id) {
        print "Job $job_id [ ".$analysis->logic_name.'('.$analysis->dbID.")] : '$input_id'".($semaphore_id ? ", wrapped in Semaphore $semaphore_id" : '')."\n";

    } else {
        warn "Could not create Job '$input_id' (it may have been created already)\n";
    }
}

main();

__DATA__

=pod

=head1 NAME

seed_pipeline.pl

=head1 SYNOPSIS

    seed_pipeline.pl {-url <url> | -reg_conf <reg_conf> [-reg_type <reg_type>] -reg_alias <reg_alias>} [ {-analyses_pattern <pattern> | -analysis_id <analysis_id> | -logic_name <logic_name>} [ -input_id <input_id> ] ]

=head1 DESCRIPTION

seed_pipeline.pl is a generic script that is used to create {initial or top-up} Jobs for eHive pipelines

=head1 USAGE EXAMPLES

        # find out which analyses may need seeding (with an example input_id):

    seed_pipeline.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult"


        # seed one Job into the "start" Analysis:

    seed_pipeline.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult" \
                     -logic_name start -input_id '{"a_multiplier" => 2222222222, "b_multiplier" => 3434343434}'

=head1 OPTIONS

=head2 Connection parameters

=over

=item --reg_conf <path>

path to a Registry configuration file

=item --reg_type <string>

type of the registry entry ("hive", "core", "compara", etc - defaults to "hive")

=item --reg_alias <string>

species/alias name for the eHive DBAdaptor

=item --url <url string>

URL defining where eHive database is located

=item --nosqlvc

"No SQL Version Check" - set if you want to force working with a database created by a potentially schema-incompatible API

=back

=head2 Analysis parameters

=over

=item --analyses_pattern <string>

seed Job(s) for analyses whose logic_name matches the supplied pattern

=item --analysis_id <num>

seed Job for Analysis with the given analysis_id

=back

=head2 Input

=over

=item --input_id <string>

specify the Job's input parameters as a stringified hash

=item --semaphored

wrap the Job into a funnel Semaphore (provide a stable_id for the whole execution stream)

=back

=head2 Other commands/options

=over

=item -h, --help

show this help message

=back

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2022] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

Please subscribe to the eHive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss eHive-related questions or to be notified of our updates

=cut

