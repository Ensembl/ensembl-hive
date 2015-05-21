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
use File::Path 'make_path';
use Bio::EnsEMBL::Hive::Utils ('script_usage', 'destringify', 'report_versions');
use Bio::EnsEMBL::Hive::Utils::Config;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Queen;
use Bio::EnsEMBL::Hive::Valley;
use Bio::EnsEMBL::Hive::Scheduler;


main();


sub main {
    $| = 1;

        # ok this is a hack, but I'm going to pretend I've got an object here
        # by creating a hash ref and passing it around like an object
        # this is to avoid using global variables in functions, and to consolidate
        # the globals into a nice '$self' package
    my $self = {};

    my $help                        = 0;
    my $report_versions             = 0;
    my $loopit                      = 0;
    my $sync                        = 0;
    my $local                       = 0;
    my $show_failed_jobs            = 0;
    my $default_meadow_type         = undef;
    my $submit_workers_max          = undef;
    my $total_running_workers_max   = undef;
    my $submission_options          = undef;
    my $run                         = 0;
    my $max_loops                   = 0; # not running by default
    my $run_job_id                  = undef;
    my $force                       = undef;
    my $keep_alive                  = 0; # ==1 means run even when there is nothing to do
    my $check_for_dead              = 0;
    my $all_dead                    = 0;
    my $balance_semaphores          = 0;
    my $job_id_for_output           = 0;
    my $show_worker_stats           = 0;
    my $kill_worker_id              = 0;
    my $reset_job_id                = 0;
    my $reset_all_jobs_for_analysis = 0;        # DEPRECATED
    my $reset_failed_jobs_for_analysis = 0;     # DEPRECATED
    my $reset_all_jobs              = 0;
    my $reset_failed_jobs           = 0;

    $self->{'url'}                  = undef;
    $self->{'reg_conf'}             = undef;
    $self->{'reg_type'}             = undef;
    $self->{'reg_alias'}            = undef;
    $self->{'nosqlvc'}              = undef;

    $self->{'config_files'}         = [];

    $self->{'sleep_minutes'}        = 1;
    $self->{'retry_throwing_jobs'}  = undef;
    $self->{'can_respecialize'}     = undef;
    $self->{'hive_log_dir'}         = undef;
    $self->{'submit_log_dir'}       = undef;

    GetOptions(
                    # connection parameters
               'url=s'              => \$self->{'url'},
               'reg_conf|regfile=s' => \$self->{'reg_conf'},
               'reg_type=s'         => \$self->{'reg_type'},
               'reg_alias|regname=s'=> \$self->{'reg_alias'},
               'nosqlvc=i'          => \$self->{'nosqlvc'},     # can't use the binary "!" as it is a propagated option

                    # json config files
               'config_file=s@'     => $self->{'config_files'},

                    # loop control
               'run'                => \$run,
               'loop'               => \$loopit,
               'max_loops=i'        => \$max_loops,
               'keep_alive'         => \$keep_alive,
               'job_id|run_job_id=i'=> \$run_job_id,
               'force=i'            => \$force,
               'sleep=f'            => \$self->{'sleep_minutes'},

                    # meadow control
               'local!'                         => \$local,
               'meadow_type=s'                  => \$default_meadow_type,
               'total_running_workers_max=i'    => \$total_running_workers_max,
               'submit_workers_max=i'           => \$submit_workers_max,
               'submission_options=s'           => \$submission_options,

                    # worker control
               'job_limit=i'            => \$self->{'job_limit'},
               'life_span|lifespan=i'   => \$self->{'life_span'},
               'logic_name=s'           => \$self->{'logic_name'},
               'analyses_pattern=s'     => \$self->{'analyses_pattern'},
               'hive_log_dir|hive_output_dir=s'      => \$self->{'hive_log_dir'},
               'retry_throwing_jobs=i'  => \$self->{'retry_throwing_jobs'},
               'can_respecialize=i'     => \$self->{'can_respecialize'},
               'debug=i'                => \$self->{'debug'},
               'submit_log_dir=s'       => \$self->{'submit_log_dir'},

                    # other commands/options
               'h|help!'           => \$help,
               'v|versions!'       => \$report_versions,
               'sync!'             => \$sync,
               'dead!'             => \$check_for_dead,
               'killworker=i'      => \$kill_worker_id,
               'alldead!'          => \$all_dead,
               'balance_semaphores'=> \$balance_semaphores,
               'no_analysis_stats' => \$self->{'no_analysis_stats'},
               'worker_stats'      => \$show_worker_stats,
               'failed_jobs'       => \$show_failed_jobs,
               'reset_job_id=i'    => \$reset_job_id,
               'reset_failed_jobs_for_analysis=s' => \$reset_failed_jobs_for_analysis,
               'reset_all_jobs_for_analysis=s' => \$reset_all_jobs_for_analysis,
               'reset_failed_jobs' => \$reset_failed_jobs,
               'reset_all_jobs'    => \$reset_all_jobs,
               'job_output=i'      => \$job_id_for_output,
    );

    if ($help) { script_usage(0); }

    if($report_versions) {
        report_versions();
        exit(0);
    }

    my $config = Bio::EnsEMBL::Hive::Utils::Config->new(@{$self->{'config_files'}});

    if($run or $run_job_id) {
        $max_loops = 1;
    } elsif ($loopit or $keep_alive) {
        unless($max_loops) {
            $max_loops = -1; # unlimited
        }
    }

    if($self->{'url'} or $self->{'reg_alias'}) {
        $self->{'dba'} = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(
            -url                            => $self->{'url'},
            -reg_conf                       => $self->{'reg_conf'},
            -reg_type                       => $self->{'reg_type'},
            -reg_alias                      => $self->{'reg_alias'},
            -no_sql_schema_version_check    => $self->{'nosqlvc'},
        );
    } else {
        print "\nERROR : Connection parameters (url or reg_conf+reg_alias) need to be specified\n\n";
        script_usage(1);
    }

    if( $self->{'url'} ) {    # protect the URL that we pass to Workers by hiding the password in %ENV:
        $self->{'url'} = "'". $self->{'dba'}->dbc->url('EHIVE_PASS') ."'";
    }

    my $queen = $self->{'dba'}->get_Queen;

    my $pipeline_name = $self->{'dba'}->get_MetaAdaptor->get_value_by_key( 'hive_pipeline_name' );

    if($pipeline_name) {
        warn "Pipeline name: $pipeline_name\n";
    } else {
        print STDERR "+---------------------------------------------------------------------+\n";
        print STDERR "!                                                                     !\n";
        print STDERR "!                  WARNING:                                           !\n";
        print STDERR "!                                                                     !\n";
        print STDERR "! At the moment your pipeline doesn't have 'pipeline_name' defined.   !\n";
        print STDERR "! This may seriously impair your beekeeping experience unless you are !\n";
        print STDERR "! the only farm user. The name should be set in your PipeConfig file, !\n";
        print STDERR "! or if you are running an old pipeline you can just set it by hand   !\n";
        print STDERR "! in the 'meta' table.                                                !\n";
        print STDERR "!                                                                     !\n";
        print STDERR "+---------------------------------------------------------------------+\n";
    }

    if($run_job_id) {
        $submit_workers_max = 1;
    }

    $default_meadow_type = 'LOCAL' if($local);
    my $valley = Bio::EnsEMBL::Hive::Valley->new( $config, $default_meadow_type, $pipeline_name );

    my ($beekeeper_meadow_type, $beekeeper_meadow_name) = $valley->whereami();
    unless($beekeeper_meadow_type eq 'LOCAL') {
        die "beekeeper.pl detected it has been itself submitted to '$beekeeper_meadow_type/$beekeeper_meadow_name', but this mode of operation is not supported.\n"
           ."Please just run beekeeper.pl on a farm head node, preferably from under a 'screen' session.\n";
    }

    $valley->config_set('SubmitWorkersMax', $submit_workers_max) if(defined $submit_workers_max);

    my $default_meadow = $valley->get_default_meadow();
    warn "Default meadow: ".$default_meadow->signature."\n\n";

    $default_meadow->config_set('TotalRunningWorkersMax', $total_running_workers_max) if(defined $total_running_workers_max);
    $default_meadow->config_set('SubmissionOptions', $submission_options) if(defined $submission_options);

    if($reset_job_id) { $queen->reset_job_by_dbID_and_sync($reset_job_id); }

    if($job_id_for_output) {
        printf("===== job output\n");
        my $job = $self->{'dba'}->get_AnalysisJobAdaptor->fetch_by_dbID($job_id_for_output);
        print $job->toString. "\n";
    }

    if($reset_all_jobs_for_analysis) {
        die "Deprecated option -reset_all_jobs_for_analysis. Please use -reset_all_jobs in combination with -analyses_pattern <pattern>";
    }
    if($reset_failed_jobs_for_analysis) {
        die "Deprecated option -reset_failed_jobs_for_analysis. Please use -reset_failed_jobs in combination with -analyses_pattern <pattern>";
    }

    if ($kill_worker_id) {
        my $kill_worker = $queen->fetch_by_dbID($kill_worker_id)
            or die "Could not fetch worker with dbID='$kill_worker_id' to kill";

        unless( $kill_worker->cause_of_death() ) {
            if( my $meadow = $valley->find_available_meadow_responsible_for_worker( $kill_worker ) ) {

                if( $meadow->check_worker_is_alive_and_mine ) {
                    printf("Killing worker: %10d %35s %15s  %20s(%d) : ", 
                            $kill_worker->dbID, $kill_worker->host, $kill_worker->process_id, 
                            $kill_worker->analysis->logic_name, $kill_worker->analysis_id);

                    $meadow->kill_worker($kill_worker);
                    $kill_worker->cause_of_death('KILLED_BY_USER');
                    $queen->register_worker_death($kill_worker);
                         # what about clean-up? Should we do it here or not?
                } else {
                    die "According to the Meadow, the Worker (dbID=$kill_worker_id) is not running, so cannot kill";
                }
            } else {
                die "Cannot access the Meadow responsible for the Worker (dbID=$kill_worker_id), so cannot kill";
            }
        } else {
            die "According to the Queen, the Worker (dbID=$kill_worker_id) is not running, so cannot kill";
        }
    }

    if( $self->{'logic_name'} ) {   # FIXME: for now, logic_name will override analysis_pattern quietly
        warn "-logic_name is now deprecated, please use -analyses_pattern that extends the functionality of -logic_name .\n";
        $self->{'analyses_pattern'} = $self->{'logic_name'};
    }

    my $run_job;
    if($run_job_id) {
        $run_job = $self->{'dba'}->get_AnalysisJobAdaptor->fetch_by_dbID( $run_job_id )
            or die "Could not fetch Job with dbID=$run_job_id.\n";
    }

    my $list_of_analyses = $run_job
        ? [ $run_job->analysis ]
        : $self->{'dba'}->get_AnalysisAdaptor->fetch_all_by_pattern( $self->{'analyses_pattern'} );

    if( $self->{'analyses_pattern'} ) {
        if( @$list_of_analyses ) {
            print "Beekeeper : the following Analyses matched your -analysis_pattern '".$self->{'analyses_pattern'}."' : "
                .join(', ', map { $_->logic_name.'('.$_->dbID.')' } @$list_of_analyses)."\n\n";
        } else {
            die "Beekeeper : the -analyses_pattern '".$self->{'analyses_pattern'}."' did not match any Analyses.\n"
        }
    }

    if($reset_all_jobs || $reset_failed_jobs) {
        if ($reset_all_jobs and not $self->{'analyses_pattern'}) {
            die "Beekeeper : do you really want to reset *all* the jobs ? If yes, add \"-analyses_pattern '%'\" to the command line\n";
        }
        $self->{'dba'}->get_AnalysisJobAdaptor->reset_jobs_for_analysis_id( $list_of_analyses, $reset_all_jobs ); 
        $self->{'dba'}->get_Queen->synchronize_hive( $list_of_analyses );
    }

    if($all_dead)           { $queen->register_all_workers_dead(); }
    if($check_for_dead)     { $queen->check_for_dead_workers($valley, 1); }
    if($balance_semaphores) { $self->{'dba'}->get_AnalysisJobAdaptor->balance_semaphores( $list_of_analyses ); }

    if ($max_loops) { # positive $max_loop means limited, negative means unlimited

        run_autonomously($self, $max_loops, $keep_alive, $queen, $valley, $list_of_analyses, $self->{'analyses_pattern'}, $run_job_id, $force);

    } else {
            # the output of several methods will look differently depending on $analysis being [un]defined

        if($sync) {
            $queen->synchronize_hive( $list_of_analyses );
        }
        print $queen->print_status_and_return_reasons_to_exit( $list_of_analyses, !$self->{'no_analysis_stats'} );

        if($show_worker_stats) {
            print "\n===== List of live Workers according to the Queen: ======\n";
            foreach my $worker (@{ $queen->fetch_overdue_workers(0) }) {
                print $worker->toString(1)."\n";
            }
        }
        $self->{'dba'}->get_RoleAdaptor->print_active_role_counts;

        Bio::EnsEMBL::Hive::Scheduler::schedule_workers_resync_if_necessary($queen, $valley, $list_of_analyses);   # show what would be submitted, but do not actually submit

        if($show_failed_jobs) {
            print("===== failed jobs\n");
            my $failed_job_list = $self->{'dba'}->get_AnalysisJobAdaptor->fetch_all_by_analysis_id_status( $self->{'logic_name'} and $list_of_analyses , 'FAILED');

            foreach my $job (@{$failed_job_list}) {
                print $job->toString. "\n";
            }
        }
    }

    exit(0);
}

