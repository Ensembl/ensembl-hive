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

$self->{'analysis_id'} = undef;
$self->{'outdir'}      = "/ecs4/work2/ensembl/jessica/data/hive-output";

my $conf_file;
my ($help, $host, $user, $pass, $dbname, $port, $adaptor, $url);

GetOptions('help'           => \$help,
           'url=s'          => \$url,
           'conf=s'         => \$conf_file,
           'dbhost=s'       => \$host,
           'dbport=i'       => \$port,
           'dbuser=s'       => \$user,
           'dbpass=s'       => \$pass,
           'dbname=s'       => \$dbname,
           'dead'           => \$self->{'all_dead'},
	   'run'            => \$self->{'run'},
          );

$self->{'analysis_id'} = shift if(@_);

if ($help) { usage(); }

parse_conf($self, $conf_file);

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


$queen->update_analysis_stats();
$queen->check_blocking_control_rules;

run_next_worker_clutch($self, $queen);

if($self->{'all_dead'}) { check_for_dead_workers($self, $queen); }


Bio::EnsEMBL::Hive::URLFactory->cleanup;
exit(0);


#######################
#
# subroutines
#
#######################

sub usage {
  print "local_beekeeper.pl [options]\n";
  print "  -help                  : print this help\n";
  print "  -url <url string>      : url defining where hive database is located\n";
  print "  -conf <path>           : config file describing db connection\n";
  print "  -dbhost <machine>      : mysql database host <machine>\n";
  print "  -dbport <port#>        : mysql port number\n";
  print "  -dbname <name>         : mysql database <name>\n";
  print "  -dbuser <name>         : mysql connection user <name>\n";
  print "  -dbpass <pass>         : mysql connection password\n";
  print "  -analysis_id <id>      : analysis_id in db\n";
  print "  -limit <num>           : #jobs to run before worker can die naturally\n";
  print "  -outdir <path>         : directory where stdout/stderr is redirected\n";
  print "local_beekeeper.pl v1.0\n";
  
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


sub run_next_worker_clutch
{
  my $self = shift;
  my $queen = shift;  

  $queen->update_analysis_stats();

  my $clutches = $queen->db->get_AnalysisStatsAdaptor->fetch_by_needed_workers();

  foreach my $analysis_stats (@{$clutches}) {
    $analysis_stats->print_stats;
  }

  foreach my $analysis_stats (@{$clutches}) {
    ##my($analysis_id, $count) = $queen->next_clutch();
    #if($count>0) {

    my $analysis_id = $analysis_stats->analysis_id;
    my $count = $analysis_stats->num_required_workers;

    my ($worker_cmd, $cmd);
    if($conf_file) { $worker_cmd = "./runWorker.pl -analysis_id $analysis_id -conf $conf_file";}
    if($url)       { $worker_cmd = "./runWorker.pl -analysis_id $analysis_id -url $url";}

    if($count>1) { $cmd = "bsub -JW$analysis_id\[1-$count\] $worker_cmd";}
    else { $cmd = "bsub -JW$analysis_id $worker_cmd";}
    print("$cmd\n");
    system($cmd) if($self->{'run'});

    # return of bsub looks like this
    #Job <6392054> is submitted to default queue <normal>.

  }
}


sub check_for_dead_workers {
  my $self = shift;
  my $queen = shift;

  my $host = hostname;

  my $overdueWorkers = $queen->fetch_overdue_workers(5*60);  #overdue by 5 minutes
  print(scalar(@{$overdueWorkers}), " overdue workers\n");
  foreach my $worker (@{$overdueWorkers}) {
    printf("%10d %20s    analysis_id=%d\n", $worker->hive_id,$worker->host, $worker->analysis->dbID);
    #if(($worker->beekeeper eq '') and ($worker->host eq $host)) {
      print("  is one of mine\n");
      my $cmd = "ps -p ". $worker->process_id;
      my $check = qx/$cmd/;

      $queen->register_worker_death($worker);
    #}
  }
}


