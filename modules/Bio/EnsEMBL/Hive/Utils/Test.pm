
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
    my ($module_or_file, $param_hash, $expected_events, $flags) = @_;

    $events_to_test = $expected_events ? [@$expected_events] : undef;

    my $input_id = stringify($param_hash);

    eval {
        ok(Bio::EnsEMBL::Hive::Scripts::StandaloneJob::standaloneJob($module_or_file, $input_id, $flags, undef, 1), 'job completed');
    };
    if ($@) {
        fail(sprintf('standaloneJob("%s", "%s")', $module_or_file, stringify($param_hash)));
        print $@, "\n";
    }
    ok(!scalar(@$events_to_test), 'no untriggered events') if $expected_events;
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
        fail("event-stack is empty, cannot get the next expected event");
        use Data::Dumper;
        print Dumper([@_]);
    }
}


sub init_pipeline {
    my ($file_or_module, $options) = @_;

    $options ||= [];

    my $hive_dba;
    local @ARGV = @$options;
    lives_and(sub {
        $hive_dba = Bio::EnsEMBL::Hive::Scripts::InitPipeline::init_pipeline($file_or_module, 1);
        ok($hive_dba, 'pipeline initialized');
        $hive_dba->init_collections();
    }, sprintf('init_pipeline("%s", %s)', $file_or_module, stringify($options)));

    return $hive_dba;
}


1;
