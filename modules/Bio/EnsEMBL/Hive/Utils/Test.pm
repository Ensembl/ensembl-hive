=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2021] EMBL-European Bioinformatics Institute

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
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module', 'stringify', 'destringify');


our @ISA         = qw(Exporter);
our @EXPORT      = ();
our %EXPORT_TAGS = ();
our @EXPORT_OK   = qw( init_pipeline runWorker );

our $VERSION = '0.00';


sub init_pipeline {
    my ($file_or_module, $pipeline_url, $options) = @_;

    $options ||= [];

    my $hive_dba;
    local @ARGV = @$options;
    local %Bio::EnsEMBL::Hive::Cacheable::cache_by_class;

    lives_ok(sub {
        my @cmd = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/init_pipeline.pl', $file_or_module, '-pipeline_url', $pipeline_url, @$options);
        my $rc = system(@cmd);
        ok(!$rc, 'pipeline initialized');
        $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(-url => $pipeline_url);
        ok($hive_dba, 'DBAdaptor created');
    }, sprintf('init_pipeline("%s on %s", %s)', $file_or_module, $pipeline_url, stringify($options)));

    return $hive_dba;
}


sub runWorker {
    my ($hive_dba, $specialization_options, $life_options, $execution_options) = @_;

    $specialization_options ||= {};
    $life_options ||= {};
    $execution_options ||= {};

    lives_ok(sub {
        my $pipeline_url = $hive_dba->dbc->url;
        my @cmd = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/runWorker.pl', '-url', $pipeline_url);
        my %super_hash = (%$specialization_options, %$life_options, %$execution_options);
        foreach my $option (keys %super_hash) {
            push @cmd, ('-'.$option, $super_hash{$option});
        }
        my $rc = system(@cmd);
        ok(!$rc, 'worker successful');
    }, sprintf('runWorker()'));
}


1;
