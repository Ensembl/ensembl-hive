#!/usr/local/ensembl/bin/perl -w

use strict;
use DBI;
use Getopt::Long;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Worker;
use Bio::EnsEMBL::Hive::Queen;
use Bio::EnsEMBL::Hive::URLFactory;
use Sys::Hostname;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor;

# ok this is a hack, but I'm going to pretend I've got an object here
# by creating a blessed hash ref and passing it around like an object
# this is to avoid using global variables in functions, and to consolidate
# the globals into a nice '$self' package
my $self = bless {};

$self->{'db_conf'} = {};
$self->{'db_conf'}->{'-user'} = 'ensro';
$self->{'db_conf'}->{'-port'} = 3306;
$self->{'max_loops'} = 0; #unlimited

my $conf_file;
my ($help, $host, $user, $pass, $dbname, $port, $adaptor, $url);
my ($job_limit, $batch_size);
my $loopit=0;
my $worker_limit = 50;
my $sleep_time = 5;
my $sync=0;
$self->{'overdue_limit'} = 75; #minutes
$self->{'show_analysis_stats'} = undef;
$self->{'show_worker_stats'} = undef;

GetOptions('help'           => \$help,
           'url=s'          => \$url,
           'conf=s'         => \$conf_file,
           'dbhost=s'       => \$host,
           'dbport=i'       => \$port,
           'dbuser=s'       => \$user,
           'dbpass=s'       => \$pass,
           'dbname=s'       => \$dbname,
           'dead'           => \$self->{'check_for_dead'},
           'overdue'        => \$self->{'overdue_limit'},
           'alldead'        => \$self->{'all_dead'},
           'run'            => \$self->{'run'},
           'jlimit=i'       => \$job_limit,
           'wlimit=i'       => \$worker_limit,
           'batch_size=i'   => \$batch_size,
           'loop'           => \$loopit,
	   'sync'           => \$sync,
	   'analysis_stats' => \$self->{'show_analysis_stats'},
	   'worker_stats'   => \$self->{'show_worker_stats'},
	   'sleep=i'        => \$sleep_time,
	   'logic_name=s'   => \$self->{'logic_name'},
          );

if ($help) { usage(); }

parse_conf($self, $conf_file);

if($self->{'run'}) {
  $loopit = 1;
  $self->{'max_loops'} = 1;
}

my $DBA;

if($url) {
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
}

my $queen = $DBA->get_Queen;

if($self->{'all_dead'}) { register_all_workers_dead($self, $queen); }
if($self->{'check_for_dead'}) { check_for_dead_workers($self, $queen); }

my $analysis = $DBA->get_AnalysisAdaptor->fetch_by_logic_name($self->{'logic_name'});

if($loopit) { 
  run_autonomously($self, $queen);
} elsif($analysis) {
  my $stats = $analysis->stats;
  if($sync) {
    $queen->synchronize_AnalysisStats($stats);
    $queen->check_blocking_control_rules_for_AnalysisStats($stats);
  }
  $stats->print_stats;
  $queen->get_num_needed_workers();
} else { 
  $queen->synchronize_hive() if($sync);

  $queen->print_analysis_status if($self->{'show_analysis_stats'});

  $queen->print_running_worker_status;

  show_running_workers($self, $queen) if($self->{'show_worker_stats'});

  $queen->get_num_running_workers();

  $queen->get_num_needed_workers();

  $queen->get_hive_progress();
}

exit(0);


#######################
#
# subroutines
#
#######################

sub usage {
  print "lsf_beekeeper.pl [options]\n";
  print "  -help                  : print this help\n";
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
  print "  -alldead               : all outstanding workers\n";
  print "  -run                   : run 1 iteration of automation loop\n";
  print "  -loop                  : run autonomously, loops and sleeps\n";
  print "  -sleep <num>           : when looping, sleep <num> minutes (default 5)\n";
  print "  -wlimit <num>          : max # workers to create per loop\n";
  print "  -analysis_stats        : show status of each analysis\n";
  print "  -worker_stats          : show status of each running worker\n";
  print "lsf_beekeeper.pl v1.3\n";
  
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


sub check_for_dead_workers {
  my $self = shift;
  my $queen = shift;

  print("===== check for dead workers\n");
  my $overdueWorkers = $queen->fetch_overdue_workers($self->{'overdue_limit'}*60);
  print(scalar(@{$overdueWorkers}), " overdue workers\n");
  foreach my $worker (@{$overdueWorkers}) {
    if($worker->beekeeper eq 'LSF') {
      printf("%10d %35s %15s  %20s(%d) : ", $worker->hive_id,$worker->host,$worker->process_id, $worker->analysis->logic_name, $worker->analysis->dbID);
      my $cmd = "bjobs ". $worker->process_id . " 2>&1 | grep -v 'not found' | grep -v JOBID | grep -v EXIT";
      #print("  check worker with : $cmd\n");
      my $check = qx/$cmd/;

      unless($check) {
        print("worker is missing => it DIED!!\n");
        $queen->register_worker_death($worker);
      }
      else {
        print("ALIVE and running\n");
      }
    }
  }
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
  my $queen = shift;

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
  }
}


sub run_autonomously {
  my $self = shift;
  my $queen = shift;

  my ($cmd, $worker_cmd);
  my $loopCount=1; 
  while($loopit) {
    print("\n=======lsf_beekeeper loop ** $loopCount **==========\n");

    check_for_dead_workers($self, $queen);
    
    my $runCount = $queen->get_num_running_workers();
    my $load     = $queen->get_hive_current_load();
    my $count    = $queen->get_num_needed_workers();

    my $pend_count = $self->get_pending_count();
    $count = $count - $pend_count;

    if($load==0 and $count==0 and $runCount==0) {
      #nothing running and nothing todo => do hard resync
      print("*** nothing is happening => do a hard resync\n");
      $queen->synchronize_hive();
      $count = $queen->get_num_needed_workers();
    }  

    $queen->print_hive_status()  if($self->{'show_analysis_stats'});
    $queen->print_running_worker_status()  if($self->{'show_worker_stats'});

    $count = $worker_limit if($count>$worker_limit);    
    
    if($count>0) {
      print("need $count workers\n");
      $worker_cmd = "runWorker.pl -bk LOCAL -url $url";
      $worker_cmd .= " -limit $job_limit" if(defined $job_limit);
      $worker_cmd .= " -batch_size $batch_size" if(defined $batch_size);

      if($count>1) { $cmd = "$worker_cmd";}
      else { $cmd = "$worker_cmd";}
      print("$cmd\n");
      system($cmd);
    }

    last if($self->{'max_loops'}>0 and ($loopCount >= $self->{'max_loops'}));

    $DBA->dbc->disconnect_if_idle;
    
    #print("sleep $sleep_time minutes\n");
    #sleep($sleep_time*60);  
    $loopCount++;
  }
  printf("dbc %d disconnect cycles\n", $DBA->dbc->disconnect_count);
}


sub get_pending_count {
  return 0; # Not needed for local
  my $self = shift;

  my $cmd = "bjobs | grep -c PEND";
  my $pend_count = qx/$cmd/;
  chomp($pend_count);

  print("$pend_count workers queued but not running\n");

  return $pend_count;
}

