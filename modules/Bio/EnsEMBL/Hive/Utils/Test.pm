
package Bio::EnsEMBL::Hive::Utils::Test;

use strict;
use warnings;
no warnings qw( redefine );

use Exporter;
use Carp qw{croak};
use Cwd qw{getcwd};

use Test::More;

use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module', 'stringify', 'destringify');

BEGIN {
    $ENV{'USER'}         ||= (getpwuid($<))[7];
    $ENV{'EHIVE_USER'}     = $ENV{'USER'};
    $ENV{'EHIVE_PASS'}   ||= 'password';
    $ENV{'EHIVE_ROOT_DIR'} =  getcwd();
}


our @ISA         = qw(Exporter);
our @EXPORT      = ();
our %EXPORT_TAGS = ();
our @EXPORT_OK   = qw( spurt standaloneJob init_pipeline );

our $VERSION = '0.00';

sub spurt {
    my ($content, $path) = @_;
    croak qq{Can't open file "$path": $!} unless open my $file, '>', $path;
    croak qq{Can't write to file "$path": $!}
    unless defined $file->syswrite($content);
    return $content;
}


my $events_to_test = undef;
sub standaloneJob {
    my ($module_or_file, $param_hash, $expected_events, $no_write) = @_;

    $events_to_test = $expected_events ? [@$expected_events] : undef;

    my $runnable_module = load_file_or_module( $module_or_file );
    ok($runnable_module, "module '$module_or_file' is loaded");

    my $runnable_object = $runnable_module->new();
    ok($runnable_object, "runnable is instantiated");
    $runnable_object->execute_writes(not $no_write);

    my $job = Bio::EnsEMBL::Hive::AnalysisJob->new( 'dbID' => -1 );
    my $input_id = stringify($param_hash);
    $job->input_id( $input_id );
    $job->dataflow_rules(1, []);

    $job->param_init( $runnable_object->strict_hash_format(), $runnable_object->param_defaults(), $job->input_id() );

    $runnable_object->input_job($job);
    $runnable_object->life_cycle();

    ok(!$job->died_somewhere(), 'job completed');
}


*Bio::EnsEMBL::Hive::Process::dataflow_output_id = sub {
    shift;
    _test_event('DATAFLOW', @_);
    return [1];
};

*Bio::EnsEMBL::Hive::Process::warning = sub {
    shift;
    _test_event('WARNING', @_);
};

sub _test_event {
    return unless $events_to_test;
    if (@$events_to_test) {
        is_deeply([@_], (shift @$events_to_test), "$_[0] event");
    } else {
        ok(0, "event-stack is not empty");
        use Data::Dumper;
        print Dumper([@_]);
    }
}


sub init_pipeline {
    my ($file_or_module, $options) = @_;

    my $pipeconfig_package_name = load_file_or_module( $file_or_module );
    ok($pipeconfig_package_name, "module '$file_or_module' is loaded");

    my $pipeconfig_object = $pipeconfig_package_name->new();

    $options = [] unless $options;
    push @$options, ('-hive_driver', 'sqlite');

    if ($options) {
	local @ARGV = @$options;
	$pipeconfig_object->process_options( 1 );
    }

    $pipeconfig_object->run_pipeline_create_commands();

    my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeconfig_object->pipeline_url(), -no_sql_schema_version_check => 1 );

    $hive_dba->load_collections();

    $pipeconfig_object->add_objects_from_config();

    $hive_dba->save_collections();

    return $pipeconfig_object;
}


1;
