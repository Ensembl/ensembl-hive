#!/usr/bin/env perl
# Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
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

use Test::More tests => 16;
use Test::Exception;

use Bio::EnsEMBL::Hive::Utils::Config;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Valley' );
}

# Need EHIVE_ROOT_DIR to access the default config file
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );
my @config_files = Bio::EnsEMBL::Hive::Utils::Config->default_config_files();
my $config = Bio::EnsEMBL::Hive::Utils::Config->new(@config_files);

# WARNING: the data in this script must be in sync with what the fake
# binaries output
$ENV{'PATH'} = $ENV{'EHIVE_ROOT_DIR'}.'/t/04.meadow/fake_bin:'.$ENV{'PATH'};

my $test_pipeline_name = 'tracking_homo_sapiens_funcgen_81_38_hive';
my $test_meadow_name = 'test_clUster';

my $valley = Bio::EnsEMBL::Hive::Valley->new($config, 'LSF', $test_pipeline_name);

my $lsf_meadow = $valley->available_meadow_hash->{'LSF'};
ok($lsf_meadow, 'Can build the meadow');

# Check that the meadow has been initialised correctly
is($lsf_meadow->name, $test_meadow_name, 'Found the LSF farm name');
is($lsf_meadow->pipeline_name, $test_pipeline_name, 'Getter/setter pipeline_name() works');

subtest 'get_current_worker_process_id()' => sub
{
    local $ENV{'LSB_JOBID'} = 34;
    local $ENV{'LSB_JOBINDEX'} = 56;
    is($lsf_meadow->get_current_worker_process_id(), '34[56]', 'Job array with index');
    local $ENV{'LSB_JOBINDEX'} = 0;
    is($lsf_meadow->get_current_worker_process_id(), '34', 'Job array without index');
    local $ENV{'LSB_JOBID'} = undef;
    throws_ok {$lsf_meadow->get_current_worker_process_id()} qr/Could not establish the process_id/, 'Not a LSF job';
};

is_deeply(
    [$lsf_meadow->count_pending_workers_by_rc_name],
    [ { 'normal_30GB_2cpu' => 2, 'normal_10gb' => 7 }, 9 ],
    'count_pending_workers_by_rc_name()',
);

is($lsf_meadow->count_running_workers, 25, 'count_running_workers()');

is_deeply(
    $lsf_meadow->status_of_all_our_workers,
    {
        '2068349[1]' => 'RUN',
        '2067769[11]' => 'RUN',
        '2067765[4]' => 'RUN',
        '2067754[31]' => 'RUN',
        '2068245' => 'RUN',
        '2067754[27]' => 'RUN',
        '2067769[2]' => 'RUN',
        '2068349[2]' => 'RUN',
        '2067769[14]' => 'RUN',
        '2067754[32]' => 'RUN',
        '2067754[34]' => 'RUN',
        '2067754[7]' => 'RUN',
        '2067769[10]' => 'RUN',
        '2067769[3]' => 'PEND',
        '2067769[9]' => 'RUN',
        '2067769[17]' => 'PEND',
        '2067754[14]' => 'RUN',
        '2067769[4]' => 'PEND',
        '2067769[6]' => 'PEND',
        '2068410' => 'PEND',
        '2067769[19]' => 'PEND',
        '2067769[18]' => 'PEND',
        '2067754[30]' => 'RUN',
        '2067769[12]' => 'RUN',
        '2067754[26]' => 'RUN',
        '2067765[13]' => 'RUN',
        '2068463' => 'PEND',
        '2067769[13]' => 'RUN',
        '2067769[15]' => 'RUN',
        '2067769[16]' => 'RUN',
        '2067769[8]' => 'RUN',
        '2067754[28]' => 'RUN',
        '2067754[33]' => 'RUN',
        '2067769[5]' => 'PEND'
    },
    'status_of_all_our_workers()',
);

use Bio::EnsEMBL::Hive::Worker;
my $worker = Bio::EnsEMBL::Hive::Worker->new();

{
    $worker->meadow_type('LSF');
    $worker->meadow_name('imaginary_meadow');
    is($valley->find_available_meadow_responsible_for_worker($worker), undef, 'find_available_meadow_responsible_for_worker() with a worker from another meadow');
    $worker->meadow_name($test_meadow_name);
    is($valley->find_available_meadow_responsible_for_worker($worker), $lsf_meadow, 'find_available_meadow_responsible_for_worker() with a worker from that meadow');
}

{
    local $ENV{USER} = 'mm14';
    $worker->process_id('2068245');
    ok($lsf_meadow->check_worker_is_alive_and_mine($worker), 'An existing process that belongs to me');
    $worker->process_id('2068349');
    ok(!$lsf_meadow->check_worker_is_alive_and_mine($worker), 'An existing process that belongs to il4');
    $worker->process_id('123456789');
    ok(!$lsf_meadow->check_worker_is_alive_and_mine($worker), 'A missing process');
}

lives_ok( sub {
    local $ENV{EHIVE_EXPECTED_BSUB} = '-o /dev/null -e /dev/null -J tracking_homo_sapiens_funcgen_81_38_hive-Hive-/resource_class/-56 /rc_args/ /worker_cmd/';
    $lsf_meadow->submit_workers('/worker_cmd/', 1, 56, '/resource_class/', '/rc_args/');
}, 'Can submit 1 worker');

lives_ok( sub {
    local $ENV{EHIVE_EXPECTED_BSUB} = '-o /dev/null -e /dev/null -J tracking_homo_sapiens_funcgen_81_38_hive-Hive-/resource_class/-56[1-4] /rc_args/ /worker_cmd/';
    $lsf_meadow->submit_workers('/worker_cmd/', 4, 56, '/resource_class/', '/rc_args/');
}, 'Can submit 4 workers');

lives_ok( sub {
    local $ENV{EHIVE_EXPECTED_BSUB} = '-o /submit_log_dir/ -e /dev/null -J tracking_homo_sapiens_funcgen_81_38_hive-Hive-/resource_class/-56 /rc_args/ /worker_cmd/';
    $lsf_meadow->submit_workers('/worker_cmd/', 1, 56, '/resource_class/', '/rc_args/', '/submit_log_dir/');
}, 'Can submit 1 worker with a submit_log_dir');

done_testing();

