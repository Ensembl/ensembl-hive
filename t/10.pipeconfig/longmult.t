#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
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
use File::Temp qw{tempdir};

use Bio::EnsEMBL::Hive::Utils qw(dbc_to_cmd);
use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker);


my $dir = tempdir CLEANUP => 1;
chdir $dir;

foreach my $long_mult_version (qw(LongMult_conf LongMultSt_conf LongMultWf_conf)) {
    my $pipeline_url = "sqlite:///${long_mult_version}";
    my $hive_dba = init_pipeline('Bio::EnsEMBL::Hive::PipeConfig::'.$long_mult_version, [-pipeline_url => $pipeline_url, -hive_force_init => 1]);
    runWorker($hive_dba, { can_respecialize => 1 });
    my $results = $hive_dba->dbc->db_handle->selectall_arrayref('SELECT * FROM final_result');
    ok(scalar(@$results), 'There are some results');
    ok($_->[0]*$_->[1] eq $_->[2], sprintf("%s*%s=%s", $_->[0], $_->[1], $_->[0]*$_->[1])) for @$results;

    system( @{ dbc_to_cmd($hive_dba->dbc, undef, undef, undef, 'DROP DATABASE') } );
}

done_testing();
