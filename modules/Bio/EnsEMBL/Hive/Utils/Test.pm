=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2020] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


package Bio::EnsEMBL::Hive::Utils::Test;

use strict;
use warnings;
no warnings qw( redefine );

use Exporter;
use Carp qw{croak};
use File::Spec;
use File::Temp qw{tempfile};

use Data::Dumper;

use Test::More;
use Test::Exception;

use Bio::EnsEMBL::Hive::DBSQL::DBConnection;
use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module', 'stringify', 'destringify', 'whoami');
use Bio::EnsEMBL::Hive::Utils::URL ('parse');

use Bio::EnsEMBL::Hive::Scripts::InitPipeline;
use Bio::EnsEMBL::Hive::Scripts::StandaloneJob;


our @ISA         = qw(Exporter);
our @EXPORT      = ();
our %EXPORT_TAGS = ();
our @EXPORT_OK   = qw( standaloneJob init_pipeline runWorker beekeeper generate_graph visualize_jobs db_cmd seed_pipeline peekJob get_test_urls get_test_url_or_die run_sql_on_db load_sql_in_db make_new_db_from_sqls make_hive_db safe_drop_database all_source_files);

our $VERSION = '0.00';


# Helper method to compare warning messages. It allows the expectation to
# be given as a string (for exact match) or a regular expression.
sub _compare_job_warnings {
    my ($got, $expects) = @_;
    subtest "WARNING content as expected" => sub {
        plan tests => 2;
        my $exp_mess = shift @$expects;
        if (re::is_regexp($exp_mess)) {
            like(shift @$got, $exp_mess, 'WARNING message as expected');
        } else {
            is(shift @$got, $exp_mess, 'WARNING message as expected');
        }
        is_deeply($got, $expects, 'remaining WARNING arguments');
    };
}


## Helper method to compare dataflows. Only exact string matches are
#allowed at the moment.
sub _compare_job_dataflows {
    my ($got, $expects) = @_;
    is_deeply($got, $expects, 'DATAFLOW content as expected');
}


=head2 standaloneJob

  Example     : standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
                              { 'inputlist' => [ [1,2], [3,4] ], 'column_names' => ['a', 'b'] },
                              [
                                [ 'DATAFLOW',
                                  [ { 'a' => 1, 'b' => 2 }, { 'a' => 3, 'b' => 4 }, ],
                                  2
                                ]
                              ]
                );
  Description : Run a given Runnable in "standalone job" mode, i.e. with parameters but no connection to the database.
                One can also give a list of events that the job is expected to raise. Currently, dataflows and warnings
                are supported. Examples can be found under t/05.runnabledb/
  Returntype  : None
  Exceptions  : TAP-style
  Caller      : general
  Status      : Stable

=cut

sub standaloneJob {
    my ($module_or_file, $param_hash, $expected_events, $flags) = @_;

    my $events_to_test = $expected_events ? [@$expected_events] : undef;

    my $input_id = stringify($param_hash);

    # When a list of events is given, it must match exactly what the
    # Runnable does (no missing / extra events, etc)
    my $_test_event = sub {
        my ($triggered_type, @got) = @_;
        if (@$events_to_test) {
            my $expects = shift @$events_to_test;
            my $expected_type = shift @$expects;
            if ($triggered_type ne $expected_type) {
                fail("Got a $triggered_type event but was expecting $expected_type\nEvent payload: " . stringify(\@got));
            } elsif ($triggered_type eq 'WARNING') {
                _compare_job_warnings(\@got, $expects);
            } else {
                _compare_job_dataflows(\@got, $expects);
            }
        } else {
            fail("event-stack is empty but the job emitted an event");
            print Dumper([@_]);
        }
    };

    # Local redefinition to hijack the events
    local *Bio::EnsEMBL::Hive::Process::dataflow_output_id = sub {
        shift;
        &$_test_event('DATAFLOW', @_);
        return [1];
    } if $expected_events;

    # Local redefinition to hijack the events
    local *Bio::EnsEMBL::Hive::Process::warning = sub {
        shift;
        &$_test_event('WARNING', @_);
    } if $expected_events;

    subtest "standalone run of $module_or_file" => sub {
        plan tests => 2 + ($expected_events ? 1+scalar(@$expected_events) : 0);
        lives_ok(sub {
            my $is_success = Bio::EnsEMBL::Hive::Scripts::StandaloneJob::standaloneJob($module_or_file, $input_id, $flags, $flags->{flow_into}, $flags->{language});
            if ($flags->{expect_failure}) {
                ok(!$is_success, 'job failed as expected');
            } else {
                ok($is_success, 'job completed');
            }
        }, sprintf('standaloneJob("%s", %s, (...), %s)', $module_or_file, stringify($param_hash), stringify($flags)));

        if ($expected_events) {
            ok(!scalar(@$events_to_test), 'no untriggered events');
            diag("Did not receive: " . stringify($events_to_test)) if scalar(@$events_to_test);
        }
    }
}


