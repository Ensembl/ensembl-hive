#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Queen;
use Bio::EnsEMBL::Hive::Meadow;

Bio::EnsEMBL::Registry->no_version_check(1);

my $db_conf = {
    -host   => '',
    -port   => 3306,
    -user   => 'ensro',
    -pass   => '',
    -dbname => '',
};

my ($conf_file, $reg_conf, $reg_alias, $url);                   # Connection parameters
my ($rc_id, $logic_name, $analysis_id, $input_id, $job_id);     # Task specification parameters
my ($batch_size, $job_limit, $life_span, $no_cleanup, $no_write, $hive_output_dir, $worker_output_dir, $retry_throwing_jobs);   # Worker control parameters
my ($help, $debug, $show_analysis_stats, $maximise_concurrency);

GetOptions(

# Connection parameters:
           'conf=s'                     => \$conf_file,
           'reg_conf|regfile=s'         => \$reg_conf,
           'reg_alias|regname=s'        => \$reg_alias,
           'url=s'                      => \$url,
           'host|dbhost=s'              => \$db_conf->{'-host'},
           'port|dbport=i'              => \$db_conf->{'-port'},
           'user|dbuser=s'              => \$db_conf->{'-user'},
           'password|dbpass=s'          => \$db_conf->{'-pass'},
           'database|dbname=s'          => \$db_conf->{'-dbname'},

# Task specification parameters:
           'rc_id=i'                    => \$rc_id,
           'logic_name=s'               => \$logic_name,
           'analysis_id=i'              => \$analysis_id,
           'input_id=s'                 => \$input_id,
           'job_id=i'                   => \$job_id,

# Worker control parameters:
           'batch_size=i'               => \$batch_size,
           'job_limit|limit=i'          => \$job_limit,
           'life_span|lifespan=i'       => \$life_span,
           'no_cleanup'                 => \$no_cleanup,
           'no_write|nowrite'           => \$no_write,
           'hive_output_dir|outdir=s'   => \$hive_output_dir,       # keep compatibility with the old name
           'worker_output_dir=s'        => \$worker_output_dir,     # will take precedence over hive_output_dir if set
           'retry_throwing_jobs=i'      => \$retry_throwing_jobs,

# Other commands
           'h|help'                     => \$help,
           'debug=i'                    => \$debug,
           'analysis_stats'             => \$show_analysis_stats,
           'maximise_concurrency=i'     => \$maximise_concurrency,

# loose arguments interpreted as database name (for compatibility with mysql[dump])
            '<>', sub { $db_conf->{'-dbname'} = shift @_; },
);

if ($help) { usage(0); }

parse_conf($conf_file);

my $DBA;
if($reg_conf) {
    Bio::EnsEMBL::Registry->load_all($reg_conf);
    $DBA = Bio::EnsEMBL::Registry->get_DBAdaptor($reg_alias || 'hive', 'hive');
} elsif($url) {
    $DBA = Bio::EnsEMBL::Hive::URLFactory->fetch($url) or die "Unable to connect to '$url'\n";
} elsif ($db_conf->{'-host'} and $db_conf->{'-user'} and $db_conf->{'-dbname'}) {
    $DBA = new Bio::EnsEMBL::Hive::DBSQL::DBAdaptor(%$db_conf);
} else {
    print "\nERROR : Connection parameters (regfile+regname, url or dbhost+dbuser+dbname) need to be specified\n\n";
    usage(1);
}

unless($DBA and $DBA->isa("Bio::EnsEMBL::Hive::DBSQL::DBAdaptor")) {
  print("ERROR : no database connection\n\n");
  usage(1);
}

my $queen = $DBA->get_Queen();
$queen->{maximise_concurrency} = 1 if ($maximise_concurrency);

my ($meadow_type, $process_id, $exec_host) = Bio::EnsEMBL::Hive::Meadow->guess_current_type_pid_exechost();

print "runWorker(-MeadowType => $meadow_type, -ProcessId => $process_id, -ExecHost => $exec_host)\n";

my $worker;

