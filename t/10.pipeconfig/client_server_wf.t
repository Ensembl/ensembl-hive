#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016] EMBL-European Bioinformatics Institute
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

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker beekeeper run_sql_on_db get_test_url_or_die);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $server_url  = get_test_url_or_die(-tag => 'server');
my $client_url  = get_test_url_or_die(-tag => 'client');

init_pipeline('Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMultWfServer_conf', $server_url, [], ['pipeline.param[take_time]=0']);
init_pipeline('Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMultWfClient_conf', $client_url, [-server_url => $server_url], ['pipeline.param[take_time]=0']);

my @server_beekeeper_cmd = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/beekeeper.pl', -url => $server_url, -sleep => 0.1, '-keep_alive', '-local'); # needs to be killed
my @client_beekeeper_cmd = (-sleep => 0.1, '-loop', '-local');       # will exit when the pipeline is over

if(my $server_pid = fork) {
    beekeeper($client_url, \@client_beekeeper_cmd );

    kill('KILL', $server_pid);  # the server needs to be killed as it was running in -keep_alive mode

    my $hive_dba    = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $client_url );
    my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;

    is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 0, 'All the jobs could be run');

    my $final_result_nta = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );
    my $final_results = $final_result_nta->fetch_all();

    is(scalar(@$final_results), 2, 'There are exactly 2 final_results');
    foreach ( @$final_results ) {
        ok( $_->{'a_multiplier'}*$_->{'b_multiplier'} eq $_->{'result'},
            sprintf("%s*%s=%s", $_->{'a_multiplier'}, $_->{'b_multiplier'}, $_->{'result'}) );
    }

    run_sql_on_db($server_url, 'DROP DATABASE');
    run_sql_on_db($client_url, 'DROP DATABASE');

    done_testing();

} else {
    # close (STDOUT);

    exec( @server_beekeeper_cmd );
}