=head2 init_pipeline

  Arg[1]      : String $file_or_module. The location of the PipeConfig file
  Arg[2]      : String $url. The location of the database to be created
  Arg[3]      : (optional) Arrayref $args. Extra parameters of the pipeline (as on the command-line)
  Arg[4]      : (optional) Arrayref $tweaks. Tweaks to be applied to the database (as with the -tweak command-line option)
  Example     : init_pipeline(
                    'Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMultServer_conf',
                    $server_url,
                    [],
                    ['pipeline.param[take_time]=0']
                );
  Description : Initialize a new pipeline database for the given PipeConfig module name on that URL.
                $options simply represents the command-line options one would give on the command-line.
                Additionally, tweaks can be defined. Note that -hive_force_init is automatically added.
  Returntype  : None
  Exceptions  : TAP-style
  Caller      : general
  Status      : Stable

=cut

sub init_pipeline {
    my ($file_or_module, $url, $options, $tweaks) = @_;

    $options ||= [];

    if (ref($url) and !$tweaks) {
        # Probably the old syntax
        warn "The init_pipeline(\$options, \$tweaks) interface is deprecated. You should now give first a \$url parameter\n";
        $tweaks = $options;
        $options = $url;
        my ($url_flag_index) = grep {$options->[$_] eq '-pipeline_url'} (0..(scalar(@$options) - 1));
        unless (defined $url_flag_index) {
            die "Could not find a -url parameter in init_pipeline()'s arguments\n";
        }
        $url = (splice(@$options, $url_flag_index, 2))[1];
    }

    local @ARGV = @$options;
    unshift @ARGV, (-pipeline_url => $url, -hive_force_init => 1);

    lives_ok(sub {
        my $orig_unambig_url = Bio::EnsEMBL::Hive::Utils::URL::parse($url)->{'unambig_url'};
        ok($orig_unambig_url, 'Given URL could be parsed');
        my $returned_url = Bio::EnsEMBL::Hive::Scripts::InitPipeline::init_pipeline($file_or_module, $tweaks);
        ok($returned_url, 'pipeline initialized on '.$returned_url);

        my $returned_unambig_url = Bio::EnsEMBL::Hive::Utils::URL::parse($returned_url)->{'unambig_url'};
            # Both $url and $returned_url MAY contain the password (if applicable for the driver) but can be missing the port number assuming a default
            # Both $orig_unambig_url and $returned_unambig_url SHOULD contain the port number (if applicable for the driver) but WILL NOT contain a password
        is($returned_unambig_url, $orig_unambig_url, 'pipeline initialized on '.$url);
    }, sprintf('init_pipeline("%s", %s)', $file_or_module, stringify($options)));
}


=head2 _test_ehive_script

  Arg[1]      : String $script_name. The name of the script (assumed to be found in
                ensembl-hive/scripts/ once the .pl suffix added)
  Arg[2]      : String $url. The location of the database
  Arg[3]      : Arrayref $args. Extra arguments given to the script
  Arg[4]      : String $test_name (optional). The name of the test
  Description : Generic method that can run any eHive script and check its return status
  Returntype  : None
  Exceptions  : TAP-style
  Caller      : other methods in Utils::Test
  Status      : Stable

=cut

sub _test_ehive_script {
    my ($script_name, $url, $args, $test_name) = @_;
    $args ||= [];
    my @ext_args = ( defined($url) ? (-url => $url) : (), @$args );
    $test_name ||= 'Can run '.$script_name.(@ext_args ? ' with the following cmdline options: '.join(' ', @ext_args) : '');

    ok(!system($ENV{'EHIVE_ROOT_DIR'}.'/scripts/'.$script_name.'.pl', @ext_args), $test_name);
}


