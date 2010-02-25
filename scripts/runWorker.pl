#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Worker;
use Bio::EnsEMBL::Hive::Queen;
use Bio::EnsEMBL::Registry;

use Bio::EnsEMBL::Hive::Meadow::LSF;
use Bio::EnsEMBL::Hive::Meadow::LOCAL;

Bio::EnsEMBL::Registry->no_version_check(1);

# ok this is a hack, but I'm going to pretend I've got an object here
# by creating a blessed hash ref and passing it around like an object
# this is to avoid using global variables in functions, and to consolidate
# the globals into a nice '$self' package
my $self = bless {};

$self->{'db_conf'} = {};
$self->{'db_conf'}->{'-user'} = 'ensro';
$self->{'db_conf'}->{'-port'} = 3306;

$self->{'job_id'}      = undef;     # most  specific specialization
$self->{'analysis_id'} = undef;     # less  specific specialization
$self->{'logic_name'}  = undef;     # (---------,,---------------)
$self->{'rc_id'}       = undef;     # least specific specialization

$self->{'outdir'}      = undef;
$self->{'beekeeper'}   = undef;
$self->{'process_id'}  = undef;
$self->{'debug'}       = undef;
$self->{'no_write'}     = undef;
$self->{'maximise_concurrency'} = undef;

my $conf_file;
my ($help, $host, $user, $pass, $dbname, $port, $adaptor, $url);
my $reg_conf  = undef;
my $reg_alias = 'hive';

GetOptions(

# Connection parameters:
           'conf=s'         => \$conf_file,
           'regfile=s'      => \$reg_conf,
           'regname=s'      => \$reg_alias,
           'url=s'          => \$url,
           'host|dbhost=s'  => \$host,
           'port|dbport=i'  => \$port,
           'user|dbuser=s'  => \$user,
           'password|dbpass=s'  => \$pass,
           'database|dbname=s'  => \$dbname,

# Job/Analysis control parameters:
           'job_id=i'       => \$self->{'job_id'},
           'analysis_id=i'  => \$self->{'analysis_id'},
           'rc_id=i'        => \$self->{'rc_id'},
           'logic_name=s'   => \$self->{'logic_name'},
           'batch_size=i'   => \$self->{'batch_size'},
           'limit=i'        => \$self->{'job_limit'},
           'lifespan=i'     => \$self->{'lifespan'},
           'outdir=s'       => \$self->{'outdir'},
           'bk=s'           => \$self->{'beekeeper'}, # deprecated and ignored
           'pid=s'          => \$self->{'process_id'},
           'input_id=s'     => \$self->{'input_id'},
           'no_cleanup'     => \$self->{'no_global_cleanup'},
           'analysis_stats' => \$self->{'show_analysis_stats'},
           'no_write'       => \$self->{'no_write'},
           'nowrite'        => \$self->{'no_write'},
           'maximise_concurrency' => \$self->{'maximise_concurrency'},

# Other commands
           'h|help'         => \$help,
           'debug=i'        => \$self->{'debug'},
          );

$self->{'analysis_id'} = shift if(@_);

if ($help) { usage(0); }

parse_conf($self, $conf_file);

my $DBA;
if($reg_conf) {
  Bio::EnsEMBL::Registry->load_all($reg_conf);
  $DBA = Bio::EnsEMBL::Registry->get_DBAdaptor($reg_alias, 'hive');
} 
elsif($url) {
  $DBA = Bio::EnsEMBL::Hive::URLFactory->fetch($url);
} 
else {
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
    usage(1);
  }

  # connect to database specified
  $DBA = new Bio::EnsEMBL::Hive::DBSQL::DBAdaptor(%{$self->{'db_conf'}});
}

unless($DBA and $DBA->isa("Bio::EnsEMBL::Hive::DBSQL::DBAdaptor")) {
  print("ERROR : no database connection\n\n");
  usage(1);
}

my $queen = $DBA->get_Queen();
$queen->{maximise_concurrency} = 1 if ($self->{maximise_concurrency});

unless($self->{'process_id'}) {     # do we really need this confusing feature - to be able to set the process_id externally?
    eval {
        $self->{'process_id'} = Bio::EnsEMBL::Hive::Meadow::LSF->get_current_worker_process_id();
    };
    if($@) {
        $self->{'process_id'} = Bio::EnsEMBL::Hive::Meadow::LOCAL->get_current_worker_process_id();
        $self->{'beekeeper'}  = 'LOCAL';
    } else {
        $self->{'beekeeper'}  = 'LSF';
    }
}

print("pid = ", $self->{'process_id'}, "\n") if($self->{'process_id'});

if($self->{'logic_name'}) {
  my $analysis = $queen->db->get_AnalysisAdaptor->fetch_by_logic_name($self->{'logic_name'});
  unless($analysis) {
    printf("logic_name: '%s' does not exist in database\n\n", $self->{'logic_name'});
    usage(1);
  }
  $self->{'analysis_id'} = $analysis->dbID;
}

$self->{'analysis_job'} = undef;

if($self->{'analysis_id'} and $self->{'input_id'}) {
  $self->{'analysis_job'} = new Bio::EnsEMBL::Hive::AnalysisJob;
  $self->{'analysis_job'}->input_id($self->{'input_id'});
  $self->{'analysis_job'}->analysis_id($self->{'analysis_id'}); 
  $self->{'analysis_job'}->dbID(-1); 
  print("creating job outside database\n");
  $self->{'analysis_job'}->print_job;
  $self->{'debug'}=1 unless(defined($self->{'debug'}));
  $self->{'outdir'}='' unless(defined($self->{'outdir'}));
}

