#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;

use Test::More; # tests => 22;
use Test::Exception;

use Bio::EnsEMBL::Hive::Utils::Config;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Valley' );
}

# Need EHIVE_ROOT_DIR to access the default config file
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );
my @config_files = Bio::EnsEMBL::Hive::Utils::Config->default_config_files();
my $config = Bio::EnsEMBL::Hive::Utils::Config->new(@config_files);

# Check that the meadows are fully implemented
foreach my $meadow_class ( @{ Bio::EnsEMBL::Hive::Valley->get_implemented_meadow_list() } ) {
    subtest $meadow_class => sub
    {
        lives_ok( sub {
                eval "require $meadow_class";
            }, $meadow_class.' can be compiled and imported');
        my $meadow_object = $meadow_class->new();
        ok($meadow_object->isa('Bio::EnsEMBL::Hive::Meadow'), $meadow_class.' implements the eHive Meadow interface');

        # Let's check that the virtual methods have been redefined
        foreach my $method (qw(name get_current_worker_process_id count_running_workers count_pending_workers_by_rc_name status_of_all_our_workers check_worker_is_alive_and_mine kill_worker submit_workers)) {
            eval {
                $meadow_object->$method();
            };
            if ($@) {
                unlike($@, qr/Please use a derived method/, $method.'() is implemented');
            } else {
                ok(1, $method.'() is implemented');
            }
        }
    }
}

my $pipeline_name = 'fake_pipeline_name';

my $valley = Bio::EnsEMBL::Hive::Valley->new($config, 'LOCAL', $pipeline_name);

ok($valley, 'Can build a Valley');

my ($meadow_type, $meadow_name) = $valley->whereami();
ok($meadow_type, 'Could find the neadow type');
ok($meadow_name, 'Could find the neadow name');

my $available_meadows = $valley->get_available_meadow_list();
ok(scalar(@$available_meadows), 'At least a meadow could be found');
is($available_meadows->[-1]->type, 'LOCAL', 'The last one is LOCAL');
foreach my $meadow (@$available_meadows) {
    is($meadow->pipeline_name, $pipeline_name, $meadow->type.' is registered to the pipeline');
}

done_testing();

