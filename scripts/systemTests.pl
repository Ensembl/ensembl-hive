#!/usr/local/ensembl/bin/perl -w

use strict;
use DBI;
use Getopt::Long;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Worker;
use Bio::EnsEMBL::Hive::Queen;
use Time::HiRes qw(time gettimeofday tv_interval);
use Data::UUID;

# ok this is a hack, but I'm going to pretend I've got an object here
# by creating a blessed hash ref and passing it around like an object
# this is to avoid using global variables in functions, and to consolidate
# the globals into a nice '$self' package
my $self = bless {};

$self->{'db_conf'} = {};
$self->{'db_conf'}->{'-user'} = 'ensro';
$self->{'db_conf'}->{'-port'} = 3306;

$self->{'analysis_id'} = undef;
$self->{'logic_name'}  = undef;
$self->{'outdir'}      = undef;
$self->{'beekeeper'}   = undef;
$self->{'process_id'}  = undef;


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
           'analysis_id=i'  => \$self->{'analysis_id'},
           'logic_name=s'   => \$self->{'logic_name'},
           'batchsize=i'    => \$self->{'batch_size'},
           'limit=i'        => \$self->{'job_limit'},
           'lifespan=i'     => \$self->{'lifespan'},
           'outdir=s'       => \$self->{'outdir'},
           'bk=s'           => \$self->{'beekeeper'},
           'pid=s'          => \$self->{'process_id'},
           'input_id=s'     => \$self->{'input_id'},
          );

$self->{'analysis_id'} = shift if(@_);

if ($help) { usage(); }

my $DBA;
if($url) {
  $DBA = Bio::EnsEMBL::Hive::URLFactory->fetch($url);
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
  $url = $DBA->url();
}
#$DBA->dbc->disconnect_when_inactive(1);

my $queen = $DBA->get_Queen();

test_job_creation($self);

exit(0);


#######################
#
# subroutines
#
#######################

sub usage {
  print "systemTests.pl [options]\n";
  print "  -help                  : print this help\n";
  print "  -url <url string>      : url defining where database is located\n";
  print "systemTests.pl v1.0\n";
  
  exit(1);  
}


sub test_job_creation {
  my $self = shift;

  print("creating analysis 'SubmitTestJobs'\n");
  my $analysis = Bio::EnsEMBL::Analysis->new (
      -db              => '',
      -db_file         => '',
      -db_version      => '1',
      -parameters      => "",
      -logic_name      => 'SubmitTestJobs',
      -module          => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
    );
  $DBA->get_AnalysisAdaptor()->store($analysis);

  my $stats = $analysis->stats;
  $stats->batch_size(7000);
  $stats->hive_capacity(11);
  $stats->status('BLOCKED');
  $stats->update();

  print("inserting jobs\n");
  my $starttime = time();
  my $count =0;
  my $ug    = new Data::UUID;
  my $uuid  = $ug->to_string( $ug->create() );
  while(++$count < 10000) {
    my $input_id = "test_job_$uuid\_$count";
    Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob (
          -input_id       => $input_id,
          -analysis       => $analysis,
          -input_job_id   => 0,
          );
    print("$input_id at ",(time()-$starttime)," secs\n") if($count % 500 == 0);          
  }

  my $total_time = (time()-$starttime);
  print "$count jobs created in $total_time secs\n";
  print("speed : ",($count / $total_time), " jobs/sec\n");
}