#######################
#
# subroutines
#
#######################


sub generate_worker_cmd {
    my ($self, $analyses_pattern, $run_job_id, $force) = @_;

    my $worker_cmd = $ENV{'EHIVE_ROOT_DIR'}.'/scripts/runWorker.pl';

    unless(-x $worker_cmd) {
        print("Can't run '$worker_cmd' script for some reason, please investigate.\n");
        exit(1);
    }

    foreach my $worker_option ('url', 'reg_conf', 'reg_type', 'reg_alias', 'nosqlvc', 'job_limit', 'life_span', 'retry_throwing_jobs', 'can_respecialize', 'hive_log_dir', 'debug') {
        if(defined(my $value = $self->{$worker_option})) {
            $worker_cmd .= " -${worker_option} $value";
        }
    }

        # special task:
    if ($run_job_id) {
        $worker_cmd .= " -job_id $run_job_id";
    } elsif ($analyses_pattern) {
        $worker_cmd .= " -analyses_pattern '".$analyses_pattern."'";
    }

    if (defined($force)) {
        $worker_cmd .= " -force $force";
    }

    return $worker_cmd;
}


sub run_autonomously {
    my ($self, $max_loops, $keep_alive, $queen, $valley, $list_of_analyses, $analyses_pattern, $run_job_id, $force) = @_;

    my $resourceless_worker_cmd = generate_worker_cmd($self, $analyses_pattern, $run_job_id, $force);

    my $beekeeper_pid = $$;

    my $iteration=0;
    my $reasons_to_exit;

    BKLOOP: while( ($iteration++ != $max_loops) or $keep_alive ) {  # NB: the order of conditions is important!

        print("\nBeekeeper : loop #$iteration ======================================================\n");

        $queen->check_for_dead_workers($valley, 0);

        if( $reasons_to_exit = $queen->print_status_and_return_reasons_to_exit( $list_of_analyses, !$self->{'no_analysis_stats'} )) {
            if($keep_alive) {
                print "Beekeeper : detected exit condition, but staying alive because of -keep_alive : ".$reasons_to_exit;
            } else {
                last BKLOOP;
            }
        }

        $self->{'dba'}->get_RoleAdaptor->print_active_role_counts;

        my $workers_to_submit_by_meadow_type_rc_name
            = Bio::EnsEMBL::Hive::Scheduler::schedule_workers_resync_if_necessary($queen, $valley, $list_of_analyses);

        if( keys %$workers_to_submit_by_meadow_type_rc_name ) {

            my $submit_log_subdir;

            if( $self->{'submit_log_dir'} ) {
                $submit_log_subdir = $self->{'submit_log_dir'}."/submit_bk${beekeeper_pid}_iter${iteration}";
                make_path( $submit_log_subdir );
            }

                # make sure the Resources are loaded fresh every time we need them:
            my $rc_id2name  = $self->{'dba'}->get_ResourceClassAdaptor->fetch_HASHED_FROM_resource_class_id_TO_name();
            my %meadow_type_rc_name2resource_param_list = ();
            foreach my $rd (@{ $self->{'dba'}->get_ResourceDescriptionAdaptor->fetch_all() }) {
                $meadow_type_rc_name2resource_param_list{ $rd->meadow_type() }{ $rc_id2name->{$rd->resource_class_id} } = [ $rd->submission_cmd_args, $rd->worker_cmd_args ];
            }

            foreach my $meadow_type (keys %$workers_to_submit_by_meadow_type_rc_name) {

                my $this_meadow = $valley->available_meadow_hash->{$meadow_type};

                foreach my $rc_name (keys %{ $workers_to_submit_by_meadow_type_rc_name->{$meadow_type} }) {
                    my $this_meadow_rc_worker_count = $workers_to_submit_by_meadow_type_rc_name->{$meadow_type}{$rc_name};

                    print "\nBeekeeper : submitting $this_meadow_rc_worker_count workers (rc_name=$rc_name) to ".$this_meadow->signature()."\n";

                    my ($submission_cmd_args, $worker_cmd_args) = @{ $meadow_type_rc_name2resource_param_list{ $meadow_type }{ $rc_name } || [] };

                    my $specific_worker_cmd = $resourceless_worker_cmd
                                            . " -rc_name $rc_name"
                                            . (defined($worker_cmd_args) ? " $worker_cmd_args" : '');

                    $this_meadow->submit_workers($specific_worker_cmd, $this_meadow_rc_worker_count, $iteration,
                                                    $rc_name, $submission_cmd_args || '', $submit_log_subdir);
                }
            }
        } else {
            print "\nBeekeeper : not submitting any workers this iteration\n";
        }

        if( $iteration != $max_loops ) {    # skip the last sleep
            $self->{'dba'}->dbc->disconnect_if_idle;
            printf("Beekeeper : going to sleep for %.2f minute(s). Expect next iteration at %s\n", $self->{'sleep_minutes'}, scalar localtime(time+$self->{'sleep_minutes'}*60));
            sleep($self->{'sleep_minutes'}*60);  

            unless($run_job_id) {   # refresh the data from analysis_base table
                $list_of_analyses = $self->{'dba'}->get_AnalysisAdaptor->fetch_all_by_pattern( $analyses_pattern );
            }
        }
    }

    print "Beekeeper : stopped looping because ".( $reasons_to_exit || "the number of loops was limited by $max_loops and this limit expired\n");

    printf("Beekeeper: dbc %d disconnect cycles\n", $self->{'dba'}->dbc->disconnect_count);
}


