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

#use Test::More tests => 25;
use Test::More;
use Test::Exception;

use Bio::EnsEMBL::Hive::Utils::Config;

BEGIN {
    use_ok ('Bio::EnsEMBL::Hive::Valley');
    use_ok ('Bio::EnsEMBL::Hive::Meadow::SLURM');
}

# Currently, this assumes you're on a system with a working Slurm installation,
# you have no processes running and you can submit jobs

# Need EHIVE_ROOT_DIR to access the default config file
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );
my $config = Bio::EnsEMBL::Hive::Utils::Config->new();


throws_ok {
    local $ENV{'PATH'} = $ENV{'EHIVE_ROOT_DIR'}.'/t/04.meadow/deceptive_bin:'.$ENV{'PATH'};
    my $valley = Bio::EnsEMBL::Hive::Valley->new($config, 'SLURM');
} qr/Meadow 'SLURM' does not seem to be available on this machine, please investigate at/, 'No SLURM meadow if "sinfo" is not present (or does not behave well)';

my $test_meadow_name = 'slurm';
my $test_pipeline_name = 'slurm_pipeline_name';
my $valley = Bio::EnsEMBL::Hive::Valley->new($config, 'SLURM', $test_pipeline_name);

isa_ok ($valley->available_meadow_hash->{'SLURM'}, 'Bio::EnsEMBL::Hive::Meadow::SLURM', 'Slurm meadow object');
my $meadow = $valley->available_meadow_hash->{'SLURM'};

# Check that the meadow has been initialised correctly
is ($meadow->name, $test_meadow_name, 'Found the SLURM farm name');
is ($meadow->pipeline_name, $test_pipeline_name, 'Getter/setter pipeline_name() works');

throws_ok {$meadow->get_current_worker_process_id()} qr/Could not establish the process_id/, 'Check if get_current_worker_process_id throws if there is no process';

is_deeply($meadow->status_of_all_our_workers, [], 'Check if we have no workers running');
my $id = sbatch();
#use Data::Dumper;
#$Data::Dumper::Sortkeys = 1;
#print Dumper($meadow->status_of_all_our_workers);

my $list = $meadow->status_of_all_our_workers;
is (ref($list), 'ARRAY', 'Checking for workers returns an array');

my $found = 0;
foreach my $item (@$list) {
    my ($pid, $username, $status) = @$item;
    if ($id == $pid and $username eq $ENV{USER} and $status eq 'PENDING' or $status eq 'RUNNING') {
        $found = 1;
        last;
    }
}
is ($found, 1, 'Check if we can find our slurm processes');

sub sbatch {
    my $sbid = `sbatch --mem 10M -t 01:00 --wrap 'sh -c "sleep 50"' --parsable`;
    chomp $sbid;
    return $sbid;
}
sub scancel {
    my $pid = shift;
    `scancel $pid`;
}

use Bio::EnsEMBL::Hive::Worker;
my $worker = Bio::EnsEMBL::Hive::Worker->new();
{
    $worker->meadow_type('SLURM');
    $worker->meadow_name('imaginary_meadow');
    is($valley->find_available_meadow_responsible_for_worker($worker), undef, 'find_available_meadow_responsible_for_worker() with a worker from another meadow');
    $worker->meadow_name($test_meadow_name);
    is($valley->find_available_meadow_responsible_for_worker($worker), $meadow, 'find_available_meadow_responsible_for_worker() with a worker from that meadow');
}

{
    $worker->process_id($id);
    ok($meadow->check_worker_is_alive_and_mine($worker), 'An existing process that belongs to me');
    $worker->process_id('123456789');
    ok(!$meadow->check_worker_is_alive_and_mine($worker), 'A missing process');
}

scancel($id);

my $submitted_pids;
lives_ok( sub {
    $submitted_pids = $meadow->submit_workers_return_meadow_pids('sh -c "sleep 5"', 1, 1, 'rc_name', '--mem 10M -t 01:00');
}, 'Can submit something');

my $cmp_pid = `squeue --noheader -o '%i' --name slurm_pipeline_name-Hive-rc_name-1`;
chomp($cmp_pid);

is_deeply($submitted_pids, [$cmp_pid], 'Returned the correct pid');