=head2 runWorker

  Arg[1]      : String $url. The location of the database
  Arg[2]      : Arrayref $args. Extra arguments given to runWorker
  Arg[3]      : String $test_name (optional). The name of the test
  Example     : runWorker($url, [ -can_respecialize => 1 ]);
  Description : Run a worker on the given pipeline in the current process.
                The worker options have been divided in three groups: the ones affecting its specialization,
                the ones affecting its "life" (how long it lasts), and the ones controlling its execution mode.
  Returntype  : None
  Exceptions  : TAP-style
  Caller      : general
  Status      : Stable

=cut

sub runWorker {
    my ($pipeline, $specialization_options, $life_options, $execution_options) = @_;
    if (ref($pipeline)) {
        # Probably the old syntax
        warn "The runWorker(\$pipeline, \$specialization_options, \$life_options, \$execution_options) interface is deprecated. You should now give a \$url parameter and combine all the options\n";
        my %combined_params = (%{$specialization_options||{}}, %{$life_options||{}}, %{$execution_options||{}});
        unless ($pipeline->hive_dba) {
            die "The pipeline doesn't have a hive_dba(). This is required by runWorker()\n";
        }
        my $url = $pipeline->hive_dba->dbc->url;
        return _test_ehive_script('runWorker', $url, [map {("-$_" => $combined_params{$_})} keys %combined_params]);
    }
    return _test_ehive_script('runWorker', @_);
}


=head2 seed_pipeline

  Arg[1]      : String $url. The location of the database
  Arg[2]      : Arrayref $args. Extra arguments given to seed_pipeline
  Arg[3]      : String $test_name (optional). The name of the test
  Example     : $seed_pipeline($url, [$arg1, $arg2], 'Run seed_pipeline with two arguments');
  Description : Very generic function to run seed_pipeline on the given database with the given arguments
  Returntype  : None
  Exceptions  : TAP-style
  Caller      : general
  Status      : Stable

=cut

sub seed_pipeline {
    my ($url, $logic_name, $input_id, $test_name, @other_options) = @_;
    return _test_ehive_script('seed_pipeline', $url, [-logic_name => $logic_name, -input_id => $input_id, @other_options], $test_name);
}


=head2 beekeeper

  Arg[1]      : String $url. The location of the database
  Arg[2]      : Arrayref $args. Extra arguments given to beekeeper.pl
  Arg[3]      : String $test_name (optional). The name of the test
  Example     : beekeeper($url, [$arg1, $arg2], 'Run beekeeper with two arguments');
  Description : Very generic function to run beekeeper on the given database with the given arguments
  Returntype  : None
  Exceptions  : TAP-style
  Caller      : general
  Status      : Stable

=cut

sub beekeeper {
    return _test_ehive_script('beekeeper', @_);
}


=head2 generate_graph

  Arg[1]      : String $url or undef. The location of the database
  Arg[2]      : Arrayref $args. Extra arguments given to generate_graph.pl
  Arg[3]      : String $test_name (optional). The name of the test
  Example     : generate_graph($url, [-output => 'lm_analyses.png'], 'Generate a PNG A-diagram');
  Description : Very generic function to run generate_graph.pl on the given database with the given arguments
  Returntype  : None
  Exceptions  : TAP-style
  Caller      : general
  Status      : Stable

=cut

sub generate_graph {
    return _test_ehive_script('generate_graph', @_);
}


=head2 visualize_jobs

  Arg[1]      : String $url. The location of the database
  Arg[2]      : Arrayref $args. Extra arguments given to visualize_jobs.pl
  Arg[3]      : String $test_name (optional). The name of the test
  Example     : visualize_jobs($url, [-output => 'lm_jobs.png', -accu_values], 'Generate a PNG J-diagram with accu values');
  Description : Very generic function to run visualize_jobs.pl on the given database with the given arguments
  Returntype  : None
  Exceptions  : TAP-style
  Caller      : general
  Status      : Stable

=cut

sub visualize_jobs {
    return _test_ehive_script('visualize_jobs', @_);
}

