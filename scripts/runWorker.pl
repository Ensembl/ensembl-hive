#!/usr/local/ensembl/bin/perl -w

use strict;
use DBI;
use Getopt::Long;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Worker;
use Bio::EnsEMBL::Hive::Queen;


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
$self->{'job_id'}      = undef;


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
           'job_id=i'       => \$self->{'job_id'},
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

parse_conf($self, $conf_file);

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

my $queen = $DBA->get_Queen();

################################
# LSF submit system dependency
# no nice way to move this outside, so inside here.
# environment variables LSB_JOBID and LSB_JOBINDEX are set for process started 
# by LSF deamon.  Also know that the beekeeper is 'LSF'
#
my $lsb_jobid    = $ENV{'LSB_JOBID'};
my $lsb_jobindex = $ENV{'LSB_JOBINDEX'};
if(defined($lsb_jobid) and defined($lsb_jobindex)) {
  $self->{'beekeeper'}='LSF' unless($self->{'beekeeper'});
  if($lsb_jobindex>0) {
    $self->{'process_id'} = "$lsb_jobid\[$lsb_jobindex\]";
  } else {
    $self->{'process_id'} = "$lsb_jobid";
  }
}
################################
print("pid = ", $self->{'process_id'}, "\n") if($self->{'process_id'});

if($self->{'logic_name'}) {
  my $analysis = $queen->db->get_AnalysisAdaptor->fetch_by_logic_name($self->{'logic_name'});
  $self->{'analysis_id'} = $analysis->dbID if($analysis);
}

if($self->{'job_id'}) {
  printf("fetching job for id ", $self->{'job_id'}, "\n");
  $self->{'analysis_job'} = $queen->db->get_AnalysisJobAdaptor->fetch_by_dbID($self->{'job_id'});
  $self->{'analysis_id'} = $self->{'analysis_job'}->analysis_id if($self->{'analysis_job'}); 
  
  $queen->db->get_AnalysisJobAdaptor->reset_job_by_dbID($self->{'analysis_job'}->dbID);
}

my $worker = $queen->create_new_worker(
     -analysis_id    => $self->{'analysis_id'},
     -beekeeper      => $self->{'beekeeper'},
     -process_id     => $self->{'process_id'}
     );
unless($worker) {
  print("couldn't create worker\n");
  exit(0);
}

if(defined($self->{'outdir'})) { $worker->output_dir($self->{'outdir'}); }
else {
  my $arrRef = $DBA->get_MetaContainer->list_value_by_key( 'hive_output_dir' );
  if( @$arrRef ) {
    $worker->output_dir($arrRef->[0]);
  } 
}

if($self->{'batch_size'}) {
  $worker->batch_size($self->{'batch_size'});
}
if($self->{'job_limit'}) {
  $worker->job_limit($self->{'job_limit'});
  $worker->life_span(0);
}
if($self->{'lifespan'}) {
  $worker->life_span($self->{'lifespan'} * 60);
}

$worker->print_worker();

if($self->{'input_id'}) {
  $worker->output_dir('');
  my $job = new Bio::EnsEMBL::Hive::AnalysisJob;
  $job->input_id($self->{'input_id'});
  $job->analysis_id(0); #don't link into hive, ie prevents using dataflow rules
  eval { $worker->run($job); };
}
elsif($self->{'analysis_job'}) {
  my $job = $self->{'analysis_job'};
  print("running job_id=", $job->dbID," input_id:", $job->input_id,"\n");
  eval { $worker->run($job); };
}
else {
  eval { $worker->run(); };
}

if($@) {
  #worker threw an exception so it had a problem
  print("\n$@");
	$queen->register_worker_death($worker);
}

printf("dbc %d disconnect cycles\n", $DBA->dbc->disconnect_count);
print("total jobs completes : ", $worker->work_done, "\n");

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
  print "  -logic_name <string>   : logic_name of analysis to make this worker\n";
  print "  -batchsize <num>       : #jobs to claim at a time\n";
  print "  -limit <num>           : #jobs to run before worker can die naturally\n";
  print "  -lifespan <num>        : number of minutes this worker is allowed to run\n";
  print "  -outdir <path>         : directory where stdout/stderr is redirected\n";
  print "  -bk <string>           : beekeeper identifier\n";
  print "  -pid <string>          : externally set process_id descriptor (e.g. lsf job_id, array_id)\n";
  print "  -input_id <string>     : test input_id on specified analysis\n";
  print "  -job_id <id>           : run specific job defined by analysis_job_id\n";
  print "runWorker.pl v1.3\n";
  
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

