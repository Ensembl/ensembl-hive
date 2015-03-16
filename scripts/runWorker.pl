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


use Getopt::Long;
use Bio::EnsEMBL::Hive::Utils ('script_usage', 'report_versions');
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Queen;
use Bio::EnsEMBL::Hive::Valley;
use Bio::EnsEMBL::Hive::Scripts::RunWorker;


main();


sub main {
    my ($url, $reg_conf, $reg_type, $reg_alias, $nosqlvc);                   # Connection parameters
    my ($resource_class_id, $resource_class_name, $analyses_pattern, $analysis_id, $logic_name, $job_id, $force);  # Task specification parameters
    my ($job_limit, $life_span, $no_cleanup, $no_write, $hive_log_dir, $worker_log_dir, $retry_throwing_jobs, $can_respecialize);   # Worker control parameters
    my ($help, $report_versions, $debug);

    GetOptions(

    # Connection parameters:
               'url=s'                      => \$url,
               'reg_conf|regfile=s'         => \$reg_conf,
               'reg_type=s'                 => \$reg_type,
               'reg_alias|regname=s'        => \$reg_alias,
               'nosqlvc=i'                  => \$nosqlvc,       # can't use the binary "!" as it is a propagated option

    # Task specification parameters:
               'rc_id=i'                    => \$resource_class_id,
               'rc_name=s'                  => \$resource_class_name,
               'analyses_pattern=s'         => \$analyses_pattern,
               'analysis_id=i'              => \$analysis_id,
               'logic_name=s'               => \$logic_name,
               'job_id=i'                   => \$job_id,
               'force=i'                    => \$force,

    # Worker control parameters:
               'job_limit=i'                => \$job_limit,
               'life_span|lifespan=i'       => \$life_span,
               'no_cleanup'                 => \$no_cleanup,
               'no_write'                   => \$no_write,
               'hive_log_dir|hive_output_dir=s'         => \$hive_log_dir,       # keep compatibility with the old name
               'worker_log_dir|worker_output_dir=s'     => \$worker_log_dir,     # will take precedence over hive_log_dir if set
               'retry_throwing_jobs=i'      => \$retry_throwing_jobs,
               'can_respecialize=i'         => \$can_respecialize,

    # Other commands
               'h|help'                     => \$help,
               'v|versions'                 => \$report_versions,
               'debug=i'                    => \$debug,
    );

    if ($help) { script_usage(0); }

    if($report_versions) {
        report_versions();
        exit(0);
    }

    my $hive_dba;

    if($url or $reg_alias) {
            # Perform environment variable substitution separately with and without curly braces.
            #       Fixme: Perl 5.10 has a cute new "branch reset" (?|pattern)
            #              that would allow to merge the two substitutions below into a nice one-liner.
            #              But people around may still be using Perl 5.8, so let's wait a bit.
            #
            # Make sure expressions stay as they were if we were unable to substitute them.
            #
        if($url) {
            $url =~ s/\$(\{(\w+)\})/defined($ENV{$2})?"$ENV{$2}":"\$$1"/eg;
            $url =~ s/\$((\w+))/defined($ENV{$2})?"$ENV{$2}":"\$$1"/eg;
        }

        $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(
                -url                            => $url,
                -reg_conf                       => $reg_conf,
                -reg_type                       => $reg_type,
                -reg_alias                      => $reg_alias,
                -no_sql_schema_version_check    => $nosqlvc,
        );

    } else {
        print "\nERROR : Connection parameters (url or reg_conf+reg_alias) need to be specified\n\n";
        script_usage(1);
    }

    unless($hive_dba and $hive_dba->isa("Bio::EnsEMBL::Hive::DBSQL::DBAdaptor")) {
        print "ERROR : no database connection\n\n";
        script_usage(1);
    }

    if( $logic_name ) {
        warn "-logic_name is now deprecated, please use -analyses_pattern that extends the functionality of -logic_name and -analysis_id .\n";
        $analyses_pattern = $logic_name;
    } elsif ( $analysis_id ) {
        warn "-analysis_id is now deprecated, please use -analyses_pattern that extends the functionality of -analysis_id and -logic_name .\n";
        $analyses_pattern = $analysis_id;
    }

    my %specialization_options = (
        resource_class_id   => $resource_class_id,
        resource_class_name => $resource_class_name,
        can_respecialize    => $can_respecialize,
        analyses_pattern    => $analyses_pattern,
        job_id              => $job_id,
        force               => $force,
    );
    my %life_options = (
        job_limit           => $job_limit,
        life_span           => $life_span,
        retry_throwing_jobs => $retry_throwing_jobs,
    );
    my %execution_options = (
        no_cleanup          => $no_cleanup,
        no_write            => $no_write,
        worker_log_dir      => $worker_log_dir,
        hive_log_dir        => $hive_log_dir,
        debug               => $debug,
    );

    Bio::EnsEMBL::Hive::Scripts::RunWorker::runWorker($hive_dba, \%specialization_options, \%life_options, \%execution_options);
}


