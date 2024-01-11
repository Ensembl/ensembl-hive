#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2024] EMBL-European Bioinformatics Institute
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

my $server_url  = get_test_url_or_die(-tag => 'server');
my $client_url  = get_test_url_or_die(-tag => 'client');

init_pipeline('Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMultServer_conf', $server_url, [], ['pipeline.param[take_time]=0']);
init_pipeline('Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMultClient_conf', $client_url, [-server_url => $server_url], ['pipeline.param[take_time]=0']);

my @server_beekeeper_cmd = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/beekeeper.pl', -url => $server_url, -sleep => 0.02, '-loop_until' => 'NO_WORK', '-local');  # will exit when there are no jobs left
my @client_beekeeper_cmd = (-sleep => 0.02, '-loop_until' => 'NO_WORK', '-local');  # will exit when there are no jobs left


runWorker($client_url);

if(my $server_pid = fork) {             # "Client" branch
    beekeeper($client_url, \@client_beekeeper_cmd);

    waitpid( $server_pid, 0 ); # wait for the "Server" branch to finish

} else {                                # "Server" branch
    # close (STDOUT);

    exec( @server_beekeeper_cmd );
}

foreach my $url ($client_url, $server_url) {

    my $hive_dba    = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $url );
    my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;

    is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 0, 'All the jobs could be run');

    my $final_result_nta    = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );
    my $final_results       = $final_result_nta->fetch_all();

    is(scalar(@$final_results), 1, 'There is exactly 1 final_result');

    foreach ( @$final_results ) {
        ok( $_->{'a_multiplier'}*$_->{'b_multiplier'} eq $_->{'result'},
            sprintf("%s*%s=%s", $_->{'a_multiplier'}, $_->{'b_multiplier'}, $_->{'result'}) );
    }

    safe_drop_database( $hive_dba );
}

done_testing();

