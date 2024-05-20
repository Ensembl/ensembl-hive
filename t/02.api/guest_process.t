#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2023] EMBL-European Bioinformatics Institute
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

use Test::More tests => 3;
use Test::Exception;

#use Bio::EnsEMBL::Hive::Utils::Config;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::GuestProcess' );
}

# Need EHIVE_ROOT_DIR to configure the paths
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );


subtest 'check_version_compatibility' => sub {
    my $current_version = Bio::EnsEMBL::Hive::GuestProcess->get_protocol_version;

    ok(Bio::EnsEMBL::Hive::GuestProcess->check_version_compatibility("${current_version}.0"), 'Passes when the major number matches');
    ok(!Bio::EnsEMBL::Hive::GuestProcess->check_version_compatibility(($current_version+1).'.0'), 'Fails when the major number is higher');
    ok(!Bio::EnsEMBL::Hive::GuestProcess->check_version_compatibility(($current_version-1).'.0'), 'Fails when the major number is lower');
    ok(!Bio::EnsEMBL::Hive::GuestProcess->check_version_compatibility("$current_version"), 'Fails if no minor number (even if the major number if the same');
};


subtest 'dummy language' => sub {
    # Remove existing custom wrappers
    delete local @ENV{grep {/^EHIVE_WRAPPER_/} keys %ENV};
    # And add ours
    local $ENV{'EHIVE_WRAPPER_DUMMY'} = $ENV{'EHIVE_ROOT_DIR'}.'/t/02.api/fake_bin/dummy_guest_language_wrapper';

    my %expected_wrappers = (
        'dummy'     => $ENV{'EHIVE_WRAPPER_DUMMY'},
        'python3'   => $ENV{'EHIVE_ROOT_DIR'}.'/wrappers/python3/wrapper',
    );

    subtest '_get_wrapper_for_language' => sub {
        foreach my $language (keys %expected_wrappers) {
            is(Bio::EnsEMBL::Hive::GuestProcess::_get_wrapper_for_language($language), $expected_wrappers{$language}, "Found the correct wrapper for $language");
        }

        throws_ok {
            local $ENV{'EHIVE_WRAPPER_DUMMY'} = $ENV{'EHIVE_ROOT_DIR'}.'/t/02.api/fake_bin/missing_wrapper';
            Bio::EnsEMBL::Hive::GuestProcess::_get_wrapper_for_language('dummy');
        } qr/The path '.*' doesn't exist/, 'Throws a relevant message if the path doesn\'t exist';

        throws_ok {
            local $ENV{'EHIVE_WRAPPER_DUMMY'} = $ENV{'EHIVE_ROOT_DIR'}.'/t/02.api/fake_bin/empty_wrapper';
            Bio::EnsEMBL::Hive::GuestProcess::_get_wrapper_for_language('dummy');
        } qr/The wrapper '.*' is an empty file/, 'Throws a relevant message if the file is empty';

        throws_ok {
            local $ENV{'EHIVE_WRAPPER_DUMMY'} = $ENV{'EHIVE_ROOT_DIR'}.'/t/02.api/fake_bin/non_executable_wrapper';
            Bio::EnsEMBL::Hive::GuestProcess::_get_wrapper_for_language('dummy');
        } qr/No permissions to execute the wrapper '.*'/, 'Throws a relevant message if the file is not executable';
    };

    subtest '_get_all_registered_wrappers' => sub {
        my $wrappers = Bio::EnsEMBL::Hive::GuestProcess::_get_all_registered_wrappers();
        is_deeply($wrappers, \%expected_wrappers, 'Found all the wrappers (under ensembl-hive/wrappers and defined in the environment)');
    };

    subtest 'get_wrapper_version' => sub {
        local $ENV{'EHIVE_EXPECTED_WRAPPER'} = 'version';
        my $version = Bio::EnsEMBL::Hive::GuestProcess::get_wrapper_version('dummy');
        is($version, 'OK', 'Query the version of the wrapper');
    };

    subtest 'build_wrapper_for_language' => sub {
        lives_ok( sub {
            local $ENV{'EHIVE_EXPECTED_WRAPPER'} = 'build';
            Bio::EnsEMBL::Hive::GuestProcess::build_wrapper_for_language('dummy');
        }, 'Request a build with the correct arguments');

        throws_ok {
            local $ENV{'EHIVE_EXPECTED_WRAPPER'} = 'wrong_build';
            Bio::EnsEMBL::Hive::GuestProcess::build_wrapper_for_language('dummy');
        } qr/The dummy wrapper cannot be built/, 'Throws a relevant message if the build fails';
    };

    subtest 'assert_runnable_exists' => sub {
        lives_ok( sub {
            local $ENV{'EHIVE_EXPECTED_WRAPPER'} = 'check_exists runner';
            Bio::EnsEMBL::Hive::GuestProcess::assert_runnable_exists('dummy', 'runner');
        }, 'Query the existence of a Runnable with the correct arguments');

        throws_ok {
            local $ENV{'EHIVE_EXPECTED_WRAPPER'} = 'wrong_check_exists runner';
            Bio::EnsEMBL::Hive::GuestProcess::assert_runnable_exists('dummy', 'runner');
        } qr/The runnable module 'runner' cannot be loaded or compiled/, 'Throws a relevant message if the runnable cannot be found';
    };

};

