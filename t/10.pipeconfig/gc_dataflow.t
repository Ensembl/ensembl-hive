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

use Test::More;
use Data::Dumper;

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline beekeeper get_test_url_or_die safe_drop_database);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url  = get_test_url_or_die();

{
    local @INC = @INC;
    push @INC, $ENV{'EHIVE_ROOT_DIR'}.'/t/10.pipeconfig/';
    init_pipeline('TestPipeConfig::AnyFailureBranch_conf', $pipeline_url, [], ['pipeline.param[take_time]=100']);
}
my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );

# Will submit a worker
beekeeper($pipeline_url, ['-run', '-local']);

# Find the process_id
my $process_id;
until ($process_id) {
    my $workers = $hive_dba->get_WorkerAdaptor->fetch_all(q{status = 'JOB_LIFECYCLE'});
    if (scalar(@$workers)) {
        $process_id = $workers->[0]->process_id;
    } else {
        sleep 1;
    }
}
ok($process_id, 'Found a process_id');

# Kill the process
note("got process_id $process_id");
system('kill', '-SIGKILL', $process_id);
sleep 10; # must be more than MaxLimboSeconds for beekeeper to actual rip the worker

# Kill the worker
beekeeper($pipeline_url, ['-dead']);

# Assumes that job_ids are auto-incremented
my $new_job = $hive_dba->get_AnalysisJobAdaptor->fetch_by_dbID(2);
ok($new_job, 'Found job with dbID=2');
is($new_job && $new_job->analysis->logic_name, 'third');

safe_drop_database( $hive_dba );

done_testing();

