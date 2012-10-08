#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long;
use Bio::EnsEMBL::Hive::Utils ('script_usage');
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Queen;
use Bio::EnsEMBL::Hive::Valley;

Bio::EnsEMBL::Registry->no_version_check(1);

my $db_conf = {
    -host   => '',
    -port   => 3306,
    -user   => 'ensro',
    -pass   => '',
    -dbname => '',
};

my ($reg_conf, $reg_alias, $url);                   # Connection parameters
my ($rc_id, $rc_name, $analysis_id, $logic_name, $job_id);     # Task specification parameters
my ($job_limit, $life_span, $no_cleanup, $no_write, $hive_log_dir, $worker_log_dir, $retry_throwing_jobs, $compile_module_once);   # Worker control parameters
my ($help, $debug);

GetOptions(

# Connection parameters:
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
           'rc_name=s'                  => \$rc_name,
           'analysis_id=i'              => \$analysis_id,
           'logic_name=s'               => \$logic_name,
           'job_id=i'                   => \$job_id,

# Worker control parameters:
           'job_limit|limit=i'          => \$job_limit,
           'life_span|lifespan=i'       => \$life_span,
           'no_cleanup'                 => \$no_cleanup,
           'no_write'                   => \$no_write,
           'hive_log_dir|hive_output_dir=s'         => \$hive_log_dir,       # keep compatibility with the old name
           'worker_log_dir|worker_output_dir=s'     => \$worker_log_dir,     # will take precedence over hive_log_dir if set
           'retry_throwing_jobs=i'      => \$retry_throwing_jobs,
           'compile_module_once=i'      => \$compile_module_once,

# Other commands
           'h|help'                     => \$help,
           'debug=i'                    => \$debug,

# loose arguments interpreted as database name (for compatibility with mysql[dump])
            '<>', sub { $db_conf->{'-dbname'} = shift @_; },
);

if ($help) { script_usage(0); }

if($reg_conf) {     # if reg_conf is defined, we load it regardless of whether it is used to connect to the Hive database or not:
    Bio::EnsEMBL::Registry->load_all($reg_conf);
}

my $DBA;
if($reg_alias) {
    $DBA = Bio::EnsEMBL::Registry->get_DBAdaptor($reg_alias, 'hive');
} elsif($url) {
    $DBA = Bio::EnsEMBL::Hive::URLFactory->fetch($url) or die "Unable to connect to '$url'\n";
} elsif ($db_conf->{'-host'} and $db_conf->{'-user'} and $db_conf->{'-dbname'}) {
    $DBA = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( %$db_conf );
} else {
    print "\nERROR : Connection parameters (reg_conf+reg_alias, url or dbhost+dbuser+dbname) need to be specified\n\n";
    script_usage(1);
}

unless($DBA and $DBA->isa("Bio::EnsEMBL::Hive::DBSQL::DBAdaptor")) {
  print "ERROR : no database connection\n\n";
  script_usage(1);
}

my $queen = $DBA->get_Queen();

my ($meadow_type, $meadow_name, $process_id, $exec_host) = Bio::EnsEMBL::Hive::Valley->new()->whereami();

print "runWorker(-MeadowType => $meadow_type, -MeadowName => $meadow_name, -ProcessId => $process_id, -ExecHost => $exec_host)\n";

my $worker;

eval {
    $worker = $queen->create_new_worker(
      # Worker identity:
         -meadow_type           => $meadow_type,
         -meadow_name           => $meadow_name,
         -process_id            => $process_id,
         -exec_host             => $exec_host,

      # Task specification:
         -rc_id                 => $rc_id,
         -rc_name               => $rc_name,
         -analysis_id           => $analysis_id,
         -logic_name            => $logic_name,
         -job_id                => $job_id,

      # Worker control parameters:
         -job_limit             => $job_limit,
         -life_span             => $life_span,
         -no_cleanup            => $no_cleanup,
         -no_write              => $no_write,
         -worker_log_dir        => $worker_log_dir,
         -hive_log_dir          => $hive_log_dir,
         -retry_throwing_jobs   => $retry_throwing_jobs,
         -compile_module_once   => $compile_module_once,

      # Other parameters:
         -debug                 => $debug,
    );
};
my $msg_thrown = $@;

if($worker) {

    $worker->run();

} else {

    $queen->print_analysis_status;
    print "\n=== COULDN'T CREATE WORKER ===\n";

    if($msg_thrown) {
        print "$msg_thrown\n";
    }
    exit(1);
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

=head1 OPTIONS

=head2 Connection parameters:

    -conf <path>            : config file describing db connection
    -reg_conf <path>        : path to a Registry configuration file
    -reg_alias <string>     : species/alias name for the Hive DBAdaptor
    -url <url string>       : url defining where database is located
    -host <machine>         : mysql database host <machine>
    -port <port#>           : mysql port number
    -user <name>            : mysql connection user <name>
    -password <pass>        : mysql connection password
    [-database] <name>      : mysql database <name>

=head2 Task specificaton parameters:

    -rc_id <id>                 : resource class id
    -rc_name <string>           : resource class name
    -analysis_id <id>           : pre-specify this worker in a particular analysis defined by database id
    -logic_name <string>        : pre-specify this worker in a particular analysis defined by name
    -job_id <id>                : run a specific job defined by its database id

=head2 Worker control parameters:

    -job_limit <num>            : #jobs to run before worker can die naturally
    -life_span <num>            : number of minutes this worker is allowed to run
    -no_cleanup                 : don't perform temp directory cleanup when worker exits
    -no_write                   : don't write_output or auto_dataflow input_job
    -hive_log_dir <path>        : directory where stdout/stderr of the whole hive of workers is redirected
    -worker_log_dir <path>      : directory where stdout/stderr of this particular worker is redirected
    -retry_throwing_jobs <0|1>  : if a job dies *knowingly*, should we retry it by default?
    -compile_module_once 0|1    : should we compile the module only once (desired future behaviour), or pretend to do it before every job (current behaviour)?

=head2 Other options:

    -help                       : print this help
    -debug <level>              : turn on debug messages at <level>
    -analysis_stats             : show status of each analysis in hive

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

