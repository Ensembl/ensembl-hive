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

use Bio::EnsEMBL::Hive::Version qw(report_versions);
use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Scripts::RunWorker;
use Bio::EnsEMBL::Hive::Utils::URL;

Bio::EnsEMBL::Hive::Utils::URL::hide_url_password();

main();


sub main {
    my ($url, $reg_conf, $reg_type, $reg_alias, $nosqlvc);                   # Connection parameters
    my ($preregistered, $resource_class_id, $resource_class_name, $analyses_pattern, $analysis_id, $logic_name, $job_id, $force, $beekeeper_id);    # Task specification parameters
    my ($job_limit, $life_span, $no_cleanup, $no_write, $worker_cur_dir, $hive_log_dir, $worker_log_dir, $retry_throwing_jobs, $can_respecialize,   # Worker control parameters
        $worker_delay_startup_seconds, $worker_crash_on_startup_prob, $config_files);
    my ($help, $report_versions, $debug);

    # Default values
    $config_files   = [];

    $|=1;   # make STDOUT unbuffered (STDERR is unbuffered anyway)

    GetOptions(

    # Connection parameters:
               'url=s'                        => \$url,
               'reg_conf|regfile|reg_file=s'  => \$reg_conf,
               'reg_type=s'                   => \$reg_type,
               'reg_alias|regname|reg_name=s' => \$reg_alias,
               'nosqlvc=i'                    => \$nosqlvc,       # can't use the binary "!" as it is a propagated option

    # json config files
               'config_file=s@'             => $config_files,

    # Task specification parameters:
               'preregistered!'             => \$preregistered,
               'rc_id=i'                    => \$resource_class_id,
               'rc_name=s'                  => \$resource_class_name,
               'analyses_pattern=s'         => \$analyses_pattern,
               'analysis_id=i'              => \$analysis_id,
               'logic_name=s'               => \$logic_name,
               'job_id=i'                   => \$job_id,
               'force=i'                    => \$force,
               'beekeeper_id=i'             => \$beekeeper_id,

    # Worker control parameters:
               'job_limit=i'                => \$job_limit,
               'life_span|lifespan=i'       => \$life_span,
               'no_cleanup'                 => \$no_cleanup,
               'no_write'                   => \$no_write,
               'worker_cur_dir|cwd=s'       => \$worker_cur_dir,
               'hive_log_dir|hive_output_dir=s'         => \$hive_log_dir,       # keep compatibility with the old name
               'worker_log_dir|worker_output_dir=s'     => \$worker_log_dir,     # will take precedence over hive_log_dir if set
               'retry_throwing_jobs=i'      => \$retry_throwing_jobs,
               'can_respecialize=i'         => \$can_respecialize,
               'worker_delay_startup_seconds=i' => \$worker_delay_startup_seconds,
               'worker_crash_on_startup_prob=f' => \$worker_crash_on_startup_prob,

    # Other commands
               'h|help'                     => \$help,
               'v|version|versions'         => \$report_versions,
               'debug=i'                    => \$debug,
    ) or die "Error in command line arguments\n";

    if (@ARGV) {
        die "ERROR: There are invalid arguments on the command-line: ". join(" ", @ARGV). "\n";
    }

    if ($help) {
        pod2usage({-exitvalue => 0, -verbose => 2});
    }

    if($report_versions) {
        report_versions();
        exit(0);
    }

    chdir $worker_cur_dir if $worker_cur_dir;   # Allows using relative paths for Sqlite URLs, registry files etc

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
        die "\nERROR: Connection parameters (url or reg_conf+reg_alias) need to be specified\n";
    }

    unless($pipeline->hive_dba) {
        die "ERROR : no database connection, the pipeline could not be accessed\n\n";
    }

    if( $logic_name ) {
        warn "-logic_name is now deprecated, please use -analyses_pattern that extends the functionality of -logic_name and -analysis_id .\n";
        $analyses_pattern = $logic_name;
    } elsif ( $analysis_id ) {
        warn "-analysis_id is now deprecated, please use -analyses_pattern that extends the functionality of -analysis_id and -logic_name .\n";
        $analyses_pattern = $analysis_id;
    }

    my %specialization_options = (
        preregistered       => $preregistered,
        resource_class_id   => $resource_class_id,
        resource_class_name => $resource_class_name,
        can_respecialize    => $can_respecialize,
        analyses_pattern    => $analyses_pattern,
        job_id              => $job_id,
        force               => $force,
        beekeeper_id        => $beekeeper_id,
    );
    my %life_options = (
        job_limit                       => $job_limit,
        life_span                       => $life_span,
        retry_throwing_jobs             => $retry_throwing_jobs,
        worker_delay_startup_seconds    => $worker_delay_startup_seconds,
        worker_crash_on_startup_prob    => $worker_crash_on_startup_prob,
    );
    my %execution_options = (
        config_files        => $config_files,
        no_cleanup          => $no_cleanup,
        no_write            => $no_write,
        worker_log_dir      => $worker_log_dir,
        hive_log_dir        => $hive_log_dir,
        debug               => $debug,
    );

    Bio::EnsEMBL::Hive::Scripts::RunWorker::runWorker($pipeline, \%specialization_options, \%life_options, \%execution_options);
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

=over

=item --reg_conf <path>

path to a Registry configuration file

=item --reg_alias <string>

species/alias name for the Hive DBAdaptor

=item --reg_type <string>

type of the registry entry ('hive', 'core', 'compara', etc - defaults to 'hive')

=item --url <url string>

url defining where database is located

=item --nosqlvc <0|1>

skip sql version check if 1

=back

=head2 Configs overriding

=over

=item --config_file <string>

JSON file (with absolute path) to override the default configurations (could be multiple)

=back

=head2 Task specification parameters:

=over

=item --rc_id <id>

resource class id

=item --rc_name <string>

resource class name

=item --analyses_pattern <string>

restrict the specialization of the Worker to the specified subset of Analyses

=item --analysis_id <id>

run a worker and have it specialize to an analysis with this analysis_id

=item --job_id <id>

run a specific job defined by its database id

=item --force <0|1>

set to 1 if you want to force running a Worker over a BLOCKED analysis or to run a specific DONE/SEMAPHORED job_id

=back

=head2 Worker control parameters:

=over

=item --job_limit <num>

#jobs to run before worker can die naturally

=item --life_span <num>

number of minutes this worker is allowed to run

=item --no_cleanup

don't perform temp directory cleanup when worker exits

=item --no_write

don't write_output or auto_dataflow input_job

=item --hive_log_dir <path>

directory where stdout/stderr of the whole hive of workers is redirected

=item --worker_log_dir <path>

directory where stdout/stderr of this particular worker is redirected

=item --retry_throwing_jobs <0|1>

if a job dies *knowingly*, should we retry it by default?

=item --can_respecialize <0|1>

allow this worker to re-specialize into another analysis (within resource_class) after it has exhausted all jobs of the current one

=item --worker_delay_startup_seconds <number>

number of seconds each worker has to wait before first talking to the database (0 by default, useful for debugging)

=item --worker_crash_on_startup_prob <float>

probability of each worker failing at startup (0 by default, useful for debugging)

=back

=head2 Other options:

=over

=item --help

print this help

=item --versions

report both Hive code version and Hive database schema version

=item --debug <level>

turn on debug messages at <level>

=back

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2017] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