#lives_ok( sub {
#    local $ENV{EHIVE_EXPECTED_BSUB} = '-o /dev/null -e /dev/null -J tracking_homo_sapiens_funcgen_81_38_hive-Hive-/resource_class/-56[1-4] /rc_args/ /worker_cmd/';
#    $submitted_pids = $meadow->submit_workers_return_meadow_pids('/worker_cmd/', 4, 56, '/resource_class/', '/rc_args/');
#}, 'Can submit something');
#is_deeply($submitted_pids, ['12345[1]', '12345[2]', '12345[3]', '12345[4]'], 'Returned the correct pids');
#
#lives_ok( sub {
#    local $ENV{EHIVE_EXPECTED_BSUB} = '-o /submit_log_dir//log_/resource_class/_%J_%I.out -e /submit_log_dir//log_/resource_class/_%J_%I.err -J tracking_homo_sapiens_funcgen_81_38_hive-Hive-/resource_class/-56 /rc_args/ /worker_cmd/';
#    $submitted_pids = $meadow->submit_workers_return_meadow_pids('/worker_cmd/', 1, 56, '/resource_class/', '/rc_args/', '/submit_log_dir/');
#}, 'Can submit something with a submit_log_dir');
#is_deeply($submitted_pids, [12345], 'Returned the correct pid');
#
#my $expected_sacct = {
#    '2581807[1]' => {
#        'when_died' => '2020-11-26 14:25:12',
#        'pending_sec' => '147',
#        'exception_status' => 'underrun',
#        'cause_of_death' => undef,
#        'lifespan_sec' => '150',
#        'mem_megs' => 28,
#        'cpu_sec' => '2.74',
#        'exit_status' => 'done',
#        'swap_megs' => 144,
#        'when_born' => '2020-11-26 14:25:09',
#        'meadow_host' => 'bc-25-1-10',
#    },
#    '2581801[48]' => {
#        'when_died' => '2020-11-26 14:25:16',
#        'pending_sec' => '196',
#        'exception_status' => 'underrun',
#        'mem_megs' => 50,
#        'lifespan_sec' => '215',
#        'cause_of_death' => undef,
#        'cpu_sec' => '2.61',
#        'exit_status' => 'done',
#        'swap_megs' => 269,
#        'when_born' => '2020-11-26 14:24:57',
#        'meadow_host' => 'bc-27-2-07',
#    },
#    '3194397[75]' => {
#        'cpu_sec' => '6.97',
#        'lifespan_sec' => '57',
#        'pending_sec' => '2',
#        'exception_status' => 'underrun',
#        'swap_megs' => 218,
#        'when_died' => '2020-12-02 13:53:29',
#        'cause_of_death' => 'MEMLIMIT',
#        'exit_status' => 'exit/TERM_MEMLIMIT',
#        'mem_megs' => 102,
#        'when_born' => '2020-12-02 13:52:34',
#        'meadow_host' => 'bc-31-2-11',
#    },
#};
#
#$meadow->config_set("AccountingDisabled", 0);
#my $sacct_opts = $meadow->config_get('sacctExtraOptions') || "";
#lives_and( sub {
#    local $ENV{EHIVE_EXPECTED_sacct} = $sacct_opts.'-l 34 56[7]';
#    my $h = $meadow->get_report_entries_for_process_ids(34, '56[7]');
#    is_deeply($h, $expected_sacct, 'Got sacct output');
#}, 'Can call sacct on process_ids');
#
#lives_and( sub {
#    local $ENV{EHIVE_EXPECTED_sacct} = $sacct_opts.'-l -C 2020/10/11/12:23,2020/12/12/23:58 -u kb3';
#    my $h = $meadow->get_report_entries_for_time_interval('2020-10-11 12:23:45', '2020-12-12 23:56:59', 'kb3');
#    is_deeply($h, $expected_sacct, 'Got sacct output');
#}, 'Can call sacct on a date range');
#
#
#$meadow->config_set("AccountingDisabled", 1);
#lives_and( sub {
#    local $ENV{EHIVE_EXPECTED_sacct} = $sacct_opts.'-l 34 56[7]';
#    my $h = $meadow->get_report_entries_for_process_ids(34, '56[7]');
#    is_deeply($h, {}, 'No sacct output when accounting disabled');
#}, 'Suppressed sacct when AccountingDisabled when checking process_ids');
#
#lives_and( sub {
#    local $ENV{EHIVE_EXPECTED_sacct} = $sacct_opts.'-l -C 2015/10/11/12:23,2015/12/12/23:58 -u kb3';
#    my $h = $meadow->get_report_entries_for_time_interval('2015-10-11 12:23:45', '2015-12-12 23:56:59', 'kb3');
#    is_deeply($h, {}, 'No sacct output when accounting disabled');
#}, 'Suppressed sacct when AccountingDisabled when checking a date range');
#
#} # end local $ENV{'PATH'}
#
#subtest "Cluster detection", sub {
#    my $SLURM_detection_root_dir = $ENV{'EHIVE_ROOT_DIR'}.'/t/04.meadow/SLURM_detection';
#    opendir( my $dir_fh, $SLURM_detection_root_dir) || die "Can't opendir $SLURM_detection_root_dir: $!";
#    foreach my $subdir ( readdir($dir_fh) ) {
#        next unless -d "$SLURM_detection_root_dir/$subdir";
#        local $ENV{'PATH'} = "$SLURM_detection_root_dir/$subdir:$ini_path";
#        if ($subdir =~ /^ok_(.*)$/) {
#            my $detected_name = Bio::EnsEMBL::Hive::Meadow::SLURM::name();
#            ok($detected_name, "Detects $subdir");
#            is($detected_name, $1, "Correct cluster name");
#        } elsif ($subdir =~ /^no/) {
#            my $detected_name = Bio::EnsEMBL::Hive::Meadow::SLURM::name();
#            ok(!$detected_name, "Does not detect $subdir");
#        }
#    }
#    closedir($dir_fh);
#};

done_testing();