=head2 peekJob

  Arg[1]      : String $url. The location of the database
  Arg[2]      : Arrayref $args. Extra arguments given to peekJob.pl
  Arg[3]      : String $test_name (optional). The name of the test
  Example     : peekJob($url, [-job_id => 1], 'Check params for job 1');
  Description : Very generic function to run peekJob.pl on the given database with the given arguments
  Returntype  : None
  Exceptions  : TAP-style
  Caller      : general
  Status      : Stable

=cut

sub peekJob {
    return _test_ehive_script('peekJob', @_);
}


=head2 db_cmd

  Arg[1]      : String $url. The location of the database
  Arg[2]      : Arrayref $args. Extra arguments given to db_cmd.pl
  Arg[3]      : String $test_name (optional). The name of the test
  Example     : db_cmd($url, [-sql => 'DROP DATABASE'], 'Drop the database');
  Description : Very generic function to run db_cmd.pl on the given database with the given arguments
  Returntype  : None
  Exceptions  : TAP-style
  Caller      : general
  Status      : Stable

=cut

sub db_cmd {
    return _test_ehive_script('db_cmd', @_);
}


=head2 run_sql_on_db

  Arg[1]      : String $url. The location of the database
  Arg[2]      : String $sql. The SQL to run on the database
  Arg[3]      : String $test_name (optional). The name of the test
  Example     : run_sql_on_db($url, 'INSERT INTO sweets (name, quantity) VALUES (3, 'Snickers')');
  Description : Execute an SQL command on the given database and test its execution. This expects the
                command-line client to return a non-zero code in case of a failure.
  Returntype  : None
  Exceptions  : TAP-style
  Caller      : general
  Status      : Stable

=cut

