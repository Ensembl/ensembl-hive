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

use Test::More tests => 25;
use Test::Exception;

use Bio::EnsEMBL::Hive::Utils::Config;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Valley' );
    use_ok( 'Bio::EnsEMBL::Hive::Meadow::LSF' );
}

# Need EHIVE_ROOT_DIR to access the default config file
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );
my $config = Bio::EnsEMBL::Hive::Utils::Config->new();

throws_ok {
    local $ENV{'PATH'} = $ENV{'EHIVE_ROOT_DIR'}.'/t/04.meadow/deceptive_bin:'.$ENV{'PATH'};
    my $valley = Bio::EnsEMBL::Hive::Valley->new($config, 'LSF');
} qr/Meadow 'LSF' does not seem to be available on this machine, please investigate at/, 'No LSF meadow if "lsid" is not present (or does not behave well';

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
    $lsf_meadow->status_of_all_our_workers,
    [
        [ '6388676', 'jt8', 'RUN' ],
        [ '1997948', 'tc9', 'RUN' ],
        [ '2067769[9]', 'il4', 'RUN' ],
        [ '2067769[10]', 'il4', 'RUN' ],
        [ '2067769[11]', 'il4', 'RUN' ],
        [ '2067769[12]', 'il4', 'RUN' ],
        [ '2067769[13]', 'il4', 'RUN' ],
        [ '2037301', 'il4', 'RUN' ],
        [ '2067769[8]', 'il4', 'RUN' ],
        [ '2067754[26]', 'il4', 'RUN' ],
        [ '2067754[27]', 'il4', 'RUN' ],
        [ '2067754[28]', 'il4', 'RUN' ],
        [ '2067754[30]', 'il4', 'RUN' ],
        [ '2067754[31]', 'il4', 'RUN' ],
        [ '2067754[32]', 'il4', 'RUN' ],
        [ '2067754[33]', 'il4', 'RUN' ],
        [ '2067754[34]', 'il4', 'RUN' ],
        [ '2067765[4]', 'il4', 'RUN' ],
        [ '2067765[13]', 'il4', 'RUN' ],
        [ '2068245', 'mm14', 'RUN' ],
        [ '2068410', 'il4', 'PEND' ],
        [ '2067769[14]', 'il4', 'RUN' ],
        [ '2067769[15]', 'il4', 'RUN' ],
        [ '2068463', 'mm14', 'PEND' ],
        [ '2067754[14]', 'il4', 'RUN' ],
        [ '2068349[2]', 'il4', 'RUN' ],
        [ '2067769[16]', 'il4', 'RUN' ],
        [ '2067769[17]', 'il4', 'PEND' ],
        [ '2067769[18]', 'il4', 'PEND' ],
        [ '2067769[19]', 'il4', 'PEND' ],
        [ '2067769[6]', 'il4', 'PEND' ],
        [ '2067769[3]', 'il4', 'PEND' ],
        [ '2067769[4]', 'il4', 'PEND' ],
        [ '2067769[5]', 'il4', 'PEND' ],
        [ '2068349[1]', 'il4', 'RUN' ],
        [ '2067754[7]', 'il4', 'RUN' ],
        [ '2067769[2]', 'il4', 'RUN' ],
        [ '276335[13]', 'tmpseq', 'RUN' ]
    ],
    'status_of_all_our_workers()',
);

