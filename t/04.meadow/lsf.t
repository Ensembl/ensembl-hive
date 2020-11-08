#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2020] EMBL-European Bioinformatics Institute
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

use Test::More tests => 22;
use Test::Exception;

use Bio::EnsEMBL::Hive::Utils::Config;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Valley' );
}

# Need EHIVE_ROOT_DIR to access the default config file
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );
my @config_files = Bio::EnsEMBL::Hive::Utils::Config->default_config_files();
my $config = Bio::EnsEMBL::Hive::Utils::Config->new(@config_files);

my $ini_path = $ENV{'PATH'};

# WARNING: the data in this script must be in sync with what the fake
# binaries output
{ # begin local $ENV{'PATH'}
$ENV{'PATH'} = $ENV{'EHIVE_ROOT_DIR'}.'/t/04.meadow/fake_bin:'.$ini_path;

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

is($lsf_meadow->count_running_workers, 26, 'count_running_workers()');
is($lsf_meadow->count_running_workers(['il4']), 24, 'count_running_workers("il4")');

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
        '2067769[5]' => 'PEND',
        '276335[13]' => 'RUN',
    },
    'status_of_all_our_workers()',
);

is_deeply(
    $lsf_meadow->status_of_all_our_workers(["mm14"]),
    { '2068245' => 'RUN', '2068463' => 'PEND' },
    'status_of_all_our_workers("mm14")',
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
    local $ENV{EHIVE_EXPECTED_BSUB} = '-o /submit_log_dir//log_/resource_class/_%J_%I.out -e /submit_log_dir//log_/resource_class/_%J_%I.err -J tracking_homo_sapiens_funcgen_81_38_hive-Hive-/resource_class/-56 /rc_args/ /worker_cmd/';
    $lsf_meadow->submit_workers('/worker_cmd/', 1, 56, '/resource_class/', '/rc_args/', '/submit_log_dir/');
}, 'Can submit 1 worker with a submit_log_dir');

my $expected_bacct = {
    '2581807[1]' => {
        'when_died' => '2020-11-26 14:25:12',
        'pending_sec' => '147',
        'exception_status' => 'underrun',
        'cause_of_death' => undef,
        'lifespan_sec' => '150',
        'mem_megs' => 28,
        'cpu_sec' => '2.74',
        'exit_status' => 'done',
        'swap_megs' => 144
    },
    '2581801[48]' => {
        'when_died' => '2020-11-26 14:25:16',
        'pending_sec' => '196',
        'exception_status' => 'underrun',
        'mem_megs' => 50,
        'lifespan_sec' => '215',
        'cause_of_death' => undef,
        'cpu_sec' => '2.61',
        'exit_status' => 'done',
        'swap_megs' => 269
    },
    '3194397[75]' => {
        'cpu_sec' => '6.97',
        'lifespan_sec' => '57',
        'pending_sec' => '2',
        'exception_status' => 'underrun',
        'swap_megs' => 218,
        'when_died' => '2020-12-02 13:53:29',
        'cause_of_death' => 'MEMLIMIT',
        'exit_status' => 'exit/TERM_MEMLIMIT',
        'mem_megs' => 102
    },
};

$lsf_meadow->config_set("AccountingDisabled", 0);
lives_and( sub {
    local $ENV{EHIVE_EXPECTED_BACCT} = '-l 34 56[7]';
    my $h = $lsf_meadow->get_report_entries_for_process_ids(34, '56[7]');
    is_deeply($h, $expected_bacct, 'Got bacct output');
}, 'Can call bacct on process_ids');

lives_and( sub {
    local $ENV{EHIVE_EXPECTED_BACCT} = '-l -C 2020/10/11/12:23,2020/12/12/23:58 -u kb3';
    my $h = $lsf_meadow->get_report_entries_for_time_interval('2020-10-11 12:23:45', '2020-12-12 23:56:59', 'kb3');
    is_deeply($h, $expected_bacct, 'Got bacct output');
}, 'Can call bacct on a date range');


$lsf_meadow->config_set("AccountingDisabled", 1);
lives_and( sub {
    local $ENV{EHIVE_EXPECTED_BACCT} = '-l 34 56[7]';
    my $h = $lsf_meadow->get_report_entries_for_process_ids(34, '56[7]');
    is_deeply($h, {}, 'No bacct output when accounting disabled');
}, 'Suppressed bacct when AccountingDisabled when checking process_ids');

lives_and( sub {
    local $ENV{EHIVE_EXPECTED_BACCT} = '-l -C 2015/10/11/12:23,2015/12/12/23:58 -u kb3';
    my $h = $lsf_meadow->get_report_entries_for_time_interval('2015-10-11 12:23:45', '2015-12-12 23:56:59', 'kb3');
    is_deeply($h, {}, 'No bacct output when accounting disabled');
}, 'Suppressed bacct when AccountingDisabled when checking a date range');

} # end local $ENV{'PATH'}

done_testing();

