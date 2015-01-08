
package Bio::EnsEMBL::Hive::Utils::Test;

use strict;
use warnings;

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
our @EXPORT_OK   = qw( spurt standaloneJob );

our $VERSION = '0.00';

sub spurt {
    my ($content, $path) = @_;
    croak qq{Can't open file "$path": $!} unless open my $file, '>', $path;
    croak qq{Can't write to file "$path": $!}
    unless defined $file->syswrite($content);
    return $content;
}


sub standaloneJob {
    my ($module_or_file, $param_hash, $no_write) = @_;

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


1;