__DATA__

=pod

=head1 NAME

    beekeeper.pl [options]

=head1 DESCRIPTION

    The Beekeeper is in charge of interfacing between the Queen and a compute resource or 'compute farm'.
    Its job is to initialize/sync the eHive database (via the Queen), query the Queen if it needs any workers
    and to send the requested number of workers to open machines via the runWorker.pl script.

    It is also responsible for interfacing with the Queen to identify workers which died
    unexpectedly so that she can free the dead workers and reclaim unfinished jobs.

=head1 USAGE EXAMPLES

        # Usually run after the pipeline has been created to calculate the internal statistics necessary for eHive functioning
    beekeeper.pl -url mysql://username:secret@hostname:port/ehive_dbname -sync

        # Do not run any additional Workers, just check for the current status of the pipeline:
    beekeeper.pl -url mysql://username:secret@hostname:port/ehive_dbname

        # Run the pipeline in automatic mode (-loop), run all the workers locally (-meadow_type LOCAL) and allow for 3 parallel workers (-total_running_workers_max 3)
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -meadow_type LOCAL -total_running_workers_max 3 -loop

        # Run in automatic mode, but only restrict to running blast-related analyses with the exception of analyses 4..6
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -analyses_pattern 'blast%-4..6' -loop

        # Restrict the normal execution to one iteration only - can be used for testing a newly set up pipeline
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -run

        # Reset failed 'buggy_analysis' jobs to 'READY' state, so that they can be run again
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -analyses_pattern buggy_analysis -reset_failed_jobs

        # Do a cleanup: find and bury dead workers, reclaim their jobs
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -dead

