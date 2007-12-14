#!/usr/bin/env perl

use warnings;
use strict;
use DBI;
use Getopt::Long;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Worker;
use Bio::EnsEMBL::Hive::Queen;
use Bio::EnsEMBL::Hive::URLFactory;
use Sys::Hostname;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor;

Bio::EnsEMBL::Registry->no_version_check(1);

# ok this is a hack, but I'm going to pretend I've got an object here
# by creating a blessed hash ref and passing it around like an object
# this is to avoid using global variables in functions, and to consolidate
# the globals into a nice '$self' package
my $self = bless {};

$self->{'db_conf'} = {};
$self->{'db_conf'}->{'-user'} = 'ensro';
$self->{'db_conf'}->{'-port'} = 3306;
$self->{'max_loops'} = 0; #unlimited
$self->{'beekeeper_type'} = 'LSF';
$self->{'local_cpus'} = 2;

$| = 1;

my $conf_file;
my ($help, $host, $user, $pass, $dbname, $port, $adaptor, $url);
my ($job_limit, $batch_size);
my $loopit=0;
my $worker_limit = 50;
my $sleep_time = 2;
my $sync=0;
my $local=undef;
$self->{'overdue_limit'} = 60; #minutes
$self->{'no_analysis_stats'} = undef;
$self->{'show_worker_stats'} = undef;
$self->{'verbose_stats'} = 1;
$self->{'lsf_options'} = "";
$self->{'monitor'} = undef;
my $regfile  = undef;
my $reg_alias = 'hive';

GetOptions('help'           => \$help,
           'url=s'          => \$url,
           'conf=s'         => \$conf_file,
           'dbhost=s'       => \$host,
           'dbport=i'       => \$port,
           'dbuser=s'       => \$user,
           'dbpass=s'       => \$pass,
           'dbname=s'       => \$dbname,
           'local'          => \$local,
           'lsf'            => \$self->{'lsf_mode'},
           'dead'           => \$self->{'check_for_dead'},
           'killworker=i'   => \$self->{'kill_worker_id'},
           'overdue'        => \$self->{'overdue_limit'},
           'alldead'        => \$self->{'all_dead'},
           'run'            => \$self->{'run'},
           'run_job_id=i'   => \$self->{'run_job_id'},
           'jlimit=i'       => \$job_limit,
           'wlimit=i'       => \$worker_limit,
           'batch_size=i'   => \$batch_size,
           'loop'           => \$loopit,
           'no_pend'        => \$self->{'no_pend_adjust'},
           'sync'           => \$sync,
           'no_analysis_stats' => \$self->{'no_analysis_stats'},
           'verbose_stats=i'   => \$self->{'verbose_stats'},
           'worker_stats'   => \$self->{'show_worker_stats'},
           'sleep=f'        => \$sleep_time,
           'logic_name=s'   => \$self->{'logic_name'},
           'failed_jobs'    => \$self->{'show_failed_jobs'},
           'reset_job_id=i' => \$self->{'reset_job_id'},
           'reset_all|reset_all_jobs_for_analysis=s' => \$self->{'reset_all_jobs_for_analysis'},
           'delete|remove=s' => \$self->{'remove_analysis_id'}, # careful
           'lsf_options=s'  => \$self->{'lsf_options'},
           'job_output=i'   => \$self->{'show_job_output'},
           'regfile=s'      => \$regfile,
           'regname=s'      => \$reg_alias,
           'monitor!'       => \$self->{'monitor'},
          );

if ($help) { usage(); }

if($local) {
  $self->{'beekeeper_type'} ='LOCAL'; 
}

parse_conf($self, $conf_file);

if($self->{'run'} or $self->{'run_job_id'}) {
  $loopit = 1;
  $self->{'max_loops'} = 1;
} elsif ($loopit) {
  $self->{'monitor'} = 1 if (!defined($self->{'monitor'}));
}

