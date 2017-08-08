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


use File::Path 'make_path';
use Getopt::Long qw(:config no_auto_abbrev);

use Bio::EnsEMBL::Hive::DBSQL::LogMessageAdaptor ('store_beekeeper_message');
use Bio::EnsEMBL::Hive::Utils ('script_usage', 'destringify', 'report_versions');
use Bio::EnsEMBL::Hive::Utils::Slack ('send_beekeeper_message_to_slack');
use Bio::EnsEMBL::Hive::Utils::Config;
use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Valley;
use Bio::EnsEMBL::Hive::Beekeeper;
use Bio::EnsEMBL::Hive::Scheduler;


main();


sub main {
    $|=1;   # make STDOUT unbuffered (STDERR is unbuffered anyway)

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
    my $run_job_id                  = undef;
    my $force                       = undef;
    my $check_for_dead              = 0;
    my $bury_unkwn_workers          = 0;
    my $all_dead                    = 0;
    my $balance_semaphores          = 0;
    my $job_id_for_output           = 0;
    my $show_worker_stats           = 0;
    my $kill_worker_id              = 0;
    my $keep_alive                  = 0;        # DEPRECATED
    my $reset_job_id                = 0;
    my $reset_all_jobs_for_analysis = 0;        # DEPRECATED
    my $reset_failed_jobs_for_analysis = 0;     # DEPRECATED
    my $reset_all_jobs              = 0;    # Mark DONE, PASSED_ON and FAILED jobs to READY
    my $reset_failed_jobs           = 0;    # Mark FAILED jobs to READY
    my $reset_done_jobs             = 0;    # Mark DONE and PASSED_ON jobs to READY
    my $unblock_semaphored_jobs     = 0;    # Mark SEMAPHORED jobs to READY
    my $forgive_failed_jobs         = 0;    # Mark FAILED jobs to DONE
    my $discard_ready_jobs          = 0;    # Mark READY jobs to DONE

    $self->{'url'}                  = undef;
    $self->{'reg_conf'}             = undef;
    $self->{'reg_type'}             = undef;
    $self->{'reg_alias'}            = undef;
    $self->{'nosqlvc'}              = undef;

    $self->{'config_files'}         = [];

    $self->{'sleep_minutes'}        = 1;
    $self->{'max_loops'}            = 0;
    $self->{'retry_throwing_jobs'}  = undef;
    $self->{'loop_until'}           = undef;
    $self->{'can_respecialize'}     = undef;
    $self->{'hive_log_dir'}         = undef;
    $self->{'submit_log_dir'}       = undef;
    $self->{'worker_delay_startup_seconds'} = undef;
    $self->{'worker_crash_on_startup_prob'} = undef;

    # store all the options passed on the command line for registration
    # we re-create this a bit later, so that we can protect any passwords
    # that might be passed in a URL
    my @original_argv = @ARGV;

    GetOptions(
                    # connection parameters
               'url=s'                        => \$self->{'url'},
               'reg_conf|regfile|reg_file=s'  => \$self->{'reg_conf'},
               'reg_type=s'                   => \$self->{'reg_type'},
               'reg_alias|regname|reg_name=s' => \$self->{'reg_alias'},
               'nosqlvc=i'                    => \$self->{'nosqlvc'},     # can't use the binary "!" as it is a propagated option

                    # json config files
               'config_file=s@'     => $self->{'config_files'},

                    # loop control
               'run'                => \$run,
               'loop'               => \$loopit,
               'max_loops=i'        => \$self->{'max_loops'},
               'loop_until=s'       => \$self->{'loop_until'},
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
               'job_limit=i'                    => \$self->{'job_limit'},
               'life_span|lifespan=i'           => \$self->{'life_span'},
               'logic_name=s'                   => \$self->{'logic_name'},
               'analyses_pattern=s'             => \$self->{'analyses_pattern'},
               'hive_log_dir|hive_output_dir=s' => \$self->{'hive_log_dir'},
               'retry_throwing_jobs=i'          => \$self->{'retry_throwing_jobs'},
               'can_respecialize=i'             => \$self->{'can_respecialize'},
               'debug=i'                        => \$self->{'debug'},
               'submit_log_dir=s'               => \$self->{'submit_log_dir'},
               'worker_delay_startup_seconds=i' => \$self->{'worker_delay_startup_seconds'},
               'worker_crash_on_startup_prob=f' => \$self->{'worker_crash_on_startup_prob'},

                    # other commands/options
               'h|help!'           => \$help,
               'v|version|versions!'    => \$report_versions,
               'sync!'             => \$sync,
               'dead!'             => \$check_for_dead,
               'unkwn!'            => \$bury_unkwn_workers,
               'killworker=i'      => \$kill_worker_id,
               'alldead!'          => \$all_dead,
               'balance_semaphores'=> \$balance_semaphores,
               'worker_stats'      => \$show_worker_stats,
               'failed_jobs'       => \$show_failed_jobs,
               'reset_job_id=i'    => \$reset_job_id,
               'reset_failed_jobs_for_analysis=s' => \$reset_failed_jobs_for_analysis,
               'reset_all_jobs_for_analysis=s' => \$reset_all_jobs_for_analysis,
               'reset_failed_jobs' => \$reset_failed_jobs,
               'reset_all_jobs'    => \$reset_all_jobs,
               'reset_done_jobs'   => \$reset_done_jobs,
               'discard_ready_jobs'     => \$discard_ready_jobs,
               'forgive_failed_jobs'    => \$forgive_failed_jobs,
               'unblock_semaphored_jobs'    => \$unblock_semaphored_jobs,
               'job_output=i'      => \$job_id_for_output,
    ) or die "Error in command line arguments\n";

    if (@ARGV) {
        die "ERROR: There are invalid arguments on the command-line: ". join(" ", @ARGV). "\n";
    }

    if ($help) { script_usage(0); }

    if($report_versions) {
        report_versions();
        exit(0);
    }

    my $config = Bio::EnsEMBL::Hive::Utils::Config->new(@{$self->{'config_files'}});

    # if -keep_alive passed, ensure looping is on and loop_until is forever
    if ($keep_alive) {
        $self->{'loop_until'} = 'FOREVER';
        $loopit = 1;
    }

    # if user has specified -loop_until, ensure looping is turned on
    if ($self->{'loop_until'}) {
        $loopit = 1;
    }

    # if loop_until hasn't been set by the user, or defaulted by a flag,
    # set it to ANALYSIS_FAILURE
    unless ($self->{'loop_until'}) {
        $self->{'loop_until'} = 'ANALYSIS_FAILURE';
    }

    if($run or $run_job_id) {
        $self->{'max_loops'} = 1;
    } elsif ($loopit) {
        unless($self->{'max_loops'}) {
            $self->{'max_loops'} = -1; # unlimited
        }
    }

    if($self->{'url'} or $self->{'reg_alias'}) {

        $self->{'pipeline'} = Bio::EnsEMBL::Hive::HivePipeline->new(
            -url                            => $self->{'url'},
            -reg_conf                       => $self->{'reg_conf'},
            -reg_type                       => $self->{'reg_type'},
            -reg_alias                      => $self->{'reg_alias'},
            -no_sql_schema_version_check    => $self->{'nosqlvc'},
        );

        $self->{'dba'} = $self->{'pipeline'}->hive_dba();

    } else {
        print "\nERROR : Connection parameters (url or reg_conf+reg_alias) need to be specified\n\n";
        script_usage(1);
    }

    if( $self->{'url'} ) {    # protect the URL that we pass to Workers by hiding the password in %ENV:
        $self->{'url'} = "'". $self->{'dba'}->dbc->url('EHIVE_PASS') ."'";

    # find the url in the original @argv, remove it, then replace with the new, protected url
        my ($url_flag_index) = grep {$original_argv[$_] eq '-url'} (0..(scalar(@original_argv) - 1));
        $original_argv[$url_flag_index + 1] = $self->{'dba'}->dbc->url('EHIVE_PASS');
    }
    $self->{'options'} = join(" ", @original_argv);

    # make -loop_until case insensitive
    $self->{'loop_until'} = uc($self->{'loop_until'});

    my @allowed_loop_until_values = qw(ANALYSIS_FAILURE FOREVER JOB_FAILURE NO_WORK);
    unless (grep {$_ eq $self->{'loop_until'}} @allowed_loop_until_values) {
        die sprintf('"%s" is not a recognized value for -loop_until. Use one of %s', $self->{'loop_until'}, join('/', @allowed_loop_until_values));
    }

    my $pipeline_name = $self->{'pipeline'}->hive_pipeline_name;

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
    $self->{'available_meadow_list'} = $valley->get_available_meadow_list();

    $valley->config_set('SubmitWorkersMax', $submit_workers_max) if(defined $submit_workers_max);

    my $default_meadow = $valley->get_default_meadow();
    warn "Default meadow: ".$default_meadow->signature."\n\n";

    $default_meadow->config_set('TotalRunningWorkersMax', $total_running_workers_max) if(defined $total_running_workers_max);
    $default_meadow->config_set('SubmissionOptions', $submission_options) if(defined $submission_options);

    my $queen = $self->{'dba'}->get_Queen;

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

    if( $self->{'logic_name'} ) {   # FIXME: for now, logic_name will override analyses_pattern quietly
        warn "-logic_name is now deprecated, please use -analyses_pattern that extends the functionality of -logic_name .\n";
        $self->{'analyses_pattern'} = $self->{'logic_name'};
    }

    # May die if running within a non-LOCAL meadow
    $self->{'beekeeper'} = register_beekeeper($valley, $self);
    $self->{'logmessage_adaptor'} = $self->{'dba'}->get_LogMessageAdaptor();

    # Check other beekeepers in our meadow to see if they are still alive
    $self->{'beekeeper'}->adaptor->bury_other_beekeepers($self->{'beekeeper'});

    if ($kill_worker_id) {
        my $kill_worker;
        eval {$kill_worker = $queen->fetch_by_dbID($kill_worker_id) or die};
        if ($@) {
            log_and_die($self, "Could not fetch worker with dbID='$kill_worker_id' to kill");
        }

        unless( $kill_worker->cause_of_death() ) {
            if( my $meadow = $valley->find_available_meadow_responsible_for_worker( $kill_worker ) ) {

                if( $meadow->check_worker_is_alive_and_mine($kill_worker) ) {
                    printf("Killing worker: %10d %35s %15s : ",
                            $kill_worker->dbID, $kill_worker->meadow_host, $kill_worker->process_id);

                    $meadow->kill_worker($kill_worker);
                    $kill_worker->cause_of_death('KILLED_BY_USER');
                    $queen->register_worker_death($kill_worker);
                    # what about clean-up? Should we do it here or not?
                } else {
                    log_and_die($self, "According to the Meadow, the Worker (dbID=$kill_worker_id) is not running, so cannot kill");
                }
            } else {
                log_and_die($self, "Cannot access the Meadow responsible for the Worker (dbID=$kill_worker_id), so cannot kill");
            }
        } else {
            log_and_die($self, "According to the Queen, the Worker (dbID=$kill_worker_id) is not running, so cannot kill");
        }
    }

    my $run_job;
    if($run_job_id) {
        eval {$run_job = $self->{'dba'}->get_AnalysisJobAdaptor->fetch_by_dbID( $run_job_id ) or die};
        if ($@) {
            log_and_die($self, "Could not fetch Job with dbID=$run_job_id.\n");
        }
    }

    my $list_of_analyses = $run_job
        ? [ $run_job->analysis ]
        : $self->{'pipeline'}->collection_of('Analysis')->find_all_by_pattern( $self->{'analyses_pattern'} );

    if( $self->{'analyses_pattern'} ) {
        if( @$list_of_analyses ) {
            print "Beekeeper : the following Analyses matched your -analyses_pattern '".$self->{'analyses_pattern'}."' : "
                . join(', ', map { $_->logic_name.'('.$_->dbID.')' } sort {$a->dbID <=> $b->dbID} @$list_of_analyses)
                . "\nBeekeeper : ", scalar($self->{'pipeline'}->collection_of('Analysis')->list())-scalar(@$list_of_analyses), " Analyses are not shown\n\n";
        } else {
            log_and_die($self, "Beekeeper : the -analyses_pattern '".$self->{'analyses_pattern'}."' did not match any Analyses.\n");
        }
    }

    my $has_task = ($reset_all_jobs || $reset_failed_jobs || $reset_done_jobs || $unblock_semaphored_jobs || $forgive_failed_jobs || $discard_ready_jobs);
    if($reset_all_jobs || $reset_failed_jobs || $reset_done_jobs) {
        if (($reset_all_jobs || $reset_done_jobs) and not $self->{'analyses_pattern'}) {
            log_and_die($self, "Beekeeper : do you really want to reset *all* the jobs ? If yes, add \"-analyses_pattern '%'\" to the command line\n");
        }
        my $statuses_to_reset = $reset_failed_jobs ? [ 'FAILED' ] : ($reset_done_jobs ? [ 'DONE', 'PASSED_ON' ] : [ 'DONE', 'FAILED', 'PASSED_ON' ]);
        $self->{'dba'}->get_AnalysisJobAdaptor->reset_jobs_for_analysis_id( $list_of_analyses, $statuses_to_reset );
    }

    if ($unblock_semaphored_jobs) {
        $self->{'dba'}->get_AnalysisJobAdaptor->unblock_jobs_for_analysis_id( $list_of_analyses );
    }

    if ($discard_ready_jobs) {
        $self->{'dba'}->get_AnalysisJobAdaptor->discard_jobs_for_analysis_id( $list_of_analyses, 'READY' );
    }

    if ($forgive_failed_jobs) {
        $self->{'dba'}->get_AnalysisJobAdaptor->discard_jobs_for_analysis_id( $list_of_analyses, 'FAILED' );
    }

    $queen->synchronize_hive( $list_of_analyses ) if $has_task;

    if($all_dead)           { $queen->register_all_workers_dead(); }
    if($check_for_dead)     { $queen->check_for_dead_workers($valley, 1); }
    if($bury_unkwn_workers) { $queen->check_for_dead_workers($valley, 1, 1); }
    if($balance_semaphores) { $self->{'dba'}->get_AnalysisJobAdaptor->balance_semaphores( $list_of_analyses ); }

    if ($self->{'max_loops'}) { # positive $max_loop means limited, negative means unlimited

        run_autonomously($self, $self->{'pipeline'}, $self->{'max_loops'}, $self->{'loop_until'}, $valley, $list_of_analyses, $self->{'analyses_pattern'}, $run_job_id, $force);

    } else {
        # the output of several methods will look differently depending on $analysis being [un]defined

        if($sync) {
            $queen->synchronize_hive( $list_of_analyses );
        }
        my $reasons_to_exit =  $queen->print_status_and_return_reasons_to_exit( $list_of_analyses, $self->{'debug'} );

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
            my $failed_job_list = $self->{'dba'}->get_AnalysisJobAdaptor->fetch_all_by_analysis_id_status( $list_of_analyses , 'FAILED');

            foreach my $job (@{$failed_job_list}) {
                print $job->toString. "\n";
            }
        }
        $self->{'beekeeper'}->set_cause_of_death('LOOP_LIMIT');
    }
    exit(0);
}