=head1 OPTIONS

=head2 Connection parameters

    -reg_conf <path>       : path to a Registry configuration file
    -reg_type <string>     : type of the registry entry ('hive', 'core', 'compara', etc - defaults to 'hive')
    -reg_alias <string>    : species/alias name for the Hive DBAdaptor
    -url <url string>      : url defining where hive database is located

=head2 Configs overriding

    -config_file <string>  : json file (with absolute path) to override the default configurations (could be multiple)

=head2 Looping control

    -loop                  : run autonomously, loops and sleeps
    -max_loops <num>       : perform max this # of loops in autonomous mode
    -keep_alive            : do not stop when there are no more jobs to do - carry on looping
    -job_id <job_id>       : run 1 iteration for this job_id
    -run                   : run 1 iteration of automation loop
    -sleep <num>           : when looping, sleep <num> minutes (default 1 min)

=head2 Current Meadow control

    -meadow_type <string>               : the desired Meadow class name, such as 'LSF' or 'LOCAL'
    -total_running_workers_max <num>    : max # workers to be running in parallel
    -submit_workers_max <num>           : max # workers to create per loop iteration
    -submission_options <string>        : passes <string> to the Meadow submission command as <options> (formerly lsf_options)
    -submit_log_dir <dir>               : record submission output+error streams into files under the given directory (to see why some workers fail after submission)

