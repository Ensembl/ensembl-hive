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

use Test::More;

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline get_test_url_or_die safe_drop_database);
use Bio::EnsEMBL::Hive::Utils qw(destringify);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url  = get_test_url_or_die();

{
    local $ENV{'PERL5LIB'} = $ENV{'EHIVE_ROOT_DIR'}.'/t/10.pipeconfig/::'.$ENV{PERL5LIB};
    init_pipeline('TestPipeConfig::PipelineURL_conf', $pipeline_url);
}

my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );

my $analysis = $hive_dba->get_AnalysisAdaptor->fetch_by_logic_name('first');
my $params = destringify($analysis->parameters);
ok(exists $params->{'url'}, '"url" parameter is there');
is($params->{'url'}, $pipeline_url, "URL is correct");

safe_drop_database( $hive_dba );

done_testing();