is_deeply(
    $lsf_meadow->status_of_all_our_workers(["mm14"]),
    [
        [ '2068245', 'mm14', 'RUN' ],
        [ '2068463', 'mm14', 'PEND' ]
    ],
    'status_of_all_our_workers(["mm14"])',
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

my $submitted_pids;
lives_ok( sub {
    local $ENV{EHIVE_EXPECTED_BSUB} = '-o /dev/null -e /dev/null -J tracking_homo_sapiens_funcgen_81_38_hive-Hive-/resource_class/-56 /rc_args/ /worker_cmd/';
    $submitted_pids = $lsf_meadow->submit_workers_return_meadow_pids('/worker_cmd/', 1, 56, '/resource_class/', '/rc_args/');
}, 'Can submit something');
is_deeply($submitted_pids, [12345], 'Returned the correct pid');

lives_ok( sub {
    local $ENV{EHIVE_EXPECTED_BSUB} = '-o /dev/null -e /dev/null -J tracking_homo_sapiens_funcgen_81_38_hive-Hive-/resource_class/-56[1-4] /rc_args/ /worker_cmd/';
    $submitted_pids = $lsf_meadow->submit_workers_return_meadow_pids('/worker_cmd/', 4, 56, '/resource_class/', '/rc_args/');
}, 'Can submit something');
is_deeply($submitted_pids, ['12345[1]', '12345[2]', '12345[3]', '12345[4]'], 'Returned the correct pids');

lives_ok( sub {
    local $ENV{EHIVE_EXPECTED_BSUB} = '-o /submit_log_dir//log_/resource_class/_%J_%I.out -e /submit_log_dir//log_/resource_class/_%J_%I.err -J tracking_homo_sapiens_funcgen_81_38_hive-Hive-/resource_class/-56 /rc_args/ /worker_cmd/';
    $submitted_pids = $lsf_meadow->submit_workers_return_meadow_pids('/worker_cmd/', 1, 56, '/resource_class/', '/rc_args/', '/submit_log_dir/');
}, 'Can submit something with a submit_log_dir');
is_deeply($submitted_pids, [12345], 'Returned the correct pid');

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
        'swap_megs' => 144,
        'when_born' => '2020-11-26 14:25:09',
        'meadow_host' => 'bc-25-1-10',
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
        'swap_megs' => 269,
        'when_born' => '2020-11-26 14:24:57',
        'meadow_host' => 'bc-27-2-07',
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
        'mem_megs' => 102,
        'when_born' => '2020-12-02 13:52:34',
        'meadow_host' => 'bc-31-2-11',
    },
};

$lsf_meadow->config_set("AccountingDisabled", 0);
my $bacct_opts = $lsf_meadow->config_get('BacctExtraOptions') || "";
lives_and( sub {
    local $ENV{EHIVE_EXPECTED_BACCT} = $bacct_opts.'-l 34 56[7]';
    my $h = $lsf_meadow->get_report_entries_for_process_ids(34, '56[7]');
    is_deeply($h, $expected_bacct, 'Got bacct output');
}, 'Can call bacct on process_ids');

lives_and( sub {
    local $ENV{EHIVE_EXPECTED_BACCT} = $bacct_opts.'-l -C 2020/10/11/12:23,2020/12/12/23:58 -u kb3';
    my $h = $lsf_meadow->get_report_entries_for_time_interval('2020-10-11 12:23:45', '2020-12-12 23:56:59', 'kb3');
    is_deeply($h, $expected_bacct, 'Got bacct output');
}, 'Can call bacct on a date range');


$lsf_meadow->config_set("AccountingDisabled", 1);
lives_and( sub {
    local $ENV{EHIVE_EXPECTED_BACCT} = $bacct_opts.'-l 34 56[7]';
    my $h = $lsf_meadow->get_report_entries_for_process_ids(34, '56[7]');
    is_deeply($h, {}, 'No bacct output when accounting disabled');
}, 'Suppressed bacct when AccountingDisabled when checking process_ids');

lives_and( sub {
    local $ENV{EHIVE_EXPECTED_BACCT} = $bacct_opts.'-l -C 2015/10/11/12:23,2015/12/12/23:58 -u kb3';
    my $h = $lsf_meadow->get_report_entries_for_time_interval('2015-10-11 12:23:45', '2015-12-12 23:56:59', 'kb3');
    is_deeply($h, {}, 'No bacct output when accounting disabled');
}, 'Suppressed bacct when AccountingDisabled when checking a date range');

} # end local $ENV{'PATH'}

subtest "Cluster detection", sub {
    my $lsf_detection_root_dir = $ENV{'EHIVE_ROOT_DIR'}.'/t/04.meadow/lsf_detection';
    opendir( my $dir_fh, $lsf_detection_root_dir) || die "Can't opendir $lsf_detection_root_dir: $!";
    foreach my $subdir ( readdir($dir_fh) ) {
        next unless -d "$lsf_detection_root_dir/$subdir";
        local $ENV{'PATH'} = "$lsf_detection_root_dir/$subdir:$ini_path";
        if ($subdir =~ /^ok_(.*)$/) {
            my $detected_name = Bio::EnsEMBL::Hive::Meadow::LSF::name();
            ok($detected_name, "Detects $subdir");
            is($detected_name, $1, "Correct cluster name");
        } elsif ($subdir =~ /^no/) {
            my $detected_name = Bio::EnsEMBL::Hive::Meadow::LSF::name();
            ok(!$detected_name, "Does not detect $subdir");
        }
    }
    closedir($dir_fh);
};

done_testing();