=head2 Worker control

    -analyses_pattern <string>  : restrict the sync operation, printing of stats or looping of the beekeeper to the specified subset of analyses
    -can_respecialize <0|1>     : allow workers to re-specialize into another analysis (within resource_class) after their previous analysis was exhausted
    -life_span <num>            : life_span limit for each worker
    -job_limit <num>            : #jobs to run before worker can die naturally
    -retry_throwing_jobs 0|1    : if a job dies *knowingly*, should we retry it by default?
    -hive_log_dir <path>        : directory where stdout/stderr of the hive is redirected
    -debug <debug_level>        : set debug level of the workers

=head2 Other commands/options

    -help                  : print this help
    -versions              : report both Hive code version and Hive database schema version
    -dead                  : detect all unaccounted dead workers and reset their jobs for resubmission
    -alldead               : tell the database all workers are dead (no checks are performed in this mode, so be very careful!)
    -balance_semaphores    : set all semaphore_counts to the numbers of unDONE fan jobs (emergency use only)
    -no_analysis_stats     : don't show status of each analysis
    -worker_stats          : show status of each running worker
    -failed_jobs           : show all failed jobs
    -reset_job_id <num>    : reset a job back to READY so it can be rerun
    -reset_failed_jobs     : reset FAILED jobs of -analyses_filter'ed ones back to READY so they can be rerun
    -reset_all_jobs        : reset ALL jobs of -analyses_filter'ed ones back to READY so they can be rerun

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

