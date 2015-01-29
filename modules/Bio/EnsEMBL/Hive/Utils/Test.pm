
package Bio::EnsEMBL::Hive::Utils::Test;

use strict;
use warnings;
no warnings qw( redefine );

use Exporter;
use Carp qw{croak};
use Cwd qw{getcwd};

use Test::More;
use Test::Exception;

use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module', 'stringify', 'destringify');

use Bio::EnsEMBL::Hive::Scripts::InitPipeline;
use Bio::EnsEMBL::Hive::Scripts::StandaloneJob;

BEGIN {
    $ENV{'USER'}         ||= (getpwuid($<))[7];
    $ENV{'EHIVE_USER'}     = $ENV{'USER'};
    $ENV{'EHIVE_PASS'}   ||= 'password';
    $ENV{'EHIVE_ROOT_DIR'} ||=  getcwd();
}


our @ISA         = qw(Exporter);
our @EXPORT      = ();
our %EXPORT_TAGS = ();
our @EXPORT_OK   = qw( spurt standaloneJob init_pipeline runWorker );

our $VERSION = '0.00';

sub spurt {
    my ($content, $path) = @_;
    croak qq{Can't open file "$path": $!} unless open my $file, '>', $path;
    croak qq{Can't write to file "$path": $!}
    unless defined $file->syswrite($content);
    return $content;
}


sub standaloneJob {
    my ($module_or_file, $param_hash, $expected_events, $flags) = @_;

    my $events_to_test = $expected_events ? [@$expected_events] : undef;

    my $input_id = stringify($param_hash);

    my $_test_event = sub {
        if (@$events_to_test) {
            is_deeply([@_], (shift @$events_to_test), "$_[0] event");
        } else {
            fail("event-stack is empty, cannot get the next expected event");
            use Data::Dumper;
            print Dumper([@_]);
        }
    };

    local *Bio::EnsEMBL::Hive::Process::dataflow_output_id = sub {
        shift;
        &$_test_event('DATAFLOW', @_);
        return [1];
    } if $expected_events;

    local *Bio::EnsEMBL::Hive::Process::warning = sub {
        shift;
        &$_test_event('WARNING', @_);
    } if $expected_events;

    lives_and(sub {
        ok(Bio::EnsEMBL::Hive::Scripts::StandaloneJob::standaloneJob($module_or_file, $input_id, $flags, undef), 'job completed');
    }, sprintf('standaloneJob("%s", %s, (...), %s)', $module_or_file, stringify($param_hash), stringify($flags)));

    ok(!scalar(@$events_to_test), 'no untriggered events') if $expected_events;
}


sub init_pipeline {
    my ($file_or_module, $options) = @_;

    $options ||= [];

    my $hive_dba;
    local @ARGV = @$options;
    lives_and(sub {
        $hive_dba = Bio::EnsEMBL::Hive::Scripts::InitPipeline::init_pipeline($file_or_module, 1);
        ok($hive_dba, 'pipeline initialized');
        %Bio::EnsEMBL::Hive::Cacheable::cache_by_class = %;
    }, sprintf('init_pipeline("%s", %s)', $file_or_module, stringify($options)));

    return $hive_dba;
}


sub runWorker {
    my ($hive_dba, $specialization_options, $life_options, $execution_options) = @_;

    isa_ok($hive_dba, 'Bio::EnsEMBL::Hive::DBSQL::DBAdaptor');
    $specialization_options ||= {};
    $life_options ||= {};
    $execution_options ||= {};

    my $queen = $hive_dba->get_Queen();
    isa_ok($queen, 'Bio::EnsEMBL::Hive::Queen', 'God bless the Queen');

    my ($meadow_type, $meadow_name, $process_id, $meadow_host, $meadow_user) = Bio::EnsEMBL::Hive::Valley->new()->whereami();
    ok($meadow_type && $meadow_name && $process_id && $meadow_host && $meadow_user, 'Valley is fully defined');

    # Sync the hive
    my $list_of_analyses = $hive_dba->get_AnalysisAdaptor->fetch_all_by_pattern( $specialization_options->{analyses_pattern} );
    $queen->synchronize_hive( $list_of_analyses );

    # Create the worker
    my $worker = $queen->create_new_worker(
          # Worker identity:
             -meadow_type           => $meadow_type,
             -meadow_name           => $meadow_name,
             -process_id            => $process_id,
             -meadow_host           => $meadow_host,
             -meadow_user           => $meadow_user,
             -resource_class_name   => $specialization_options->{resource_class_name},

          # Worker control parameters:
             -job_limit             => $life_options->{job_limit},
             -life_span             => $life_options->{life_span},
             -no_cleanup            => $execution_options->{no_cleanup},
             -no_write              => $execution_options->{no_write},
             -retry_throwing_jobs   => $life_options->{retry_throwing_jobs},
             -can_respecialize      => $specialization_options->{can_respecialize},
    );
    isa_ok($worker, 'Bio::EnsEMBL::Hive::Worker', 'we have a worker !');

    # Run the worker
    eval {
        $worker->run( {
             -analyses_pattern      => $specialization_options->{analyses_pattern},
             -job_id                => $specialization_options->{job_id},
        } );
        pass('run the worker');
    } or do {
        fail("could not run the worker:\n$@");
    };
}

1;
