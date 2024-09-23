#!/usr/bin/env perl
# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
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
use File::Temp 'tempdir';

#use Test::More tests => 53;
use Test::More;
use Test::Exception;
use Time::Piece;
use Time::Seconds;

use Bio::EnsEMBL::Hive::Utils::Config;
use Bio::EnsEMBL::Hive::Worker;

# I believe it makes no sense to test this with mock executables
if ( not $ENV{TEST_AUTHOR} ) {
    my $msg = 'Author test. Set $ENV{TEST_AUTHOR} to a true value to run.';
    plan( skip_all => $msg );
}

BEGIN {
    use_ok ('Bio::EnsEMBL::Hive::Valley');
    use_ok ('Bio::EnsEMBL::Hive::Meadow::SLURM');
}


# Currently, this assumes you're on a system with a working Slurm installation,
# you have no processes running and you can submit jobs.
# One subtest will create a temp dir in your home for log files. Assumes that
# submitted jobs can write there and that it is a networked file system.
# The test tries to clean up after itself

sub sbatch {
    my $sbid = `sbatch --mem 10M -t 01:00 --wrap 'sh -c "sleep 50"' --parsable`;
    chomp $sbid;
    return $sbid;
}
sub scancel {
    my $pid = shift;
    `scancel $pid`;
}


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

my $worker_cmd = 'sh -c "sleep 5"';
my $rc_class = 'rc_name';
my $slurm_opts = '--mem 10M -t 01:00';

my $submitted_pids;
lives_ok( sub {
    $submitted_pids = $meadow->submit_workers_return_meadow_pids($worker_cmd, 1, 1, $rc_class, $slurm_opts);
}, 'Can submit something');

my $cmp_pid = `squeue --noheader -o '%i' --name slurm_pipeline_name-Hive-rc_name-1`;
chomp($cmp_pid);
is_deeply($submitted_pids, [$cmp_pid], 'Returned the correct pid');
scancel($cmp_pid);

lives_ok( sub {
    $submitted_pids = $meadow->submit_workers_return_meadow_pids($worker_cmd, 4, 50, $rc_class, $slurm_opts);
}, 'Can submit array');
my $cmp_pids = [split /\n/, `squeue --array --noheader -o '%i' --name slurm_pipeline_name-Hive-rc_name-50`];
is_deeply($submitted_pids, $cmp_pids, 'Returned the correct pids');

for my $id (@$cmp_pids) {
    scancel($id);
}

my $dir = tempdir(CLEANUP => 1, DIR => "$ENV{HOME}");
$worker_cmd = q{perl -E 'say "SLURM test"; say STDERR "SLURM test";'};

lives_ok( sub {
    $submitted_pids = $meadow->submit_workers_return_meadow_pids($worker_cmd, 2, 51, $rc_class, $slurm_opts, $dir);
}, 'Can submit array with log');
$cmp_pids = [split /\n/, `squeue --array --noheader -o '%i' --name slurm_pipeline_name-Hive-rc_name-51`];
is_deeply($submitted_pids, $cmp_pids, 'Returned the correct pids');

my @files;
my $maxwait = 20;
for (1 .. $maxwait) {
    my $content = `ls -1 $dir`;
    @files = split /\n/, $content;
    last if @files == 4;
    sleep 1;
}
die "Waited $maxwait secs for four log files to appear in $dir but they did not (all) show up" unless @files == 4;

for my $id (@$cmp_pids) {
    scancel($id);
}

for my $id (@$cmp_pids) {
    for my $ext ("out", "err") {
        my $name = "log_rc_name_$id.$ext";
        ok((grep { $_ eq $name } @files), 'Log file is present');
    }
}

my @lines;
for (1 .. $maxwait) {
    my $pidstr = join ",", @$cmp_pids;
    my $content = `sacct -X -j $pidstr -o jobid -n`;
    @lines = split /\n/, $content;
    last if @lines == 2;
    sleep 1;
}
die "Waited $maxwait secs for sacct info, but was not found" unless @lines == 2;

$meadow->config_set("AccountingDisabled", 0);


#{ '54769534_1' => {
#    'cause_of_death' => 'UNKNOWN',
#    'cpu_sec' => '0',
#    'exception_status' => 'UNKNOWN',
#    'exit_status' => '0:0',
#    'lifespan_sec' => '0',
#    'mem_megs' => '0',
#    'pending_sec' => 0,
#    'swap_megs' => '0',
#    'when_died' => '2024-02-16 15:10:48'
#  }, ...
#}
sub compare_sacct {
    my ($h, $cmp_pids) = @_;
    for my $id (@$cmp_pids) {
        ok(exists $h->{$id}, 'id exists');
        my $data = $h->{$id};
        for my $key ('cpu_sec', 'lifespan_sec', 'mem_megs', 'pending_sec',
            'swap_megs', 'when_died', 'cause_of_death', 'exception_status',
            'exit_status'
        ){
            ok(exists $data->{$key}, "key $key exists");
        }
        ok($data->{'when_died'} =~ /\d{4}-\d{2}-\d{2}/, 'when_died info OK');
        ok($data->{'cause_of_death'} eq 'UNKNOWN', 'cause_of_death info OK');
        ok($data->{'exception_status'} eq 'UNKNOWN', 'exception_status info OK');
        ok($data->{'exit_status'} =~ /0:\d/, 'exit_status info OK');
    }
    return 1;
}

lives_and( sub {
    my $h = $meadow->get_report_entries_for_process_ids(@$cmp_pids);
    ok(compare_sacct($h, $cmp_pids), 'sacct output OK');
}, 'Can call sacct on process_ids');


my $t = localtime;
my $to_time = $t->strftime('%Y-%m-%d %H:%M:%S');
$t -= ONE_DAY;
my $from_time = $t->strftime('%Y-%m-%d %H:%M:%S');

lives_and( sub {
    my $h = $meadow->get_report_entries_for_time_interval($from_time, $to_time, $ENV{USER});
    ok(compare_sacct($h, $cmp_pids), 'Got sacct output');
}, 'Can call sacct on a date range');

 
# TODO: do these make sense here? This is not influenced by the meadow, afaics
# $meadow->config_set("AccountingDisabled", 1);
# lives_and( sub {
#     my $h = $meadow->get_report_entries_for_process_ids(@$cmp_pids);
#     is_deeply($h, {}, 'No sacct output when accounting disabled');
# }, 'Suppressed sacct when AccountingDisabled when checking process_ids');
# 
# 
# lives_and( sub {
#     my $h = $meadow->get_report_entries_for_time_interval($from_time, $to_time, $ENV{USER});
#     is_deeply($h, {}, 'No sacct output when accounting disabled');
# }, 'Suppressed sacct when AccountingDisabled when checking a date range');
#
# TODO: should be tested:
# Worker cancellation
# Timeouts
# Cause of death
#
# Should be tested in another test:
# retry count


done_testing();

