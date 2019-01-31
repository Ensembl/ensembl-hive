#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2022] EMBL-European Bioinformatics Institute
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

use Data::Dumper;

use Test::More;
use Test::Exception;

use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker beekeeper run_sql_on_db get_test_urls);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $ehive_test_pipeline_urls = get_test_urls();


    # a helper injection that may be promoted in future:
sub Bio::EnsEMBL::Hive::AnalysisJob::semaphore_count {
    my $job = shift @_;

    my $semaphore = $job->fetch_local_blocking_semaphore();

    return $semaphore ? ( $semaphore->local_jobs_counter + $semaphore->remote_jobs_counter ) : 0;
}


sub assert_jobs {
    my ($job_adaptor, $job_expected_data) = @_;
    my $all_jobs = $job_adaptor->fetch_all();

    my @job_data = map { [$_->status, $_->retry_count, $_->semaphore_count ] } sort {$a->dbID<=> $b->dbID} @$all_jobs;

    is_deeply(\@job_data, $job_expected_data, 'Job counts and statuses are correct');
}

sub fetch_job_completion_date {
    my ($job_adaptor, $job_id) = @_;
    my $job = $job_adaptor->fetch_by_dbID($job_id);
    ok($job, "Job dbID=$job_id could be fetched");
    return $job->when_completed;
}

