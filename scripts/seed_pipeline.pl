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

use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;
use Bio::EnsEMBL::Hive::Utils ('destringify', 'stringify', 'script_usage');

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
        $help);

    GetOptions(
                # connect to the database:
            'url=s'                        => \$url,
            'reg_conf|regfile|reg_file=s'  => \$reg_conf,
            'reg_type=s'                   => \$reg_type,
            'reg_alias|regname|reg_name=s' => \$reg_alias,
            'nosqlvc=i'                    => \$nosqlvc,      # using "=i" instead of "!" for consistency with scripts where it is a propagated option


                # identify the analysis:
            'analyses_pattern=s'    => \$analyses_pattern,
            'analysis_id=i'         => \$analysis_id,
            'logic_name=s'          => \$logic_name,

                # specify the input_id (as a string):
            'input_id=s'            => \$input_id,

	        # other commands/options
	    'h|help!'               => \$help,
    ) or die "Error in command line arguments\n";

    if (@ARGV) {
        die "ERROR: There are invalid arguments on the command-line: ". join(" ", @ARGV). "\n";
    }

    if ($help) { script_usage(0); }

    my $pipeline;
    if($url or $reg_alias) {
        $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
                -url                            => $url,
                -reg_conf                       => $reg_conf,
                -reg_type                       => $reg_type,
                -reg_alias                      => $reg_alias,
                -no_sql_schema_version_check    => $nosqlvc,
        );
    } else {
        warn "\nERROR: Connection parameters (url or reg_conf+reg_alias) need to be specified\n";
        script_usage(1);
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

        print "\nYou haven't specified -logic_name nor -analysis_id of the analysis being seeded.\n";
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
        'prev_job'      => undef,   # this job has been created by the initialization script, not by another job
        'analysis'      => $analysis,
        'input_id'      => $dinput_id,      # Make sure all job creations undergo re-stringification to avoid alternative "spellings" of the same input_id hash
    );

    my ($job_id) = @{ $pipeline->hive_dba->get_AnalysisJobAdaptor->store_jobs_and_adjust_counters( [ $job ] ) };

    if($job_id) {

        print "Job $job_id [ ".$analysis->logic_name.'('.$analysis->dbID.")] : '$input_id'\n";

    } else {

        warn "Could not create job '$input_id' (it may have been created already)\n";
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

    seed_pipeline.pl is a generic script that is used to create {initial or top-up} jobs for hive pipelines

=head1 USAGE EXAMPLES

        # find out which analyses may need seeding (with an example input_id):

    seed_pipeline.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult"


        # seed one job into the "start" analysis:

    seed_pipeline.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult" \
                     -logic_name start -input_id '{"a_multiplier" => 2222222222, "b_multiplier" => 3434343434}'

=head1 OPTIONS

=head2 Connection parameters

    -reg_conf <path>            : path to a Registry configuration file
    -reg_type <string>          : type of the registry entry ('hive', 'core', 'compara', etc - defaults to 'hive')
    -reg_alias <string>         : species/alias name for the Hive DBAdaptor
    -url <url string>           : url defining where hive database is located
    -nosqlvc <0|1>              : skip sql version check if 1

=head2 Analysis parameters

    -analyses_pattern <string>  : seed job(s) for analyses whose logic_name matches the supplied pattern
    -analysis_id <num>          : seed job for analysis with the given analysis_id

=head2 Input

    -input_id <string>          : specify the input_id as a stringified hash 

=head2 Other commands/options

    -h | -help                  : show this help message

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

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