my $DBA;
if($regfile) {
  Bio::EnsEMBL::Registry->load_all($regfile);
  $DBA = Bio::EnsEMBL::Registry->get_DBAdaptor($reg_alias, 'hive');
} 
elsif($url) {
  $DBA = Bio::EnsEMBL::Hive::URLFactory->fetch($url);
  die("Unable to connect to $url\n") unless($DBA);
} else {
  if($host)   { $self->{'db_conf'}->{'-host'}   = $host; }
  if($port)   { $self->{'db_conf'}->{'-port'}   = $port; }
  if($dbname) { $self->{'db_conf'}->{'-dbname'} = $dbname; }
  if($user)   { $self->{'db_conf'}->{'-user'}   = $user; }
  if($pass)   { $self->{'db_conf'}->{'-pass'}   = $pass; }


  unless(defined($self->{'db_conf'}->{'-host'})
         and defined($self->{'db_conf'}->{'-user'})
         and defined($self->{'db_conf'}->{'-dbname'}))
  {
    print "\nERROR : must specify host, user, and database to connect\n\n";
    usage();
  }

  # connect to database specified
  $DBA = new Bio::EnsEMBL::Hive::DBSQL::DBAdaptor(%{$self->{'db_conf'}});
  $url = $DBA->dbc->url;
}
$self->{'dba'} = $DBA;
my $queen = $DBA->get_Queen;
$self->{name} = $DBA->get_MetaContainer->list_value_by_key("name")->[0];

if($self->{'reset_job_id'}) { $queen->reset_and_fetch_job_by_dbID($self->{'reset_job_id'}); };
if($self->{'show_job_output'}) { print_job_output($self); }

if($self->{'reset_all_jobs_for_analysis'}) {
  reset_all_jobs_for_analysis($self, $self->{'reset_all_jobs_for_analysis'})
}

if($self->{'remove_analysis_id'}) { remove_analysis_id($self); }

if($self->{'all_dead'}) { register_all_workers_dead($self, $queen); }
if($self->{'check_for_dead'}) { check_for_dead_workers($self, $queen); }

my $analysis = $DBA->get_AnalysisAdaptor->fetch_by_logic_name($self->{'logic_name'});

if ($loopit) {

  run_autonomously($self, $queen, $analysis);

} elsif ($analysis) {

  my $stats = $analysis->stats;
  if($sync) {
    $queen->synchronize_AnalysisStats($stats);
    $queen->check_blocking_control_rules_for_AnalysisStats($stats);
  }
  $stats->print_stats($self->{'verbose_stats'});
  $queen->print_running_worker_status;
  $queen->get_num_needed_workers($analysis);
  $queen->get_hive_progress();

} elsif ($self->{'kill_worker_id'}) {

  kill_worker($self, $queen);

} else { 

  $queen->synchronize_hive() if($sync);
  $queen->print_analysis_status unless($self->{'no_analysis_stats'});

  $queen->print_running_worker_status;

  show_running_workers($self) if($self->{'show_worker_stats'});

  #show_failed_workers($self);

  $queen->get_num_needed_workers();

  $queen->get_hive_progress();
  
  show_failed_jobs($self) if($self->{'show_failed_jobs'});

}

if ($self->{'monitor'}) {
  $queen->monitor();
}

exit(0);


#######################
#
# subroutines
#
#######################

sub usage {
  print "beekeeper.pl [options]\n";
  print "  -help                  : print this help\n";
  print "  -regfile <path>        : path to a Registry configuration file\n";
  print "  -regname <string>      : species/alias name for the Hive DBAdaptor\n";
  print "  -url <url string>      : url defining where hive database is located\n";
  print "  -conf <path>           : config file describing db connection\n";
  print "  -dbhost <machine>      : mysql database host <machine>\n";
  print "  -dbport <port#>        : mysql port number\n";
  print "  -dbname <name>         : mysql database <name>\n";
  print "  -dbuser <name>         : mysql connection user <name>\n";
  print "  -dbpass <pass>         : mysql connection password\n";
  print "  -batch_size <num>      : #jobs a worker can claim at once\n";
  print "  -jlimit <num>          : #jobs to run before worker can die naturally\n";
  print "  -dead                  : clean overdue jobs for resubmission\n";
  print "  -overdue <min>         : worker overdue minutes checking if dead\n";
  print "  -alldead               : all outstanding workers\n";
  print "  -run                   : run 1 iteration of automation loop\n";
  print "  -run_job_id <job_id>   : run 1 iteration for this job_id\n";
  print "  -loop                  : run autonomously, loops and sleeps\n";
  print "  -local                 : run jobs on local CPU (fork)\n";
  print "  -lsf                   : run jobs on LSF compute resource (bsub)\n";
  print "  -lsf_options <string>  : passes <string> to LSF bsub command as <options>\n";
  print "  -no_pend               : don't adjust needed workers by pending workers\n";
  print "  -sleep <num>           : when looping, sleep <num> minutes (default 3min)\n";
  print "  -logic_name <string>   : restrict the pipeline stat/runs to this analysis logic_name\n";
  print "  -wlimit <num>          : max # workers to create per loop\n";
  print "  -no_analysis_stats     : don't show status of each analysis\n";
  print "  -worker_stats          : show status of each running worker\n";
  print "  -failed_jobs           : show all failed jobs\n";
  print "  -reset_job_id <num>    : reset a job back to READY so it can be rerun\n";
  print "  -reset_all_jobs_for_analysis <logic_name>\n";
  print "                         : reset jobs back to READY so it can be rerun\n";  
  print "beekeeper.pl v1.9\n";
  
  exit(1);  
}