foreach my $pipeline_url (@$ehive_test_pipeline_urls) {

  subtest 'Test on '.$pipeline_url, sub {

    init_pipeline('Bio::EnsEMBL::Hive::Examples::FailureTest::PipeConfig::FailureTest_conf', $pipeline_url,
                            [-job_count => 5, -failure_rate => 2],
                            ['analysis[failure_test].max_retry_count=1']
    );
    my $hive_dba    = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );
    my $hive_url    = $hive_dba->dbc->url;
    my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;

    # First run some jobs. job_id 3 is attempted twice to go over
    # max_retry_count and switch to FAILED
    foreach my $job_id (1,3,4,5,6,7,3) {
        runWorker($pipeline_url, [ '-job_id' => $job_id ]);
    }

    # We're now in a state with a selection of DONE, READY, FAILED and SEMAPHORED jobs

    # Tip: SELECT CONCAT('[', GROUP_CONCAT( CONCAT('["',status,'",', retry_count, ',',COALESCE(local_jobs_counter+remote_jobs_counter,0),']') ), ']') FROM job j LEFT JOIN semaphore s ON (j.job_id=s.dependent_job_id) ORDER BY job_id;
    assert_jobs($job_adaptor, [["DONE",0,0],["SEMAPHORED",0,3],["FAILED",2,0],["DONE",0,0],["READY",1,0],["DONE",0,0],["READY",1,0]] );

    # Reset a job with specific input_id and analysis_pattern
    beekeeper($hive_url, ['-reset_job_for_input_id', '{%', '-analyses_pattern', 2], 'beekeeper.pl -reset_job_for_input_id -analyses_pattern');
    assert_jobs($job_adaptor, [["SEMAPHORED",0,3],["DONE",0,0],["READY",1,0],["READY",1,0],["READY",1,0],["READY",1,0],["READY",2,0]] );

    # Reset DONE jobs on the fan
    beekeeper($hive_url, ['-reset_done_jobs', '-analyses_pattern', 'failure_test'], 'beekeeper.pl -reset_done_jobs');
    assert_jobs($job_adaptor, [["DONE",0,0],["SEMAPHORED",0,5],["FAILED",2,0],["READY",1,0],["READY",1,0],["READY",1,0],["READY",1,0]] );

    # Forgive FAILED jobs
    beekeeper($hive_url, ['-forgive_failed_jobs'], 'beekeeper.pl -forgive_failed_jobs');
    assert_jobs($job_adaptor, [["DONE",0,0],["SEMAPHORED",0,4],["DONE",2,0],["READY",1,0],["READY",1,0],["READY",1,0],["READY",1,0]] );

    # Run a singl job
    my $job_id = 4;
    runWorker($pipeline_url, ['--job_id' => $job_id]);
    assert_jobs($job_adaptor, [["DONE",0,0],["SEMAPHORED",0,3],["DONE",2,0],["DONE",1,0],["READY",1,0],["READY",1,0],["READY",1,0]] );
    my $completion_date1 = fetch_job_completion_date($job_adaptor, $job_id);

    # Try again
    #  Guarantee there would be at least 1 second between the completion timestamps
    #  You can't trust time on Travis, sleep(1) may sleep for less than 1 second, so sleeping for 2 seconds
    sleep(2);
    # Won't do anything because the job is already DONE, but runWorker still returns 0
    runWorker($pipeline_url, ['--job_id' => $job_id]);
    my $completion_date2 = fetch_job_completion_date($job_adaptor, $job_id);
    is($completion_date2, $completion_date1, 'The job was not re-run (same completion date)');
    assert_jobs($job_adaptor, [["DONE",0,0],["SEMAPHORED",0,3],["DONE",2,0],["DONE",1,0],["READY",1,0],["READY",1,0],["READY",1,0]] );

    # And again
    runWorker($pipeline_url, ['--job_id' => $job_id, '--force']);
    my $completion_date3 = fetch_job_completion_date($job_adaptor, $job_id);
    cmp_ok($completion_date3, 'gt', $completion_date1, 'The job was really re-run (newer completion date)');
    assert_jobs($job_adaptor, [["DONE",0,0],["SEMAPHORED",0,3],["DONE",2,0],["DONE",1,0],["READY",1,0],["READY",1,0],["READY",1,0]] );

    # Run another worker to get more failures
    foreach my $job_id (4,5,6,7) {
        runWorker($pipeline_url, [ '-job_id' => $job_id ]);
    }
    assert_jobs($job_adaptor, [["DONE",0,0],["SEMAPHORED",0,2],["DONE",2,0],["DONE",1,0],["FAILED",2,0],["DONE",1,0],["FAILED",2,0]] );

    # Reset FAILED jobs
    beekeeper($hive_url, ['-reset_failed_jobs'], 'beekeeper.pl -reset_failed_jobs');
    assert_jobs($job_adaptor, [["DONE",0,0],["SEMAPHORED",0,2],["DONE",2,0],["DONE",1,0],["READY",1,0],["DONE",1,0],["READY",1,0]] );

    # Discard READY jobs
    beekeeper($hive_url, ['-discard_ready_jobs'], 'beekeeper.pl -discard_ready_jobs');
    assert_jobs($job_adaptor, [["DONE",0,0],["READY",0,0],["DONE",2,0],["DONE",1,0],["DONE",1,0],["DONE",1,0],["DONE",1,0]] );

    # Reset all fan jobs to READY
    beekeeper($hive_url, ['-reset_all_jobs', '-analyses_pattern', 'failure_test'], 'beekeeper.pl -reset_all_jobs');
    assert_jobs($job_adaptor, [["DONE",0,0],["SEMAPHORED",0,5],["READY",1,0],["READY",1,0],["READY",1,0],["READY",1,0],["READY",1,0]] );

    # Unblock SEMAPHORED jobs
    beekeeper($hive_url, ['-unblock_semaphored_jobs'], 'beekeeper.pl -unblock_semaphored_jobs');
    assert_jobs($job_adaptor, [["DONE",0,0],["READY",0,0],["READY",1,0],["READY",1,0],["READY",1,0],["READY",1,0],["READY",1,0]] );

    # Reset a specific job_id
    beekeeper($hive_url, ['-reset_job_id', 1], 'beekeeper.pl -reset_job_id');
    assert_jobs($job_adaptor, [["READY",1,0],["READY",0,0],["READY",1,0],["READY",1,0],["READY",1,0],["READY",1,0],["READY",1,0]] );

    # Discard all jobs, but this time some non-fan jobs as well
    beekeeper($hive_url, ['-discard_ready_jobs'], 'beekeeper.pl -discard_ready_jobs');
    assert_jobs($job_adaptor, [['DONE',1,0],['READY',0,0],['DONE',1,0],['DONE',1,0],['DONE',1,0],['DONE',1,0],['DONE',1,0]] );

   $hive_dba->dbc->disconnect_if_idle();
   run_sql_on_db($pipeline_url, 'DROP DATABASE');

  }
}

done_testing();