if($self->{'job_id'}) {
  printf("fetching job for id %i\n", $self->{'job_id'});
  $self->{'analysis_job'} = $queen->reset_and_fetch_job_by_dbID($self->{'job_id'});
  $self->{'analysis_id'} = $self->{'analysis_job'}->analysis_id if($self->{'analysis_job'}); 
}

my $worker = $queen->create_new_worker(
     -rc_id          => $self->{'rc_id'},
     -analysis_id    => $self->{'analysis_id'},
     -beekeeper      => $self->{'beekeeper'},
     -process_id     => $self->{'process_id'},
     -job            => $self->{'analysis_job'},
     -no_write       => $self->{'no_write'},
     );
unless($worker) {
  $queen->print_analysis_status if($self->{'show_analysis_stats'});
  print("\n=== COULDN'T CREATE WORKER ===\n");
  exit(1);
}

$worker->debug($self->{'debug'}) if($self->{'debug'});

if(defined($self->{'outdir'})) { $worker->output_dir($self->{'outdir'}); }
else {
  my $arrRef = $DBA->get_MetaContainer->list_value_by_key( 'hive_output_dir' );
  if( @$arrRef ) {
    $worker->output_dir($arrRef->[0]);
  } 
}

if($self->{'batch_size'}) {
  $worker->set_worker_batch_size($self->{'batch_size'});
}
if($self->{'job_limit'}) {
  $worker->job_limit($self->{'job_limit'});
  $worker->life_span(0);
}
if($self->{'lifespan'}) {
  $worker->life_span($self->{'lifespan'} * 60);
}
if($self->{'no_global_cleanup'}) { 
  $worker->perform_global_cleanup(0); 
}

$worker->print_worker();

my $return_value = 0;
eval { $worker->run(); };

if($@) {
        # try to capture it ASAP:
    $return_value = ($! || $?>>8 || 1);

        #worker threw an exception so it had a problem:
    if($worker->perform_global_cleanup) {
            #have runnable cleanup any global/process files/data it may have created
        $worker->cleanup_worker_process_temp_directory;
    }
    print("\n$@");
    $queen->register_worker_death($worker);
}

if($self->{'show_analysis_stats'}) {
    $queen->print_analysis_status;
    $queen->get_num_needed_workers(); # apparently run not for the return value, but for the side-effects
}

printf("dbc %d disconnect cycles\n", $DBA->dbc->disconnect_count);
print("total jobs completes : ", $worker->work_done, "\n");

exit($return_value);


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

__DATA__

=pod

=head1 NAME

runWorker.pl

=head1 DESCRIPTION

 runWorker.pl is an eHive component script that does the work of a single Worker -
 specializes in one of the analyses and starts executing jobs of that analysis one-by-one or batch-by-batch.

 Most of the functionality of the eHive is accessible via beekeeper.pl script,
 but feel free to run the runWorker.pl if you think you know what you are doing :)

=head1 USAGE EXAMPLES

    # Run one local worker process in ehive_dbname and let the system pick up the analysis
runWorker.pl --host=hostname --port=3306 --user=username --password=secret --database=ehive_dbname

    # Run one local worker process in ehive_dbname and let the system pick up the analysis (another connection syntax)
runWorker.pl -url mysql://username:secret@hostname:port/ehive_dbname

    # Run one local worker process in ehive_dbname and specify the logic_name
runWorker.pl -url mysql://username:secret@hostname:port/ehive_dbname -logic_name fast_blast

    # Create a job outside the eHive to test the specified input_id
runWorker.pl -url mysql://username:secret@hostname:port/ehive_dbname -logic_name fast_blast -input_id '{ "foo" => 1500 }'

=head1 OPTIONS

=head2 Connection parameters

  -conf <path>           : config file describing db connection
  -regfile <path>        : path to a Registry configuration file
  -regname <string>      : species/alias name for the Hive DBAdaptor
  -url <url string>      : url defining where database is located
  -host <machine>        : mysql database host <machine>
  -port <port#>          : mysql port number
  -user <name>           : mysql connection user <name>
  -password <pass>       : mysql connection password
  -database <name>       : mysql database <name>

=head2 Job/Analysis control parameters:

  -analysis_id <id>      : analysis_id in db
  -logic_name <string>   : logic_name of analysis to make this worker
  -batch_size <num>      : #jobs to claim at a time
  -limit <num>           : #jobs to run before worker can die naturally
  -lifespan <num>        : number of minutes this worker is allowed to run
  -outdir <path>         : directory where stdout/stderr is redirected
  -bk <string>           : beekeeper identifier (deprecated and ignored)
  -pid <string>          : externally set process_id descriptor (e.g. lsf job_id, array_id)
  -input_id <string>     : test input_id on specified analysis (analysis_id or logic_name)
  -job_id <id>           : run specific job defined by analysis_job_id
  -analysis_stats        : show status of each analysis in hive
  -no_cleanup            : don't perform global_cleanup when worker exits
  -no_write              : don't write_output or auto_dataflow input_job

=head2 Other options:

  -help                  : print this help
  -debug <level>         : turn on debug messages at <level>

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