__DATA__

=pod

=head1 NAME

    runWorker.pl [options]

=head1 DESCRIPTION

    runWorker.pl is an eHive component script that does the work of a single Worker -
    specializes in one of the analyses and starts executing jobs of that analysis one-by-one or batch-by-batch.

    Most of the functionality of the eHive is accessible via beekeeper.pl script,
    but feel free to run the runWorker.pl if you think you know what you are doing :)

=head1 USAGE EXAMPLES

        # Run one local worker process in ehive_dbname and let the system pick up the analysis
    runWorker.pl -url mysql://username:secret@hostname:port/ehive_dbname

        # Run one local worker process in ehive_dbname and let the system pick up the analysis from the given resource_class
    runWorker.pl -url mysql://username:secret@hostname:port/ehive_dbname -rc_name low_mem

        # Run one local worker process in ehive_dbname and constrain its initial specialization within a subset of analyses
    runWorker.pl -url mysql://username:secret@hostname:port/ehive_dbname -analyses_pattern '1..15,analysis_X,21'

        # Run one local worker process in ehive_dbname and allow it to respecialize within a subset of analyses
    runWorker.pl -url mysql://username:secret@hostname:port/ehive_dbname -can_respecialize 1 -analyses_pattern 'blast%-4..6'

        # Run a specific job in a local worker process:
    runWorker.pl -url mysql://username:secret@hostname:port/ehive_dbname -job_id 123456

=head1 OPTIONS

=head2 Connection parameters:

    -reg_conf <path>            : path to a Registry configuration file
    -reg_alias <string>         : species/alias name for the Hive DBAdaptor
    -url <url string>           : url defining where database is located

=head2 Task specificaton parameters:

    -rc_id <id>                 : resource class id
    -rc_name <string>           : resource class name
    -analyses_pattern <string>  : restrict the specialization of the Worker to the specified subset of Analyses
    -job_id <id>                : run a specific job defined by its database id
    -force 0|1                  : set to 1 if you want to force running a Worker over a BLOCKED analysis or to run a specific DONE/SEMAPHORED job_id

=head2 Worker control parameters:

    -job_limit <num>            : #jobs to run before worker can die naturally
    -life_span <num>            : number of minutes this worker is allowed to run
    -no_cleanup                 : don't perform temp directory cleanup when worker exits
    -no_write                   : don't write_output or auto_dataflow input_job
    -hive_log_dir <path>        : directory where stdout/stderr of the whole hive of workers is redirected
    -worker_log_dir <path>      : directory where stdout/stderr of this particular worker is redirected
    -retry_throwing_jobs <0|1>  : if a job dies *knowingly*, should we retry it by default?
    -can_respecialize <0|1>     : allow this worker to re-specialize into another analysis (within resource_class) after it has exhausted all jobs of the current one

=head2 Other options:

    -help                       : print this help
    -versions                   : report both Hive code version and Hive database schema version
    -debug <level>              : turn on debug messages at <level>
    -analysis_stats             : show status of each analysis in hive

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