sub parse_conf {
  my $self      = shift;
  my $conf_file = shift;

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


sub kill_worker {
  my $self = shift;
  my $queen = shift;

  my $worker = $queen->_fetch_by_hive_id($self->{'kill_worker_id'});
  return unless($worker->beekeeper eq $self->{'beekeeper_type'});
  return if(defined($worker->cause_of_death));

  printf("KILL: %10d %35s %15s  %20s(%d) : ", 
	   $worker->hive_id, $worker->host, $worker->process_id, 
	   $worker->analysis->logic_name, $worker->analysis->dbID);

  if(($self->{'beekeeper_type'} eq 'LSF') and ($self->lsf_check_worker($worker))) {
    my $cmd = 'bkill ' . $worker->process_id;
    system($cmd);
  }

  if(($self->{'beekeeper_type'} eq 'LOCAL') and 
     ($worker->host eq hostname) and
     ($self->local_check_worker($worker))) 
  {
    my $cmd = 'kill -9 ' . $worker->process_id;
    system($cmd);
  }

  $queen->register_worker_death($worker);
}


sub check_for_dead_workers {
  my $self = shift;
  my $queen = shift;

  print("===== check for dead workers\n");
  my $overdueWorkers = $queen->fetch_overdue_workers($self->{'overdue_limit'}*60);
  print(scalar(@{$overdueWorkers}), " overdue workers\n");
  foreach my $worker (@{$overdueWorkers}) {
    next unless($worker->beekeeper eq $self->{'beekeeper_type'});
    next if(($self->{'beekeeper_type'} eq 'LOCAL') and
	    ($worker->host ne hostname));

    printf("%10d %35s %15s  %20s(%d) : ", 
	   $worker->hive_id, $worker->host, $worker->process_id, 
	   $worker->analysis->logic_name, $worker->analysis->dbID);

    my $is_alive;
    $is_alive = $self->lsf_check_worker($worker) if($self->{'beekeeper_type'} eq 'LSF');
    $is_alive = $self->local_check_worker($worker) if($self->{'beekeeper_type'} eq 'LOCAL');

    if($is_alive) {
      print("ALIVE and running\n");
    } else {
      print("worker is missing => it DIED!!\n");
      $queen->register_worker_death($worker);
    }

  }
}


sub lsf_check_worker {
  my $self = shift;
  my $worker = shift;

  my $cmd = "bjobs ". $worker->process_id . " 2>&1 | grep -v 'not found' | grep -v JOBID | grep -v EXIT";
  #print("  check worker with : $cmd\n");
  my $is_alive = qx/$cmd/;

  return $is_alive;
}


sub local_check_worker {
  my $self = shift;
  my $worker = shift;

  my $cmd = "ps ". $worker->process_id . " 2>&1 | grep " . $worker->process_id;
  my $is_alive = qx/$cmd/;
  return $is_alive;
}


sub register_all_workers_dead {
  my $self = shift;
  my $queen = shift;

  my $overdueWorkers = $queen->fetch_overdue_workers(0);
  foreach my $worker (@{$overdueWorkers}) {
    $queen->register_worker_death($worker);
  }
}


sub show_overdue_workers {
  my $self = shift;
  my $queen = shift;

  print("===== overdue workers\n");
  my $overdueWorkers = $queen->fetch_overdue_workers($self->{'overdue_limit'}*60);
  foreach my $worker (@{$overdueWorkers}) {
    printf("%10d %35s %15s  %20s(%d)\n", $worker->hive_id,$worker->host,$worker->process_id, $worker->analysis->logic_name, $worker->analysis->dbID);
  }
}

sub show_running_workers {
  my $self = shift;
  my $queen = $self->{'dba'}->get_Queen;

  print("===== running workers\n");
  my $worker_list = $queen->fetch_overdue_workers(0);
  foreach my $worker (@{$worker_list}) {
    printf("%10d %35s(%5d) %5s:%15s %15s (%s)\n", 
       $worker->hive_id,
       $worker->analysis->logic_name,
       $worker->analysis->dbID,
       $worker->beekeeper,
       $worker->process_id, 
       $worker->host,
       $worker->last_check_in);
    printf("%s\n", $worker->output_dir) if ($self->{'verbose_stats'});
  }
}


sub show_failed_jobs {
  my $self = shift;

  print("===== failed jobs\n");
  my $failed_job_list = $self->{'dba'}->get_AnalysisJobAdaptor->fetch_all_failed_jobs;

  foreach my $job (@{$failed_job_list}) {
    my $analysis = $self->{'dba'}->get_AnalysisAdaptor->fetch_by_dbID($job->analysis_id);
    printf("job_id=%d %35s(%5d) input_id='%s'\n", 
       $job->dbID,
       $analysis->logic_name,
       $analysis->dbID,
       $job->input_id);
  }
}


sub print_job_output {
  my $self = shift;

  printf("===== job output\n");
  my $job = $self->{'dba'}->get_AnalysisJobAdaptor->fetch_by_dbID($self->{'show_job_output'});

  my $analysis = $self->{'dba'}->get_AnalysisAdaptor->fetch_by_dbID($job->analysis_id);
  printf("job_id=%d %35s(%5d) input_id='%s'\n", 
     $job->dbID,
     $analysis->logic_name,
     $analysis->dbID,
     $job->input_id);
}


sub show_failed_workers {
  my $self = shift;
  my $queen = $self->{'dba'}->get_Queen;

  print("===== CRASHED workers\n");
  my $worker_list = $queen->fetch_failed_workers;
  foreach my $worker (@{$worker_list}) {
    printf("%10d %35s(%5d) %5s:%15s %15s (%s)\n", 
       $worker->hive_id,
       $worker->analysis->logic_name,
       $worker->analysis->dbID,
       $worker->beekeeper,
       $worker->process_id, 
       $worker->host,
       $worker->last_check_in);
  }
}

sub run_autonomously {
  my $self = shift;
  my $queen = shift;
  my $analysis = shift;

  unless(`runWorker.pl`) {
    print("can't find runWorker.pl script.  Please make sure it's in your path\n");
    exit(1);
  }

  my ($cmd, $worker_cmd);
  my $loopCount=1;
  while($loopit) {
    print("\n=======lsf_beekeeper loop ** $loopCount **==========\n");

    check_for_dead_workers($self, $queen);

    $queen->{'verbose_stats'} = $self->{'verbose_stats'};
    $queen->print_analysis_status unless($self->{'no_analysis_stats'});

    $queen->print_running_worker_status;
    #show_failed_workers($self);
    
    my $runCount = $queen->get_num_running_workers();
    my $load     = $queen->get_hive_current_load();
    my $count    = $queen->get_num_needed_workers($analysis);
    my $lsf_pending_count = 0;

    if($self->{'beekeeper_type'} eq 'LSF') {
      $lsf_pending_count = $self->get_lsf_pending_count($self->{name});
      $count = $count - $lsf_pending_count;
    }

    if($load==0 and $count==0 and $runCount==0 and $lsf_pending_count==0) {
      #nothing running and nothing todo => do hard resync
      print("*** nothing is happening => do a hard resync\n");
      if($analysis) {
        my $stats = $analysis->stats;
        $queen->synchronize_AnalysisStats($stats);
        $queen->check_blocking_control_rules_for_AnalysisStats($stats);
      } else {
        $queen->synchronize_hive();
      }
      $count = $queen->get_num_needed_workers($analysis);
      my $num_failed_analyses = $queen->get_num_failed_analyses($analysis);
      if ($count==0 && $analysis) {
        if (!$num_failed_analyses) {
          printf("Nothing left to do for analysis ".$analysis->logic_name.". DONE!!\n\n");
        }
        $loopit=0;
      } elsif ($count == 0) {
        if (!$num_failed_analyses) {
          print "Nothing left to do. DONE!!\n\n";
        }
        $loopit=0;
      }
    }

    $count = $worker_limit if($count>$worker_limit);    
    my $logic_name = $self->{'logic_name'};
    
    if ($count>0 or $self->{'run_job_id'}) {
      print("need $count workers\n");
      $worker_cmd = "runWorker.pl -bk ". $self->{'beekeeper_type'};
      if ($self->{'run_job_id'}) {
        $worker_cmd .= " -job_id ".$self->{'run_job_id'};
        $count = 1; # Avoid to run more than 1 worker! 
      } else {
        $worker_cmd .= " -limit $job_limit" if(defined $job_limit);
        $worker_cmd .= " -batch_size $batch_size" if(defined $batch_size);
        $worker_cmd .= " -logic_name $logic_name" if(defined $logic_name);
      }

      if ($regfile) {
        $worker_cmd .= " -regfile $regfile -regname $reg_alias";
      } else {
        $worker_cmd .= " -url $url";
      }
      
      $cmd = undef;
      if ($self->{'beekeeper_type'} eq 'LSF') {
        my $lsf_job_name = "";
        if ($self->{name}) {
          $lsf_job_name = $self->{name}. "-";
        }
        if ($count>1) {
          $lsf_job_name .= "HL$loopCount\[1-$count\]";
        } else {
          $lsf_job_name .= "HL$loopCount";
        }
        $cmd = "bsub -o /dev/null -J\"$lsf_job_name\"";
        $cmd .= " " . $self->{'lsf_options'} if ($self->{'lsf_options'});
        $cmd .= " ".$worker_cmd;

      } elsif (($self->{'beekeeper_type'} eq 'LOCAL')
          and ($self->get_local_running_count() < $self->{'local_cpus'})) {
        $cmd = "$worker_cmd &";
      }

      if($cmd) {
        print("$cmd\n");
        system($cmd);
      }
    }

    $queen->get_hive_progress();

    last if($self->{'max_loops'}>0 and ($loopCount >= $self->{'max_loops'}));
  
    $DBA->dbc->disconnect_if_idle;
    
    if($loopit) {
      $queen->monitor();
      printf("sleep %1.2f minutes. Next loop at %s\n", $sleep_time, scalar localtime(time+$sleep_time*60));
      sleep($sleep_time*60);  
      $loopCount++;
    }
  }
  printf("dbc %d disconnect cycles\n", $DBA->dbc->disconnect_count);
}


sub get_lsf_pending_count {
  my ($self, $name) = @_;

  return 0 if($self->{'no_pend_adjust'});

  my $cmd;
  if ($name) {
    $cmd = "bjobs -w | grep '$name-HL' | grep -c PEND";
  } else {
    $cmd = "bjobs -w | grep -c PEND";
  }
  my $pend_count = qx/$cmd/;
  chomp($pend_count);

  print("$pend_count workers queued on LSF but not running\n");

  return $pend_count;
}


sub get_local_running_count {
  my $self = shift;

  my $cmd = "ps -a | grep runWorker | grep -v grep | wc -l";
  my $run_count = qx/$cmd/;
  chomp($run_count);
  print("$run_count workers running locally\n");
  return $run_count;
}


sub reset_all_jobs_for_analysis {
  my ($self, $logic_name) = @_;
  
  my $analysis = $self->{'dba'}->get_AnalysisAdaptor->
                   fetch_by_logic_name($logic_name); 
  
  $self->{'dba'}->get_AnalysisJobAdaptor->reset_all_jobs_for_analysis_id($analysis->dbID); 

  $self->{'dba'}->get_Queen->synchronize_AnalysisStats($analysis->stats);
}

sub remove_analysis_id {
  my $self = shift;
  
  require Bio::EnsEMBL::DBSQL::AnalysisAdaptor or die "$!";

  my $analysis = $self->{'dba'}->get_AnalysisAdaptor->
                   fetch_by_dbID($self->{'remove_analysis_id'}); 
  
  $self->{'dba'}->get_AnalysisJobAdaptor->remove_analysis_id($analysis->dbID); 
  $self->{'dba'}->get_AnalysisAdaptor->remove($analysis); 
}
