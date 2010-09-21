#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long;

use Bio::EnsEMBL::Hive::Utils 'destringify';
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Worker;
use Bio::EnsEMBL::Hive::Queen;
use Bio::EnsEMBL::Hive::URLFactory;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor;

use Bio::EnsEMBL::Hive::Meadow::LSF;
use Bio::EnsEMBL::Hive::Meadow::LOCAL;

main();

sub main {

    $| = 1;
    Bio::EnsEMBL::Registry->no_version_check(1);

        # ok this is a hack, but I'm going to pretend I've got an object here
        # by creating a hash ref and passing it around like an object
        # this is to avoid using global variables in functions, and to consolidate
        # the globals into a nice '$self' package
    my $self = {};

    $self->{'db_conf'} = {
        -host   => '',
        -port   => 3306,
        -user   => 'ensro',
        -pass   => '',
        -dbname => '',
    };

    my ($help, $conf_file);
    my $loopit                      = 0;
    my $sync                        = 0;
    my $local                       = 0;
    my $show_failed_jobs            = 0;
    my $no_pend_adjust              = 0;
    my $worker_limit                = 50;
    my $local_cpus                  = 2;
    my $meadow_options              = '';
    my $max_loops                   = 0; # not running by default
    my $run                         = 0;
    my $check_for_dead              = 0;
    my $all_dead                    = 0;
    my $remove_analysis_id          = 0;
    my $job_id_for_output           = 0;
    my $show_worker_stats           = 0;
    my $kill_worker_id              = 0;
    my $reset_job_id                = 0;
    my $reset_all_jobs_for_analysis = 0;

    $self->{'sleep_minutes'}        = 1;
#    $self->{'overdue_minutes'}      = 60;   # which means one hour
    $self->{'verbose_stats'}        = 1;
    $self->{'reg_name'}             = 'hive';
    $self->{'maximise_concurrency'} = 0;
    $self->{'retry_throwing_jobs'}  = undef;
    $self->{'hive_output_dir'} = undef;

    GetOptions(
                    # connection parameters
               'conf=s'            => \$conf_file,
               'regfile=s'         => \$self->{'reg_file'},
               'regname=s'         => \$self->{'reg_name'},
               'url=s'             => \$self->{'url'},
               'host|dbhost=s'     => \$self->{'db_conf'}->{'-host'},
               'port|dbport=i'     => \$self->{'db_conf'}->{'-port'},
               'user|dbuser=s'     => \$self->{'db_conf'}->{'-user'},
               'password|dbpass=s' => \$self->{'db_conf'}->{'-pass'},
               'database|dbname=s' => \$self->{'db_conf'}->{'-dbname'},

                    # loop control
               'loop'              => \$loopit,
               'max_loops=i'       => \$max_loops,
               'run'               => \$run,
               'job_id|run_job_id=i'  => \$self->{'run_job_id'},
               'sleep=f'           => \$self->{'sleep_minutes'},

                    # meadow control
               'local!'            => \$local,
               'local_cpus=i'      => \$local_cpus,
               'wlimit=i'          => \$worker_limit,
               'no_pend'           => \$no_pend_adjust,
               'meadow_options|lsf_options=s'  => \$meadow_options, # 'lsf_options' is deprecated (please investigate the resource requirements, they may suit your needs way better)

                    # worker control
               'job_limit|jlimit=i'     => \$self->{'job_limit'},
               'batch_size=i'           => \$self->{'batch_size'},
               'life_span|lifespan=i'   => \$self->{'life_span'},
               'logic_name=s'      => \$self->{'logic_name'},
               'hive_output_dir=s' => \$self->{'hive_output_dir'},
               'maximise_concurrency=i' => \$self->{'maximise_concurrency'},
               'retry_throwing_jobs=i'  => \$self->{'retry_throwing_jobs'},

                    # other commands/options
               'h|help'            => \$help,
               'sync'              => \$sync,
               'dead'              => \$check_for_dead,
               'killworker=i'      => \$kill_worker_id,
#               'overdue'           => \$self->{'overdue_minutes'},
               'alldead'           => \$all_dead,
               'no_analysis_stats' => \$self->{'no_analysis_stats'},
               'verbose_stats=i'   => \$self->{'verbose_stats'},
               'worker_stats'      => \$show_worker_stats,
               'failed_jobs'       => \$show_failed_jobs,
               'reset_job_id=i'    => \$reset_job_id,
               'reset_all|reset_all_jobs_for_analysis=s' => \$reset_all_jobs_for_analysis,
               'delete|remove=s'   => \$remove_analysis_id, # careful
               'job_output=i'      => \$job_id_for_output,
               'monitor!'          => \$self->{'monitor'},

                    # loose arguments interpreted as database name (for compatibility with mysql[dump])
               '<>', sub { $self->{'db_conf'}->{'-dbname'} = shift @_; },
    );

    if ($help) { usage(0); }

    parse_conf($self, $conf_file);

    if($run or $self->{'run_job_id'}) {
        $max_loops = 1;
    } elsif ($loopit) {
        unless($max_loops) {
            $max_loops = -1; # unlimited
        }
        unless(defined($self->{'monitor'})) {
            $self->{'monitor'} = 1;
        }
    }

    if($self->{'reg_file'}) {
        Bio::EnsEMBL::Registry->load_all($self->{'reg_file'});
        $self->{'dba'} = Bio::EnsEMBL::Registry->get_DBAdaptor($self->{'reg_name'}, 'hive');
    } elsif($self->{'url'}) {
        $self->{'dba'} = Bio::EnsEMBL::Hive::URLFactory->fetch($self->{'url'}) || die("Unable to connect to $self->{'url'}\n");
    } elsif (    $self->{'db_conf'}->{'-host'}
             and $self->{'db_conf'}->{'-user'}
             and $self->{'db_conf'}->{'-dbname'}) { # connect to database specified
                    $self->{'dba'} = new Bio::EnsEMBL::Hive::DBSQL::DBAdaptor(%{$self->{'db_conf'}});
                    $self->{'url'} = $self->{'dba'}->dbc->url;
    } else {
        print "\nERROR : Connection parameters (regfile+regname, url or dbhost+dbuser+dbname) need to be specified\n\n";
        usage(1);
    }

    my $queen = $self->{'dba'}->get_Queen;
    $queen->{'maximise_concurrency'} = 1 if ($self->{'maximise_concurrency'});
    $queen->{'verbose_stats'} = $self->{'verbose_stats'};

    my $pipeline_name = destringify(
            $self->{'dba'}->get_MetaContainer->list_value_by_key("pipeline_name")->[0]
         || $self->{'dba'}->get_MetaContainer->list_value_by_key("name")->[0]
    );

    if($local) {
        $self->{'meadow'} = Bio::EnsEMBL::Hive::Meadow::LOCAL->new();
        $self->{'meadow'} -> total_running_workers_limit($local_cpus);
    } else {
        $self->{'meadow'} = Bio::EnsEMBL::Hive::Meadow::LSF->new();
        $self->{'meadow'} -> meadow_options($meadow_options);
    }
    $self->{'meadow'} -> pending_adjust(not $no_pend_adjust);

    if($self->{'run_job_id'}) {
        $worker_limit = 1;
    }
    $self->{'meadow'} -> submitted_workers_limit($worker_limit);
    $self->{'meadow'} -> pipeline_name($pipeline_name);

    if($reset_job_id) { $queen->reset_and_fetch_job_by_dbID($reset_job_id); }

    if($job_id_for_output) {
        printf("===== job output\n");
        my $job = $self->{'dba'}->get_AnalysisJobAdaptor->fetch_by_dbID($job_id_for_output);
        $job->print_job();
    }

    if($reset_all_jobs_for_analysis) {
        reset_all_jobs_for_analysis($self, $reset_all_jobs_for_analysis)
    }

    if($remove_analysis_id) { remove_analysis_id($self, $remove_analysis_id); }
    if($all_dead)           { $queen->register_all_workers_dead(); }
    if($check_for_dead)     { $queen->check_for_dead_workers($self->{'meadow'}, 1); }

    if ($kill_worker_id) {
        my $worker = $queen->fetch_by_worker_id($kill_worker_id);
        if( $self->{'meadow'}->responsible_for_worker($worker)
        and not defined($worker->cause_of_death())) {

            printf("KILL: %10d %35s %15s  %20s(%d) : ", 
                $worker->worker_id, $worker->host, $worker->process_id, 
                $worker->analysis->logic_name, $worker->analysis->dbID);

            $self->{'meadow'}->kill_worker($worker);
            $worker->cause_of_death('KILLED_BY_USER');
            $queen->register_worker_death($worker);
                # what about clean-up? Should we do it here or not?
        }
    }

    my $analysis = $self->{'dba'}->get_AnalysisAdaptor->fetch_by_logic_name($self->{'logic_name'});

    if ($max_loops) { # positive $max_loop means limited, negative means unlimited

        run_autonomously($self, $max_loops, $queen, $analysis);

    } else {
            # the output of several methods will look differently depending on $analysis being [un]defined

        if($sync) {
            $queen->synchronize_hive($analysis);
        }
        $queen->print_analysis_status($analysis) unless($self->{'no_analysis_stats'});
        $queen->print_running_worker_status;

        show_running_workers($self, $queen) if($show_worker_stats);
        #show_failed_workers($self, $queen);

        $queen->get_num_needed_workers($analysis); # apparently run not for the return value, but for the side-effects
        $queen->get_remaining_jobs_show_hive_progress();

        if($show_failed_jobs) {
            print("===== failed jobs\n");
            my $failed_job_list = $self->{'dba'}->get_AnalysisJobAdaptor->fetch_all_failed_jobs();

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

sub usage {
    my $retvalue = shift @_;

    if(`which perldoc`) {
        system('perldoc', $0);
    } else {
        foreach my $line (<DATA>) {
            if($line!~s/\=\w+\s?//) {
                $line = "\t$line";
            }
            print $line;
        }
    }
    exit($retvalue);
}

sub parse_conf {
    my ($self, $conf_file) = @_;

  if($conf_file and (-e $conf_file)) {
    #read configuration file from disk
    my @conf_list = @{do $conf_file};

    foreach my $confPtr (@conf_list) {
      #print("HANDLE type " . $confPtr->{TYPE} . "\n");
      if(($confPtr->{TYPE} eq 'COMPARA') or ($confPtr->{TYPE} eq 'DATABASE')) {
        $self->{'db_conf'} = $confPtr;
      }
    }
  }
}


# --------------[worker reports]--------------------

sub show_given_workers {
    my ($self, $worker_list, $verbose_stats) = @_;

    foreach my $worker (@{$worker_list}) {
        printf("%10d %35s(%5d) %5s:%15s %15s (%s)\n", 
            $worker->worker_id,
            $worker->analysis->logic_name,
            $worker->analysis->dbID,
            $worker->beekeeper,
            $worker->process_id, 
            $worker->host,
            $worker->last_check_in);
        printf("%s\n", $worker->worker_output_dir) if ($verbose_stats);
    }
}

sub show_running_workers {
    my ($self, $queen) = @_;

    print("===== running workers\n");
    show_given_workers($self, $queen->fetch_overdue_workers(0), $queen->{'verbose_stats'});
}

sub show_failed_workers {  # does not seem to be used
    my ($self, $queen) = @_;

    print("===== CRASHED workers\n");
    show_given_workers($self, $queen->fetch_failed_workers(), $queen->{'verbose_stats'});
}

sub generate_worker_cmd {
    my ($self) = @_;

    my $worker_cmd = 'runWorker.pl';   # -bk '. $self->{'meadow'}->type();
    if ($self->{'run_job_id'}) {
        $worker_cmd .= " -job_id ".$self->{'run_job_id'};
    } else {
        foreach my $worker_option ('batch_size', 'job_limit', 'life_span', 'logic_name', 'maximize_concurrency', 'retry_throwing_jobs', 'hive_output_dir') {
            if(defined(my $value = $self->{$worker_option})) {
                $worker_cmd .= " -${worker_option} $value";
            }
        }
    }

    if ($self->{'reg_file'}) {
        $worker_cmd .= ' -regfile '. $self->{'reg_file'} .' -regname '. $self->{'reg_name'};
    } else {
        $worker_cmd .= ' -url '. $self->{'url'};
    }

    return $worker_cmd;
}

sub run_autonomously {
    my ($self, $max_loops, $queen, $this_analysis) = @_;

    unless(`runWorker.pl`) {
        print("can't find runWorker.pl script.  Please make sure it's in your path\n");
        exit(1);
    }

    my $worker_cmd = generate_worker_cmd($self);

        # pre-hash the resource_class xparams for future use:
    my %rc_xparams = map { ($_->rc_id => $_->parameters) }
        @{ $self->{'dba'}->get_ResourceDescriptionAdaptor->fetch_all_by_meadowtype($self->{'meadow'}->type()) };

    my $iteration=0;
    my $num_of_remaining_jobs=0;
    my $failed_analyses=0;
    my $order = $self->{'maximise_concurrency'}*2-1;
    do {
        if($iteration++) {
            $queen->monitor();
            $self->{'dba'}->dbc->disconnect_if_idle;
            printf("sleep %.2f minutes. Next loop at %s\n", $self->{'sleep_minutes'}, scalar localtime(time+$self->{'sleep_minutes'}*60));
            sleep($self->{'sleep_minutes'}*60);  
        }

        print("\n======= beekeeper loop ** $iteration **==========\n");

        $queen->check_for_dead_workers($self->{'meadow'}, 0);

        $queen->print_analysis_status unless($self->{'no_analysis_stats'});
        $queen->print_running_worker_status;
        #show_failed_workers($self, $queen);

        my ($worker_count, $rc_hash) = $queen->get_needed_workers_resync_if_necessary($self->{'meadow'}, $this_analysis);

            # apply various technical and self-imposed limits:
        my $worker_quota = $self->{'meadow'}->limit_workers($worker_count);

        if($worker_quota) {
            foreach my $rc_id (sort {$order*($rc_hash->{$a}<=>$rc_hash->{$b})} keys %$rc_hash) {
                my $this_rc_worker_count = ($worker_quota < $rc_hash->{$rc_id})
                    ? $worker_quota
                    : $rc_hash->{$rc_id};

                print "Submitting $this_rc_worker_count workers (rc_id=$rc_id) to ".$self->{'meadow'}->type()."\n";

                $self->{'meadow'}->submit_workers($iteration, $worker_cmd, $this_rc_worker_count, $rc_id, $rc_xparams{$rc_id} || '');

                $worker_quota -= $this_rc_worker_count;
            }
        } else {
            print "Not submitting any workers this iteration\n";
        }

        $failed_analyses       = $queen->get_num_failed_analyses($this_analysis);
        $num_of_remaining_jobs = $queen->get_remaining_jobs_show_hive_progress();

    } while(!$failed_analyses and $num_of_remaining_jobs and $iteration!=$max_loops);

    print "The Beekeeper has stopped because ".(
          $failed_analyses ? "there were $failed_analyses failed analyses"
        : !$num_of_remaining_jobs ? "there is nothing left to do"
        : "the number of loops was limited by $max_loops and this limit expired"
    )."\n";

    printf("dbc %d disconnect cycles\n", $self->{'dba'}->dbc->disconnect_count);
}

sub reset_all_jobs_for_analysis {
    my ($self, $logic_name) = @_;
  
  my $analysis = $self->{'dba'}->get_AnalysisAdaptor->fetch_by_logic_name($logic_name)
      || die( "Cannot AnalysisAdaptor->fetch_by_logic_name($logic_name)"); 
  
  $self->{'dba'}->get_AnalysisJobAdaptor->reset_all_jobs_for_analysis_id($analysis->dbID); 
  $self->{'dba'}->get_Queen->synchronize_AnalysisStats($analysis->stats);
}

sub remove_analysis_id {
    my ($self, $analysis_id) = @_;

    require Bio::EnsEMBL::DBSQL::AnalysisAdaptor or die "$!";

    my $analysis = $self->{'dba'}->get_AnalysisAdaptor->fetch_by_dbID($analysis_id); 

    $self->{'dba'}->get_AnalysisJobAdaptor->remove_analysis_id($analysis->dbID); 
    $self->{'dba'}->get_AnalysisAdaptor->remove($analysis); 
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
    unexpectantly so that she can free the dead workers and reclaim unfinished jobs.

=head1 USAGE EXAMPLES

        # Usually run after the pipeline has been created to calculate the internal statistics necessary for eHive functioning
    beekeeper.pl --host=hostname --port=3306 --user=username --password=secret ehive_dbname -sync

        # An alternative way of doing the same thing
    beekeeper.pl -url mysql://username:secret@hostname:port/ehive_dbname -sync

        # Do not run any additional Workers, just check for the current status of the pipeline:
    beekeeper.pl -url mysql://username:secret@hostname:port/ehive_dbname

        # Run the pipeline in automatic mode (-loop), run all the workers locally (-local) and allow for 3 parallel workers (-local_cpus 3)
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -local -local_cpus 3 -loop

        # Run in automatic mode, but only restrict to running the 'fast_blast' analysis
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -logic_name fast_blast -loop

        # Restrict the normal execution to one iteration only - can be used for testing a newly set up pipeline
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -run

        # Reset all 'buggy_analysis' jobs to 'READY' state, so that they can be run again
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -reset_all_jobs_for_analysis buggy_analysis

        # Do a cleanup: find and bury dead workers, reclaim their jobs
    beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -dead

=head1 OPTIONS

=head2 Connection parameters

    -conf <path>           : config file describing db connection
    -regfile <path>        : path to a Registry configuration file
    -regname <string>      : species/alias name for the Hive DBAdaptor
    -url <url string>      : url defining where hive database is located
    -host <machine>        : mysql database host <machine>
    -port <port#>          : mysql port number
    -user <name>           : mysql connection user <name>
    -password <pass>       : mysql connection password <pass>
    [-database] <name>     : mysql database <name>

=head2 Looping control

    -loop                  : run autonomously, loops and sleeps
    -max_loops <num>       : perform max this # of loops in autonomous mode
    -run                   : run 1 iteration of automation loop
    -job_id <job_id>       : run 1 iteration for this job_id
    -sleep <num>           : when looping, sleep <num> minutes (default 2min)

=head2 Meadow control

    -local                    : run jobs on local CPU (fork)
    -local_cpus <num>         : max # workers to be running locally
    -wlimit <num>             : max # workers to create per loop
    -no_pend                  : don't adjust needed workers by pending workers
    -meadow_options <string>  : passes <string> to the Meadow submission command as <options> (formerly lsf_options)

=head2 Worker control

    -job_limit <num>            : #jobs to run before worker can die naturally
    -batch_size <num>           : #jobs a worker can claim at once
    -life_span <num>            : life_span limit for each worker
    -logic_name <string>        : restrict the pipeline stat/runs to this analysis logic_name
    -maximise_concurrency 1     : try to run more different analyses at the same time
    -retry_throwing_jobs 0|1    : if a job dies *knowingly*, should we retry it by default?
    -hive_output_dir <path>     : directory where stdout/stderr of the hive is redirected

=head2 Other commands/options

    -help                  : print this help
    -dead                  : clean dead jobs for resubmission
    -alldead               : all outstanding workers
    -no_analysis_stats     : don't show status of each analysis
    -worker_stats          : show status of each running worker
    -failed_jobs           : show all failed jobs
    -reset_job_id <num>    : reset a job back to READY so it can be rerun
    -reset_all_jobs_for_analysis <logic_name>
                           : reset jobs back to READY so they can be rerun

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