#######################
#
# subroutines
#
#######################

sub log_and_die {
    my ($self, $message) = @_;

    my $beekeeper = $self->{'beekeeper'};
    $self->{'logmessage_adaptor'}->store_beekeeper_message($beekeeper->dbID, $message, 'PIPELINE_ERROR', 'TASK_FAILED');
    $beekeeper->set_cause_of_death('TASK_FAILED');
    die $message;
}

sub generate_worker_cmd {
    my ($self, $analyses_pattern, $run_job_id, $force) = @_;

    my $worker_cmd = $ENV{'EHIVE_ROOT_DIR'}.'/scripts/runWorker.pl';

    unless(-x $worker_cmd) {
        print("Can't run '$worker_cmd' script for some reason, please investigate.\n");
        exit(1);
    }

    foreach my $worker_option ('url', 'reg_conf', 'reg_type', 'reg_alias', 'nosqlvc', 'job_limit', 'life_span', 'retry_throwing_jobs', 'can_respecialize',
                               'worker_delay_startup_seconds', 'worker_crash_on_startup_prob', 'hive_log_dir', 'debug') {
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

sub register_beekeeper {
    my ($valley, $self) = @_;

    my $loop_limit = undef;
    if ($self->{'max_loops'} > -1) {
        $loop_limit = $self->{'max_loops'};
    }

    my $meadow_signatures = join(",",
        map {$_->signature} @{$self->{'available_meadow_list'}});

    # The new instance is partly initalized with the output of Valley::whereami()
    my $beekeeper = Bio::EnsEMBL::Hive::Beekeeper->new_from_Valley($valley,
        'sleep_minutes'     => $self->{'sleep_minutes'},
        'analyses_pattern'  => $self->{'analyses_pattern'},
        'loop_limit'        => $loop_limit,
        'loop_until'        => $self->{'loop_until'},
        'options'           => $self->{'options'},
        'meadow_signatures' => $meadow_signatures,
    );

    $self->{'dba'}->get_BeekeeperAdaptor->store($beekeeper);
    unless ($self->{'beekeeper_id'} = $beekeeper->dbID) {
        die "There was a problem registering this beekeeper with the hive database.";
    }
    return $beekeeper;
}

sub run_autonomously {
    my ($self, $pipeline, $max_loops, $loop_until, $valley, $list_of_analyses, $analyses_pattern, $run_job_id, $force) = @_;

    my $hive_dba    = $pipeline->hive_dba;
    my $queen       = $hive_dba->get_Queen;
    my $meadow_user = $self->{'beekeeper'}->meadow_user;

    my $resourceless_worker_cmd = generate_worker_cmd($self, $analyses_pattern, $run_job_id, $force);

    my $iteration=0;
    my $reasons_to_exit;

    BKLOOP: while( ($iteration++ != $max_loops) or ($loop_until eq 'FOREVER') ) {  # NB: the order of conditions is important!

        print("\nBeekeeper : loop #$iteration ======================================================\n");

        $queen->check_for_dead_workers($valley, 0);

        # this section is where the beekeeper decides whether or not to stop looping
        $reasons_to_exit = $queen->print_status_and_return_reasons_to_exit( $list_of_analyses, $self->{'debug'});
        my @job_fail_statuses = grep({$_->{'exit_status'} eq 'JOB_FAILED'} @$reasons_to_exit);
        my @analysis_fail_statuses = grep({$_->{'exit_status'} eq 'ANALYSIS_FAILED'} @$reasons_to_exit);
        my @no_work_statuses = grep({$_->{'exit_status'} eq 'NO_WORK'} @$reasons_to_exit);

        my $found_reason_to_exit = 0;

        if (($loop_until eq 'JOB_FAILURE') &&
            (scalar(@job_fail_statuses)) > 0) {
            print "Beekeeper : last loop because at least one job failed and loop-until mode is '$loop_until'\n";
            print "Beekeeper : details from analyses with failed jobs:\n";
            print join("\n", map {$_->{'message'}} @job_fail_statuses) . "\n";
            $found_reason_to_exit = 1;
            last BKLOOP;
        }

        if (scalar(@analysis_fail_statuses > 0)) {
            # at least one analysis has hit its fault tolerance
            if (($loop_until eq 'FOREVER') ||
                ($loop_until eq 'NO_WORK')) {
                if (scalar(@no_work_statuses) == 0) {
                    print "Beekeeper : detected the following exit condition(s), but staying alive because loop-until mode is set to '$loop_until' :\n" .
                        join(", ", map {$_->{'message'}} @analysis_fail_statuses) . "\n";
                }
            } else {
                # loop_until_mode is either job_failure or analysis_failure, and both of these exit on analysis failure
                unless ($found_reason_to_exit) {
                    print "Beekeeper : last loop because at least one analysis failed and loop-until mode is '$loop_until'\n";
                    print "Beekeeper : details from analyses with failed jobs:\n";
                    print join("\n", map {$_->{'message'}} @analysis_fail_statuses) . "\n";
                    $found_reason_to_exit = 1;
                    last BKLOOP;
                }
            }
        }

        if ((scalar(@no_work_statuses) > 0) &&
            ($loop_until ne 'FOREVER')) {
            print "Beekeeper : last loop because there is no more work and loop-until mode is '$loop_until'\n"
                unless ($found_reason_to_exit);
            last BKLOOP;
        }

        # end of testing for loop end conditions

        $hive_dba->get_RoleAdaptor->print_active_role_counts;

        my $workers_to_submit_by_meadow_type_rc_name
            = Bio::EnsEMBL::Hive::Scheduler::schedule_workers_resync_if_necessary($queen, $valley, $list_of_analyses);

        if( keys %$workers_to_submit_by_meadow_type_rc_name ) {

            my $submit_log_subdir;

            if( $self->{'submit_log_dir'} ) {
                $submit_log_subdir = $self->{'submit_log_dir'}."/submit_bk".$self->{'beekeeper_id'}."_iter${iteration}";
                make_path( $submit_log_subdir );
            }

                # create an "index" over the freshly loaded RC/RD collections:
            my %meadow_type_rc_name2resource_param_list = ();
            foreach my $rd ( $pipeline->collection_of('ResourceDescription')->list ) {
                my $rc_name = $rd->resource_class->name;
                $meadow_type_rc_name2resource_param_list{ $rd->meadow_type }{ $rc_name } = [ $rd->submission_cmd_args, $rd->worker_cmd_args ];
            }

            foreach my $meadow_type (keys %$workers_to_submit_by_meadow_type_rc_name) {

                my $this_meadow = $valley->available_meadow_hash->{$meadow_type};

                foreach my $rc_name (keys %{ $workers_to_submit_by_meadow_type_rc_name->{$meadow_type} }) {
                    my $this_meadow_rc_worker_count = $workers_to_submit_by_meadow_type_rc_name->{$meadow_type}{$rc_name};

                    my $submission_message = "submitting $this_meadow_rc_worker_count workers (rc_name=$rc_name) to ".$this_meadow->signature();
                    print "\nBeekeeper : $submission_message\n";
                    $self->{'logmessage_adaptor'}->store_beekeeper_message($self->{'beekeeper_id'},
                        "loop iteration $iteration, $submission_message",
                        'INFO', 'ALIVE');

                    my ($submission_cmd_args, $worker_cmd_args) = @{ $meadow_type_rc_name2resource_param_list{ $meadow_type }{ $rc_name } || [] };

                    my $specific_worker_cmd = $resourceless_worker_cmd
                                            . (defined($worker_cmd_args) ? " $worker_cmd_args" : '')
                                            . ' -preregistered';

                    my $meadow_process_ids = $this_meadow->submit_workers_return_meadow_pids(
                        $specific_worker_cmd, $this_meadow_rc_worker_count, $iteration, $rc_name, $submission_cmd_args || '', $submit_log_subdir);

                    warn "Submitted the following process_ids to ".$this_meadow->signature.": ".join(', ', @$meadow_process_ids)."\n";

                    my $resource_class  = $pipeline->collection_of('ResourceClass')->find_one_by('name', $rc_name);
                    my $meadow_name     = $this_meadow->cached_name;

                    my @pre_allocated_workers = map {
                            Bio::EnsEMBL::Hive::Worker->new(
                                'meadow_type'       => $meadow_type,                # non-unique key components
                                'meadow_name'       => $meadow_name,
                                'meadow_user'       => $meadow_user,
                                'process_id'        => $_,

                                'resource_class'    => $resource_class,             # non-key, but known at the time of pre-allocation
                                'beekeeper_id'      => $self->{'beekeeper_id'},

                                'status'            => 'SUBMITTED',
                            )
                    } @$meadow_process_ids;

                    $queen->store( \@pre_allocated_workers );
                }
            }
        } else {
            print "\nBeekeeper : not submitting any workers this iteration\n";
            $self->{'logmessage_adaptor'}->store_beekeeper_message($self->{'beekeeper_id'},
                "loop iteration $iteration, 0 workers submitted",
                'INFO', 'ALIVE');
        }

        if( $iteration != $max_loops ) {    # skip the last sleep
            while (1) {
                $hive_dba->dbc->disconnect_if_idle;
                printf("Beekeeper : going to sleep for %.2f minute(s). Expect next iteration at %s\n", $self->{'sleep_minutes'}, scalar localtime(time+$self->{'sleep_minutes'}*60));
                sleep($self->{'sleep_minutes'}*60);
                # this is a good time to check up on other beekeepers as well:
                $self->{'beekeeper'}->adaptor->bury_other_beekeepers($self->{'beekeeper'});
                if ($self->{'beekeeper'}->check_if_blocked()) {
                    print "Beekeeper : We have been blocked !\n".
                          "This can happen if a job has explicitly required beekeeper to stop (have a look at log_message).\n".
                          "It may also happen if someone has set is_blocked=1 in the beekeeper table for beekeeper_id=".$self->{'beekeeper_id'}.".\n";
                } else {
                    last;
                }
            }

            # after waking up reload Resources and Analyses to stay current.
            unless($run_job_id) {
                # reset all the collections so that fresher data will be used at this iteration:
                $pipeline->invalidate_collections();
                $pipeline->invalidate_hive_current_load();

                $list_of_analyses = $pipeline->collection_of('Analysis')->find_all_by_pattern( $analyses_pattern );
            }
        }
    }

    # in this section, the beekeeper determines why it exited, sets an appropriate cause of death,
    # and prints/logs an appropriate message
    my @stringified_reasons_builder;
    my $beekeeper_cause_of_death;
    my $cause_of_death_is_error;
    my %exit_statuses; # keep a set of unique exit statuses seen
    if ($reasons_to_exit) {
        foreach my $reason_to_exit (@$reasons_to_exit) {
            $exit_statuses{$reason_to_exit->{'exit_status'}} = 1;
            push(@stringified_reasons_builder, $reason_to_exit->{'message'});
        }
    }

    my $stringified_reasons = join(", ", @stringified_reasons_builder);

    if (($loop_until eq 'JOB_FAILURE') &&
        (grep(/JOB_FAILED/, keys(%exit_statuses)))) {
        $beekeeper_cause_of_death = 'JOB_FAILED';
        $cause_of_death_is_error = 1;
    }

    if (($loop_until eq 'ANALYSIS_FAILURE') &&
        (grep(/ANALYSIS_FAILED/, keys(%exit_statuses)))) {
        $beekeeper_cause_of_death = 'ANALYSIS_FAILED';
        $cause_of_death_is_error = 1;
    }

    if (!$beekeeper_cause_of_death) {
        if (grep(/NO_WORK/, keys(%exit_statuses))) {
            $beekeeper_cause_of_death = 'NO_WORK';
        } else {
            $beekeeper_cause_of_death = 'LOOP_LIMIT';
        }
        $cause_of_death_is_error = 0;
    }

    $self->{'logmessage_adaptor'}->store_beekeeper_message($self->{'beekeeper_id'},
        "stopped looping because of $stringified_reasons",
        $cause_of_death_is_error ? 'PIPELINE_ERROR' : 'INFO',
        $beekeeper_cause_of_death);

    if ($reasons_to_exit and $ENV{EHIVE_SLACK_WEBHOOK}) {
        send_beekeeper_message_to_slack($ENV{EHIVE_SLACK_WEBHOOK}, $self->{'pipeline'}, $cause_of_death_is_error, 1, $stringified_reasons, $loop_until);
    }

    $self->{'beekeeper'}->set_cause_of_death($beekeeper_cause_of_death);
    printf("Beekeeper: dbc %d disconnect cycles\n", $hive_dba->dbc->disconnect_count);
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

=over

=item    -reg_conf <path>

Path to a Registry configuration file

=item    -reg_type <string>

Type of the registry entry ('hive', 'core', 'compara', etc. - defaults to 'hive')

=item    -reg_alias <string>

Species / alias name for the Hive DBAdaptor

=item    -url <url string>

URL defining where hive database is located

=item    -nosqlvc <0|1>

Skip sql version check if 1

=back

=head2 Configs overriding

=over

=item    -config_file <string>

JSON file (with absolute path) to override the default configurations (could be multiple)

=back

=head2 Looping control

    -loop                  : run autonomously, loops and sleeps. Equivalent to -loop_until ANALYSIS_FAILURE
    -loop_until            : sets the level of event that will cause the beekeeper to stop looping:
                           : JOB_FAILURE      = stop looping if any job fails
                           : ANALYSIS_FAILURE = stop looping if any analysis has job failures exceeding
                           :     its fault tolerance
                           : NO_WORK          = ignore job and analysis faliures, keep looping until there is no work
                           : FOREVER          = ignore failures and no work, keep looping
    -keep_alive            : (Deprecated) alias for -loop_until FOREVER
    -max_loops <num>       : perform max this # of loops in autonomous mode. The beekeeper will stop when
                           : it has performed max_loops loops, even in FOREVER mode
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

    -analyses_pattern <string>              : restrict the sync operation, printing of stats or looping of the beekeeper to the specified subset of analyses
    -can_respecialize <0|1>                 : allow workers to re-specialize into another analysis (within resource_class) after their previous analysis was exhausted
    -force                                  : run all workers with -force (see runWorker.pl)
    -killworker <worker_id>                 : kill worker by worker_id
    -life_span <num>                        : number of minutes each worker is allowed to run
    -job_limit <num>                        : #jobs to run before worker can die naturally
    -retry_throwing_jobs <0|1>              : if a job dies *knowingly*, should we retry it by default?
    -hive_log_dir <path>                    : directory where stdout/stderr of the hive is redirected
    -worker_delay_startup_seconds <number>  : number of seconds each worker has to wait before first talking to the database (0 by default, useful for debugging)
    -worker_crash_on_startup_prob <float>   : probability of each worker failing at startup (0 by default, useful for debugging)
    -debug <debug_level>                    : set debug level of the workers

=head2 Other commands/options

    -help                  : print this help
    -versions              : report both Hive code version and Hive database schema version
    -dead                  : detect all unaccounted dead workers and reset their jobs for resubmission
    -sync                  : re-synchronize the hive
    -unkwn                 : detect all workers in UNKWN state and reset their jobs for resubmission (careful, they *may* reincarnate!)
    -alldead               : tell the database all workers are dead (no checks are performed in this mode, so be very careful!)
    -balance_semaphores    : set all semaphore_counts to the numbers of unDONE fan jobs (emergency use only)
    -worker_stats          : show status of each running worker
    -failed_jobs           : show all failed jobs
    -job_output <job_id>   : print details for one job
    -reset_job_id <num>    : reset a job back to READY so it can be rerun
    -reset_failed_jobs     : reset FAILED jobs of -analyses_filter'ed ones back to READY so they can be rerun
    -reset_done_jobs       : reset DONE and PASSED_ON jobs of -analyses_filter'ed ones back to READY so they can be rerun
    -reset_all_jobs        : reset FAILED, DONE and PASSED_ON jobs of -analyses_filter'ed ones back to READY so they can be rerun
    -forgive_failed_jobs   : mark FAILED jobs of -analyses_filter'ed ones as DONE, and update their semaphores. NOTE: This does not make them dataflow
    -discard_ready_jobs    : mark READY jobs of -analyses_filter'ed ones as DONE, and update their semaphores. NOTE: This does not make them dataflow
    -unblock_semaphored_jobs : set SEMAPHORED jobs of -analyses_filter'ed ones to READY so they can start

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

