#!/usr/local/ensembl/bin/perl -w

use strict;
use DBI;
use Getopt::Long;
use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Worker;
use Bio::EnsEMBL::Hive::Queen;
use Bio::EnsEMBL::Hive::URLFactory;

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
my ($help, $host, $user, $pass, $dbname, $port, $adaptor);

GetOptions('help'           => \$help,
           'conf=s'         => \$conf_file,
           'dbhost=s'       => \$host,
           'dbport=i'       => \$port,
           'dbuser=s'       => \$user,
           'dbpass=s'       => \$pass,
           'dbname=s'       => \$dbname,
          );

$self->{'analysis_id'} = shift if(@_);

if ($help) { usage(); }

parse_conf($self, $conf_file);

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
my $DBA = new Bio::EnsEMBL::Compara::DBSQL::DBAdaptor(%{$self->{'db_conf'}});

my $queen = $DBA->get_Queen();

my $overdueWorkers = $queen->fetch_overdue_workers(3600);  #overdue by 1hr
print(scalar(@{$overdueWorkers}), " overdue workers\n");
foreach my $worker (@{$overdueWorkers}) {
  printf("%10d %20s    analysis_id=%d\n", $worker->hive_id,$worker->host, $worker->analysis->dbID);
  $queen->register_worker_death($worker);
}

$queen->update_analysis_stats();

exit(0);


#######################
#
# subroutines
#
#######################

sub usage {
  print "runWorker.pl [options]\n";
  print "  -help                  : print this help\n";
  print "  -url <url string>      : url defining where database is located\n";
  print "  -conf <path>           : config file describing db connection\n";
  print "  -dbhost <machine>      : mysql database host <machine>\n";
  print "  -dbport <port#>        : mysql port number\n";
  print "  -dbname <name>         : mysql database <name>\n";
  print "  -dbuser <name>         : mysql connection user <name>\n";
  print "  -dbpass <pass>         : mysql connection password\n";
  print "  -analysis_id <id>      : analysis_id in db\n";
  print "  -limit <num>           : #jobs to run before worker can die naturally\n";
  print "  -outdir <path>         : directory where stdout/stderr is redirected\n";
  print "runWorker.pl v1.0\n";
  
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