sub run_sql_on_db {
    my ($url, $sql, $test_name) = @_;
    return _test_ehive_script('db_cmd', $url, [-sql => $sql], $test_name // 'Can run '.$sql);
}


=head2 load_sql_in_db

  Arg[1]      : String $url. The location of the database
  Arg[2]      : String $sql_file. The location of a file to load in the database
  Arg[3]      : String $test_name (optional). The name of the test
  Example     : load_sql_in_db($url, $file_with_sql_commands);
  Description : Execute an SQL script on the given database and test its execution.
                This expects the command-line client to return a non-zero code in
                case of a failure.
  Returntype  : None
  Exceptions  : TAP-style
  Caller      : general
  Status      : Stable

=cut

sub load_sql_in_db {
    my ($url, $sql_file, $test_name) = @_;
    my $cmd = $ENV{'EHIVE_ROOT_DIR'}.'/scripts/db_cmd.pl -url ' . $url . ' < ' . $sql_file;
    ok(!system($cmd), $test_name // 'Can load '.$sql_file);
}


=head2 make_new_db_from_sqls

  Arg[1]      : String $url. The location of the database
  Arg[2]      : Arrayref of string $sqls. Each element can be a SQL command or file to load
  Arg[3]      : String $test_name (optional). The name of the test
  Example     : make_new_db_from_sqls($url, 'CREATE TABLE sweets (name VARCHAR(40) NOT NULL, quantity INT UNSIGNED NOT NULL)');
  Description : Create a new database and apply a list of SQL commands using the two above functions.
                When an SQL command is a valid filename, the file is loaded rather than the command executed.
                Note that it first issues a DROP DATABASE statement in case the database already exists
  Returntype  : Bio::EnsEMBL::Hive::DBSQL::DBConnection $dbc
  Exceptions  : TAP-style
  Caller      : general
  Status      : Stable

=cut

sub make_new_db_from_sqls {
    my ($url, $sqls, $test_name) = @_;

    $sqls = [$sqls] unless ref($sqls);
    $test_name //= 'Creation of a new custom database';
    my $dbc;

    subtest $test_name => sub {
        $dbc = Bio::EnsEMBL::Hive::DBSQL::DBConnection->new( -url => $url );
        ok($dbc, 'URL could be parsed to make a DBConnection object');
        run_sql_on_db($url, 'DROP DATABASE IF EXISTS', 'Drop existing database');
        run_sql_on_db($url, 'CREATE DATABASE', 'Create new database');
        foreach my $s (@$sqls) {
            if (-e $s) {
                load_sql_in_db($url, $s);
            } else {
                run_sql_on_db($url, $s);
            }
        }
    };

    return $dbc;
}


=head2 make_hive_db

  Arg[1]      : String $url. The location of the database
  Arg[2]      : Boolean $use_triggers (optional, default 0). Whether we want to load the SQL triggers
  Example     : make_hive_db($url);
  Description : Create a new (empty) eHive database using the two above functions.
                This function follows the same step as init_pipeline
                Note that it first issues a DROP DATABASE statement in case the database already exists
  Returntype  : None
  Exceptions  : TAP-style
  Caller      : general
  Status      : Stable

=cut

sub make_hive_db {
    my ($url, $use_triggers) = @_;

    # Will insert two keys: "hive_all_base_tables" and "hive_all_views"
    my $hive_tables_sql = 'INSERT INTO hive_meta SELECT CONCAT("hive_all_", REPLACE(LOWER(TABLE_TYPE), " ", "_"), "s"), GROUP_CONCAT(TABLE_NAME) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = "%s" GROUP BY TABLE_TYPE';

    my $dbc;
    subtest 'Creation of a fresh eHive database' => sub {
        $dbc = Bio::EnsEMBL::Hive::DBSQL::DBConnection->new( -url => $url );
        ok($dbc, 'URL could be parsed to make a DBConnection object');
        run_sql_on_db($url, 'DROP DATABASE IF EXISTS');
        run_sql_on_db($url, 'CREATE DATABASE');
        load_sql_in_db($url, $ENV{'EHIVE_ROOT_DIR'} . '/sql/tables.' . $dbc->driver);
        load_sql_in_db($url, $ENV{'EHIVE_ROOT_DIR'} . '/sql/triggers.' . $dbc->driver) if $use_triggers;
        load_sql_in_db($url, $ENV{'EHIVE_ROOT_DIR'} . '/sql/foreign_keys.sql') if $dbc->driver ne 'sqlite';
        load_sql_in_db($url, $ENV{'EHIVE_ROOT_DIR'} . '/sql/procedures.' . $dbc->driver);
        run_sql_on_db($url, $hive_tables_sql) if $dbc->driver eq 'mysql';
    };

    return $dbc;
}


=head2 get_test_urls

  Arg [1]     : -driver => driver, -tag => tag, -no_user_prefix => 1
  Example     : my @urls = get_test_urls(-driver => 'mysql', -tag => 'longmult')
  Example     : my @urls = get_test_urls(-tag => 'gcpct')
  Example     : my @urls = get_test_urls(-driver => 'sqlite')
  Example     : my @urls = get_test_urls()
  Description : Creates a listref containing db urls based on the drivers specified in
              : the environment variable EHIVE_TEST_PIPELINE_URLS.
              : The URLs will be standard eHive URLs, looking like driver://connection/database
              : A database name consisting of [username]_ehive_test will be created
              : and placed in the URL
              : For example - mysql://me@127.0.0.1/ghopper_ehive_test
              :
              : If -tag is specified, then the list will have db names appended with '_tag' 
              : For example - (-tag => 'longmult') giving mysql://me@127.0.0.1/ghopper_ehive_test_longmult
              :
              : If -driver is specified, then the list will be restricted to urls for the
              : particular driver or comma-separated list of drivers specified (e.g. 'mysql,pgsql')
              :
              : If -no_user_prefix is specified, then the automatically-generated database names
              : won't be prefixed with the name of the current user
              :
              : If no drivers are specified in EHIVE_TEST_PIPELINE_URLS, it will check
              : to see if sqlite is available in the current path, and return a sqlite url
              : in the listref. Otherwise it will return an empty listref.
              :
 Returntype   : listref of db connection URLs as strings

=cut

sub get_test_urls {
  croak "wrong number of arguments for get_test_urls(); has to be even" if (scalar(@_) % 2);
  my %args = @_;
  my %argcheck = %args;
  delete(@argcheck{qw(-driver -tag -no_user_prefix)});
  croak "get_test_urls only accepts -driver and -tag as arguments" if (scalar(keys(%argcheck)) > 0);
 

  my %url_parses_by_driver;
  if (defined($ENV{EHIVE_TEST_PIPELINE_URLS})) {
    my @urls = split( /[\s,]+/, $ENV{EHIVE_TEST_PIPELINE_URLS} );
    foreach my $url (@urls) {
      if (my $parse = Bio::EnsEMBL::Hive::Utils::URL::parse($url) ) {
	push(@{$url_parses_by_driver{$parse->{driver}}}, $parse);
      } else {
	croak "badly formed url \"$url\" in EHIVE_TEST_PIPELINE_URLS";
      }
    }
  } else {
    my ($fh, $filename) = tempfile(UNLINK => 1);
    $url_parses_by_driver{'sqlite'} = [Bio::EnsEMBL::Hive::Utils::URL::parse('sqlite:///' . $filename)];
  }

  my $constructed_db_name = ($args{-no_user_prefix} ? '' : whoami().'_') . 'ehive_test';

  my @driver_parses;
  if (defined($args{-driver})) {
    my @requested_drivers = split(/,/, $args{-driver});
    
    foreach my $requested_driver (@requested_drivers) {
      $requested_driver =~ s/^\s+|\s+$//g;  #trim whitespace
      if (defined($url_parses_by_driver{$requested_driver})) {
	push(@driver_parses, @{$url_parses_by_driver{$requested_driver}});
      }
    }
  } else {
    foreach my $parses_for_driver (values(%url_parses_by_driver)) {
      push (@driver_parses, @{$parses_for_driver});
    }
  }

  my @list_of_urls;
  foreach my $parsed_url (@driver_parses) {

    ## Use the default database name if needed, and append the tag (if given)
    $parsed_url->{'dbname'} ||= $constructed_db_name;
    $parsed_url->{'dbname'} .= $constructed_db_name if ($parsed_url->{'driver'} eq 'sqlite') && ($parsed_url->{'dbname'} =~ /\/$/);
    $parsed_url->{'dbname'} .= '_'.$args{-tag} if defined $args{-tag};

    my $final_url = Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($parsed_url);

    push (@list_of_urls, $final_url); 
  }

  return \@list_of_urls;
}


=head2 get_test_url_or_die

  Arg [1]     : see get_test_urls()
  Example     : my $url = get_test_url_or_die(-driver => 'mysql', -tag => 'longmult')
  Example     : my $url = get_test_url_or_die(-tag => 'gcpct')
  Example     : my $url = get_test_url_or_die(-driver => 'sqlite')
  Example     : my $url = get_test_url_or_die()
  Description : Wrapper around get_test_urls() that returns one of the test URLs, or
                die if no databases are available
  Returntype  : db connection URL as a string

=cut

sub get_test_url_or_die {
    my $list_of_urls = get_test_urls(@_);
    croak "No test databases are available" unless scalar(@$list_of_urls);
    return (sort @$list_of_urls)[0];
}


=head2 safe_drop_database

  Arg[1]      : DBAdaptor $hive_dba
  Example     : safe_drop_database( $hive_dba );
  Description : Wait for all workers to complete, disconnect from the database and drop it.
  Returntype  : None
  Caller      : test scripts

=cut

sub safe_drop_database {
    my $hive_dba = shift;

        # In case workers are still alive:
    my $worker_adaptor = $hive_dba->get_WorkerAdaptor;
    while( $worker_adaptor->count_all("status != 'DEAD'") ) {
        sleep(1);
    }

    my $dbc = $hive_dba->dbc;
    $dbc->disconnect_if_idle();
    run_sql_on_db($dbc->url, 'DROP DATABASE');
}


=head2 all_source_files

  Arg [n]    : Directories to scan.
  Example    : my @files = all_source_files('modules');
  Description: Scans the given directories and returns all found instances of
               source code. This includes Perl (pl,pm,t), Java(java), C(c,h) and
               SQL (sql) suffixed files.
  Returntype : Array of all found files

=cut

sub all_source_files {
  my @starting_dirs = @_;
  my @files;
  my @dirs = @starting_dirs;
  my %excluded_dir = map {$_ => 1} qw(_build build target .git __pycache__ bioperl-live cover_db deps);
  while ( my $file = shift @dirs ) {
    if ( -d $file ) {
      opendir my $dir, $file or next;
      my @new_files =
        grep { !$excluded_dir{$_} && $_ !~ /^\./ }
        File::Spec->no_upwards(readdir $dir);
      closedir $dir;
      push(@dirs, map {File::Spec->catfile($file, $_)} @new_files);
    }
    if ( -f $file ) {
      #next unless $file =~ /(?-xism:\.(?:[cht]|p[lm]|java|sql))/;
      push(@files, $file);
    }
  } # while
  return @files;
}

1;