eval {
    $worker = $queen->create_new_worker(
      # Worker identity:
         -meadow_type           => $meadow_type,
         -process_id            => $process_id,
         -exec_host             => $exec_host,

      # Task specification:
         -rc_id                 => $rc_id,
         -logic_name            => $logic_name,
         -analysis_id           => $analysis_id,
         -input_id              => $input_id,
         -job_id                => $job_id,

      # Worker control parameters:
         -batch_size            => $batch_size,
         -job_limit             => $job_limit,
         -life_span             => $life_span,
         -no_cleanup            => $no_cleanup,
         -no_write              => $no_write,
         -worker_output_dir     => $worker_output_dir,
         -hive_output_dir       => $hive_output_dir,
         -retry_throwing_jobs   => $retry_throwing_jobs,

      # Other parameters:
         -debug                 => $debug,
    );
};
my $msg_thrown = $@;

unless($worker) {
    $queen->print_analysis_status if($show_analysis_stats);
    print "\n=== COULDN'T CREATE WORKER ===\n";

    if($msg_thrown) {
        print "$msg_thrown\n";
        usage(1);
    } else {
        exit(1);
    }
}

$worker->run();

if($show_analysis_stats) {
    $queen->print_analysis_status;
    $queen->get_num_needed_workers(); # apparently run not for the return value, but for the side-effects
}

exit 0;

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
  my $conf_file = shift;

  if($conf_file and (-e $conf_file)) {
    #read configuration file from disk
    my @conf_list = @{do $conf_file};

    foreach my $confPtr (@conf_list) {
      #print("HANDLE type " . $confPtr->{TYPE} . "\n");
      if(($confPtr->{TYPE} eq 'COMPARA') or ($confPtr->{TYPE} eq 'DATABASE')) {
        $db_conf = $confPtr;
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
    runWorker.pl --host=hostname --port=3306 --user=username --password=secret ehive_dbname

        # Run one local worker process in ehive_dbname and let the system pick up the analysis (another connection syntax)
    runWorker.pl -url mysql://username:secret@hostname:port/ehive_dbname

        # Run one local worker process in ehive_dbname and specify the logic_name
    runWorker.pl -url mysql://username:secret@hostname:port/ehive_dbname -logic_name fast_blast

        # Run a specific job (by a local worker process):
    runWorker.pl -url mysql://username:secret@hostname:port/ehive_dbname -job_id 123456

        # Create a job outside the eHive to test the specified input_id
    runWorker.pl -url mysql://username:secret@hostname:port/ehive_dbname -logic_name fast_blast -input_id '{ "foo" => 1500 }'

=head1 OPTIONS

=head2 Connection parameters:

    -conf <path>            : config file describing db connection
    -regfile <path>         : path to a Registry configuration file
    -regname <string>       : species/alias name for the Hive DBAdaptor
    -url <url string>       : url defining where database is located
    -host <machine>         : mysql database host <machine>
    -port <port#>           : mysql port number
    -user <name>            : mysql connection user <name>
    -password <pass>        : mysql connection password
    [-database] <name>      : mysql database <name>

=head2 Task specificaton parameters:

    -rc_id <id>                 : resource class id
    -logic_name <string>        : pre-specify this worker in a particular analysis defined by name
    -analysis_id <id>           : pre-specify this worker in a particular analysis defined by database id
    -input_id <string>          : test this input_id on specified analysis (defined either by analysis_id or logic_name)
    -job_id <id>                : run a specific job defined by its database id

=head2 Worker control parameters:

    -batch_size <num>           : #jobs to claim at a time
    -job_limit <num>            : #jobs to run before worker can die naturally
    -life_span <num>            : number of minutes this worker is allowed to run
    -no_cleanup                 : don't perform temp directory cleanup when worker exits
    -no_write                   : don't write_output or auto_dataflow input_job
    -hive_output_dir <path>     : directory where stdout/stderr of the whole hive of workers is redirected
    -worker_output_dir <path>   : directory where stdout/stderr of this particular worker is redirected
    -retry_throwing_jobs <0|1>  : if a job dies *knowingly*, should we retry it by default?

=head2 Other options:

    -help                       : print this help
    -debug <level>              : turn on debug messages at <level>
    -analysis_stats             : show status of each analysis in hive
    -maximise_concurrency <0|1> : different scheduling strategies of analysis self-assignment

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

