#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2021] EMBL-European Bioinformatics Institute
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

use Cwd;
use File::Basename;

use Test::More; # tests => 22;
use Test::Exception;
use Test::Warn;

use Bio::EnsEMBL::Hive::Utils::Config;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Meadow' );
    use_ok( 'Bio::EnsEMBL::Hive::Valley' );
}

# Need EHIVE_ROOT_DIR to access the default config file
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );
my @config_files = Bio::EnsEMBL::Hive::Utils::Config->default_config_files();
my $config = Bio::EnsEMBL::Hive::Utils::Config->new(@config_files);

my @virtual_methods = qw(name get_current_worker_process_id count_running_workers count_pending_workers_by_rc_name status_of_all_our_workers check_worker_is_alive_and_mine kill_worker submit_workers);

# Check that the base Meadow class has some virtual methods
subtest 'Bio::EnsEMBL::Hive::Meadow' => sub {
    my $virtual_meadow = eval {
        # Meadow's constructor calls cached_name(), which needs name()
        # name() will revert to its original implementation at the end of the scope
        local *Bio::EnsEMBL::Hive::Meadow::name = sub {
            return 'this_is_me';
        };
        return Bio::EnsEMBL::Hive::Meadow->new();
    };
    foreach my $method (@virtual_methods) {
        throws_ok {$virtual_meadow->$method()} qr/Please use a derived method/, $method.'() is virtual in Meadow';
    }
    foreach my $method (qw(parse_report_source_line get_report_entries_for_process_ids get_report_entries_for_time_interval)) {
        warning_like {$virtual_meadow->$method()} qr/Bio::EnsEMBL::Hive::Meadow does not support resource usage logs/, $method.'() has a default (empty) implementation in Meadow';
    }
};

# Check that the meadows are fully implemented
foreach my $meadow_class ( @{ Bio::EnsEMBL::Hive::Valley->loaded_meadow_drivers() } ) {
    if($meadow_class->check_version_compatibility) {
        subtest $meadow_class => sub
        {
            lives_ok( sub {
                    eval "require $meadow_class";
                }, $meadow_class.' can be compiled and imported');
            my $meadow_object = $meadow_class->new();
            ok($meadow_object->isa('Bio::EnsEMBL::Hive::Meadow'), $meadow_class.' implements the eHive Meadow interface');

            # Let's check that the virtual methods have been redefined
            foreach my $method (@virtual_methods) {
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

my $mtdne = 'meadow_that_does_not_exist';
throws_ok {$valley->set_default_meadow_type($mtdne)} qr/Meadow '$mtdne' does not seem to be available on this machine, please investigate/, 'Cannot set an unexisting meadow as default';

done_testing();

