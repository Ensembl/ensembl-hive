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

use File::Temp qw{tempdir};
use Test::Exception;
use Test::More;

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline get_test_url_or_die runWorker safe_drop_database);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url = get_test_url_or_die;

init_pipeline(
    'Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf',
    $pipeline_url,
    [],
    ['pipeline.param[take_time]=0', 'analysis[take_b_apart].meadow_type=undef', 'analysis[take_b_apart].analysis_capacity=1'],
);

my $dir = tempdir CLEANUP => 1;

runWorker($pipeline_url, [ -job_id => 1, ]);
runWorker($pipeline_url, [ -job_id => 2, -worker_base_temp_dir => $dir ]);

my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );

my $worker1 = $hive_dba->get_WorkerAdaptor->fetch_by_dbID(1);
my $worker2 = $hive_dba->get_WorkerAdaptor->fetch_by_dbID(2);

unlike($worker1->temp_directory_name, qr{^$dir}, "The first worker is not using $dir");
  like($worker2->temp_directory_name, qr{^$dir}, "The second worker used $dir");

safe_drop_database( $hive_dba );

done_testing();

