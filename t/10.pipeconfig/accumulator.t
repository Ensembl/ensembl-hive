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

use Test::More;
use Data::Dumper;

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker beekeeper get_test_url_or_die safe_drop_database);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url  = get_test_url_or_die();

{
    local @INC = @INC;
    push @INC, $ENV{'EHIVE_ROOT_DIR'}.'/t/10.pipeconfig/';
    init_pipeline('TestPipeConfig::Accumulator::NullHashKey_conf', $pipeline_url, [], ['pipeline.param[take_time]=0']);
}
my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );

# Will submit a worker
runWorker($pipeline_url, [ '-can_respecialize' ]);

# Check if null hash key error is correct
my $all_objects = $hive_dba->get_LogMessageAdaptor->fetch_all();

my $msg = 'A key in the accumulator had an empty substitution. Bracket \'{}\' pair number 2, substitution from \'{}[]{test}\' to \'{}[]{}\'';
isnt(index($all_objects->[0]->{'msg'}, $msg), -1, "Detect a null hash key" );

safe_drop_database( $hive_dba );

for my $file ( glob("/tmp/gcpct_pipeline_chunk_*.chnk") ) {
    unlink $file;
}

done_testing();
