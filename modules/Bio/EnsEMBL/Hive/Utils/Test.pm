=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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

use Test::More;
use Test::Exception;

use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module', 'stringify', 'destringify');

use Bio::EnsEMBL::Hive::Scripts::InitPipeline;
use Bio::EnsEMBL::Hive::Scripts::StandaloneJob;
use Bio::EnsEMBL::Hive::Scripts::RunWorker;


our @ISA         = qw(Exporter);
our @EXPORT      = ();
our %EXPORT_TAGS = ();
our @EXPORT_OK   = qw( standaloneJob init_pipeline runWorker );

our $VERSION = '0.00';


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

    subtest "standalone run of $module_or_file" => sub {
        plan tests => 2 + ($expected_events ? 1+scalar(@$expected_events) : 0);
        lives_ok(sub {
            ok(Bio::EnsEMBL::Hive::Scripts::StandaloneJob::standaloneJob($module_or_file, $input_id, $flags, undef, $flags->{language}), 'job completed');
        }, sprintf('standaloneJob("%s", %s, (...), %s)', $module_or_file, stringify($param_hash), stringify($flags)));

        ok(!scalar(@$events_to_test), 'no untriggered events') if $expected_events;
    }
}


sub init_pipeline {
    my ($file_or_module, $options) = @_;

    $options ||= [];

    my $url;
    local @ARGV = @$options;

    lives_ok(sub {
        $url = Bio::EnsEMBL::Hive::Scripts::InitPipeline::init_pipeline($file_or_module);
        ok($url, 'pipeline initialized');
    }, sprintf('init_pipeline("%s", %s)', $file_or_module, stringify($options)));

    return $url;
}


sub runWorker {
    my ($pipeline, $specialization_options, $life_options, $execution_options) = @_;

    $specialization_options->{force_sync} = 1;

    lives_ok(sub {
        Bio::EnsEMBL::Hive::Scripts::RunWorker::runWorker($pipeline, $specialization_options, $life_options, $execution_options);
    }, sprintf('runWorker()'));
}


1;
