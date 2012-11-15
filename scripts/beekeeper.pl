#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;

use Bio::EnsEMBL::Hive::Utils ('script_usage', 'destringify');
use Bio::EnsEMBL::Hive::Utils::Config;
use Bio::EnsEMBL::Hive::URLFactory;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Queen;
use Bio::EnsEMBL::Hive::Valley;

main();

sub main {
    $| = 1;
    Bio::EnsEMBL::Registry->no_version_check(1);

        # ok this is a hack, but I'm going to pretend I've got an object here
        # by creating a hash ref and passing it around like an object
        # this is to avoid using global variables in functions, and to consolidate
        # the globals into a nice '$self' package
    my $self = {};

    my $help;
    my $loopit                      = 0;
    my $sync                        = 0;
    my $local                       = 0;
    my $show_failed_jobs            = 0;
    my $meadow_type                 = undef;
    my $pending_adjust              = undef;
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
    my $job_id_for_output           = 0;
    my $show_worker_stats           = 0;
    my $kill_worker_id              = 0;
    my $reset_job_id                = 0;
    my $reset_all_jobs_for_analysis = 0;
    my $reset_failed_jobs_for_analysis = 0;

    $self->{'reg_conf'}             = undef;
    $self->{'reg_alias'}            = undef;

    $self->{'sleep_minutes'}        = 1;
    $self->{'retry_throwing_jobs'}  = undef;
    $self->{'compile_module_once'}  = undef;
    $self->{'hive_log_dir'} = undef;

    GetOptions(
                    # connection parameters
               'reg_conf|regfile=s' => \$self->{'reg_conf'},
               'reg_alias|regname=s'=> \$self->{'reg_alias'},
               'url=s'              => \$self->{'url'},

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
               'meadow_type=s'                  => \$meadow_type,
               'total_running_workers_max=i'    => \$total_running_workers_max,
               'submit_workers_max=i'           => \$submit_workers_max,
               'pending_adjust=i'               => \$pending_adjust,
               'submission_options=s'           => \$submission_options,

                    # worker control
               'job_limit|jlimit=i'     => \$self->{'job_limit'},
               'life_span|lifespan=i'   => \$self->{'life_span'},
               'logic_name=s'           => \$self->{'logic_name'},
               'hive_log_dir|hive_output_dir=s'      => \$self->{'hive_log_dir'},
               'retry_throwing_jobs=i'  => \$self->{'retry_throwing_jobs'},
               'compile_module_once=i'  => \$self->{'compile_module_once'},
               'debug=i'                => \$self->{'debug'},

                    # other commands/options
               'h|help'            => \$help,
               'sync'              => \$sync,
               'dead'              => \$check_for_dead,
               'killworker=i'      => \$kill_worker_id,
               'alldead'           => \$all_dead,
               'no_analysis_stats' => \$self->{'no_analysis_stats'},
               'worker_stats'      => \$show_worker_stats,
               'failed_jobs'       => \$show_failed_jobs,
               'reset_job_id=i'    => \$reset_job_id,
               'reset_failed|reset_failed_jobs_for_analysis=s' => \$reset_failed_jobs_for_analysis,
               'reset_all|reset_all_jobs_for_analysis=s' => \$reset_all_jobs_for_analysis,
               'job_output=i'      => \$job_id_for_output,
               'monitor!'          => \$self->{'monitor'},
    );

    if ($help) { script_usage(0); }

    my $config = Bio::EnsEMBL::Hive::Utils::Config->new();      # will probably add a config_file option later

    if($run or $run_job_id) {
        $max_loops = 1;
    } elsif ($loopit or $keep_alive) {
        unless($max_loops) {
            $max_loops = -1; # unlimited
        }
        unless(defined($self->{'monitor'})) {
            $self->{'monitor'} = 1;
        }
    }

    if($self->{'reg_conf'} and $self->{'reg_alias'}) {
        Bio::EnsEMBL::Registry->load_all($self->{'reg_conf'});
        $self->{'dba'} = Bio::EnsEMBL::Registry->get_DBAdaptor($self->{'reg_alias'}, 'hive');
    } elsif($self->{'url'}) {
        $self->{'dba'} = Bio::EnsEMBL::Hive::URLFactory->fetch($self->{'url'}) || die("Unable to connect to $self->{'url'}\n");
    } else {
        print "\nERROR : Connection parameters (url or reg_conf+reg_alias) need to be specified\n\n";
        script_usage(1);
    }

    $self->{'safe_url'} = $self->{'dba'}->dbc->url('WORKER_PASSWORD');

    my $queen = $self->{'dba'}->get_Queen;

    my $pipeline_name = destringify(
            $self->{'dba'}->get_MetaContainer->list_value_by_key("pipeline_name")->[0]
         || $self->{'dba'}->get_MetaContainer->list_value_by_key("name")->[0]
    );

    unless($pipeline_name) {
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

    $meadow_type = 'LOCAL' if($local);
    my $valley = Bio::EnsEMBL::Hive::Valley->new( $config, $meadow_type, $pipeline_name );

    my $current_meadow = $valley->get_current_meadow();
    warn "Current ".$current_meadow->toString."\n\n";

    $current_meadow->config_set('TotalRunningWorkersMax', $total_running_workers_max) if(defined $total_running_workers_max);
    $current_meadow->config_set('PendingAdjust', $pending_adjust) if(defined $pending_adjust);
    $current_meadow->config_set('SubmitWorkersMax', $submit_workers_max) if(defined $submit_workers_max);
    $current_meadow->config_set('SubmissionOptions', $submission_options) if(defined $submission_options);

    if($reset_job_id) { $queen->reset_job_by_dbID_and_sync($reset_job_id); }

    if($job_id_for_output) {
        printf("===== job output\n");
        my $job = $self->{'dba'}->get_AnalysisJobAdaptor->fetch_by_dbID($job_id_for_output);
        $job->print_job();
    }

    if(my $reset_logic_name = $reset_all_jobs_for_analysis || $reset_failed_jobs_for_analysis) {

        my $reset_analysis = $self->{'dba'}->get_AnalysisAdaptor->fetch_by_logic_name($reset_logic_name)
              || die( "Cannot AnalysisAdaptor->fetch_by_logic_name($reset_logic_name)"); 

        $self->{'dba'}->get_AnalysisJobAdaptor->reset_jobs_for_analysis_id($reset_analysis->dbID, $reset_all_jobs_for_analysis); 
        $self->{'dba'}->get_Queen->synchronize_AnalysisStats($reset_analysis->stats);
    }

    if($all_dead)           { $queen->register_all_workers_dead(); }
    if($check_for_dead)     { $queen->check_for_dead_workers($valley, 1); }

    if ($kill_worker_id) {
        my $kill_worker = $queen->fetch_by_dbID($kill_worker_id);

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

    my $analysis = $self->{'dba'}->get_AnalysisAdaptor->fetch_by_logic_name($self->{'logic_name'});

    if ($max_loops) { # positive $max_loop means limited, negative means unlimited

        run_autonomously($self, $max_loops, $keep_alive, $queen, $valley, $analysis, $run_job_id, $force);

    } else {
            # the output of several methods will look differently depending on $analysis being [un]defined

        if($sync) {
            $queen->synchronize_hive($analysis);
        }
        $queen->print_analysis_status($analysis) unless($self->{'no_analysis_stats'});

        if($show_worker_stats) {
            print "\n===== List of live Workers according to the Queen: ======\n";
            foreach my $worker (@{ $queen->fetch_overdue_workers(0) }) {
                print $worker->toString()."\n";
            }
        }
        $queen->print_running_worker_counts;

        $queen->schedule_workers_resync_if_necessary($valley, $analysis);   # show what would be submitted, but do not actually submit
        $queen->get_remaining_jobs_show_hive_progress();

        if($show_failed_jobs) {
            print("===== failed jobs\n");
            my $failed_job_list = $self->{'dba'}->get_AnalysisJobAdaptor->fetch_all_by_analysis_id_status($analysis && $analysis->dbID, 'FAILED');

            foreach my $job (@{$failed_job_list}) {
                $job->print_job();
            }
        }
    }

    if ($self->{'monitor'}) {
        $queen->monitor();
    }

    exit(0);
}

#######################
#
# subroutines
#
#######################


sub generate_worker_cmd {
    my ($self, $run_analysis, $run_job_id, $force) = @_;

    my $worker_cmd = 'runWorker.pl';
    unless(`$worker_cmd`) {
        print("can't find $worker_cmd script.  Please make sure it's in your path\n");
        exit(1);
    }

    if ($self->{'reg_conf'}) {      # if reg_conf is defined, we have to pass it anyway, regardless of whether it is used to connect to the Hive database or not:
        $worker_cmd .= ' -reg_conf '. $self->{'reg_conf'};
    }

    if ($self->{'reg_alias'}) {     # then we pass the connection parameters:
        $worker_cmd .= ' -reg_alias '. $self->{'reg_alias'};
    } else {
        $worker_cmd .= " -url '". $self->{'safe_url'} ."'";
    }

    foreach my $worker_option ('job_limit', 'life_span', 'retry_throwing_jobs', 'compile_module_once', 'hive_log_dir', 'debug') {
        if(defined(my $value = $self->{$worker_option})) {
            $worker_cmd .= " -${worker_option} $value";
        }
    }

        # special task:
    if ($run_analysis) {
        $worker_cmd .= " -logic_name ".$run_analysis->logic_name;
    } elsif ($run_job_id) {
        $worker_cmd .= " -job_id $run_job_id";
    }

    if (defined($force)) {
        $worker_cmd .= " -force $force";
    }

    return $worker_cmd;
}

sub run_autonomously {
    my ($self, $max_loops, $keep_alive, $queen, $valley, $run_analysis, $run_job_id, $force) = @_;

    my $current_meadow  = $valley->get_current_meadow();
    my $worker_cmd      = generate_worker_cmd($self, $run_analysis, $run_job_id, $force);
    my $special_task    = $run_analysis || $run_job_id;

        # first, fetch two resource-related mappings from the database:
    my $rc_name2id = $self->{'dba'}->get_ResourceClassAdaptor->fetch_HASHED_FROM_name_TO_resource_class_id();
    my $rc_id2xparams = $self->{'dba'}->get_ResourceDescriptionAdaptor->fetch_by_meadow_type_HASHED_FROM_resource_class_id_TO_parameters($current_meadow->type());

        # now, chain these two mappings together:
        #   FIXME: in future this  mapping should be obtainable from the adaptor in one go.
    my %rc_name2xparams = map { $_ =>  $rc_id2xparams->{ $rc_name2id->{ $_ }} } keys %$rc_name2id;

    my $iteration=0;
    my $num_of_remaining_jobs=0;
    my $failed_analyses=0;
    do {
        if($iteration++) {
            $queen->monitor();
            $self->{'dba'}->dbc->disconnect_if_idle;
            printf("sleep %.2f minutes. Next loop at %s\n", $self->{'sleep_minutes'}, scalar localtime(time+$self->{'sleep_minutes'}*60));
            sleep($self->{'sleep_minutes'}*60);  
        }

        print("\n======= beekeeper loop ** $iteration **==========\n");

        $queen->check_for_dead_workers($valley, 0);

        $queen->print_analysis_status unless($self->{'no_analysis_stats'});
        $queen->print_running_worker_counts;

        my $workers_to_run_by_rc_name = $queen->schedule_workers_resync_if_necessary($valley, $run_analysis);

        if(keys %$workers_to_run_by_rc_name) {
            foreach my $rc_name ( sort { $workers_to_run_by_rc_name->{$a}<=>$workers_to_run_by_rc_name->{$b} } keys %$workers_to_run_by_rc_name) {
                my $this_rc_worker_count = $workers_to_run_by_rc_name->{$rc_name};

                print "Submitting $this_rc_worker_count workers (rc_name=$rc_name) to ".$current_meadow->toString()."\n";

                $current_meadow->submit_workers($worker_cmd.($special_task ? '' : " -rc_name $rc_name"), $this_rc_worker_count, $iteration, $rc_name, $rc_name2xparams{ $rc_name } || '');
            }
        } else {
            print "Not submitting any workers this iteration\n";
        }

        $failed_analyses       = $queen->get_num_failed_analyses($run_analysis);
        $num_of_remaining_jobs = $queen->get_remaining_jobs_show_hive_progress();

    } while( $keep_alive
            or (!$failed_analyses and $num_of_remaining_jobs and $iteration!=$max_loops) );

    print "The Beekeeper has stopped because ".(
          $failed_analyses ? "there were $failed_analyses failed analyses"
        : !$num_of_remaining_jobs ? "there is nothing left to do"
        : "the number of loops was limited by $max_loops and this limit expired"
    )."\n";

    printf("dbc %d disconnect cycles\n", $self->{'dba'}->dbc->disconnect_count);
}


__DATA__

=pod

=head1 NAME

    beekeeper.pl

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

        # Run in automatic mode, but only restrict to running the 'fast_blast' analysis
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -logic_name fast_blast -loop

        # Restrict the normal execution to one iteration only - can be used for testing a newly set up pipeline
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -run

        # Reset failed 'buggy_analysis' jobs to 'READY' state, so that they can be run again
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -reset_failed_jobs_for_analysis buggy_analysis

        # Do a cleanup: find and bury dead workers, reclaim their jobs
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -dead

=head1 OPTIONS

=head2 Connection parameters

    -reg_conf <path>       : path to a Registry configuration file
    -reg_alias <string>    : species/alias name for the Hive DBAdaptor
    -url <url string>      : url defining where hive database is located

=head2 Looping control

    -loop                  : run autonomously, loops and sleeps
    -max_loops <num>       : perform max this # of loops in autonomous mode
    -keep_alive            : do not stop when there are no more jobs to do - carry on looping
    -job_id <job_id>       : run 1 iteration for this job_id
    -run                   : run 1 iteration of automation loop
    -sleep <num>           : when looping, sleep <num> minutes (default 2min)

=head2 Current Meadow control

    -meadow_type <string>               : the desired Meadow class name, such as 'LSF' or 'LOCAL'
    -total_running_workers_max <num>    : max # workers to be running in parallel
    -submit_workers_max <num>           : max # workers to create per loop iteration
    -pending_adjust <0|1>               : [do not] adjust needed workers by pending workers
    -submission_options <string>        : passes <string> to the Meadow submission command as <options> (formerly lsf_options)

=head2 Worker control

    -job_limit <num>            : #jobs to run before worker can die naturally
    -life_span <num>            : life_span limit for each worker
    -logic_name <string>        : restrict the pipeline stat/runs to this analysis logic_name
    -retry_throwing_jobs 0|1    : if a job dies *knowingly*, should we retry it by default?
    -compile_module_once 0|1    : should we compile the module only once (desired future behaviour), or pretend to do it before every job (current behaviour)?
    -hive_log_dir <path>        : directory where stdout/stderr of the hive is redirected
    -debug <debug_level>        : set debug level of the workers

=head2 Other commands/options

    -help                  : print this help
    -dead                  : clean dead jobs for resubmission
    -alldead               : all outstanding workers
    -no_analysis_stats     : don't show status of each analysis
    -worker_stats          : show status of each running worker
    -failed_jobs           : show all failed jobs
    -reset_job_id <num>    : reset a job back to READY so it can be rerun
    -reset_failed_jobs_for_analysis <logic_name>
                           : reset FAILED jobs of an analysis back to READY so they can be rerun
    -reset_all_jobs_for_analysis <logic_name>
                           : reset ALL jobs of an analysis back to READY so they can be rerun

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

