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

package Bio::EnsEMBL::Hive::Scripts::PeekJob;

use strict;
use warnings;
use Data::Dumper;

sub peek {
    my ($pipeline, $job_id) = @_;

    my $hive_dba = $pipeline->hive_dba;
    die "Hive's DBAdaptor is not a defined Bio::EnsEMBL::Hive::DBSQL::DBAdaptor\n" unless $hive_dba and $hive_dba->isa('Bio::EnsEMBL::Hive::DBSQL::DBAdaptor');

    # fetch job and populate params
    my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;
    my $job = $job_adaptor->fetch_by_dbID( $job_id );
    die "Cannot find job with id $job_id\n" unless $job;
    $job->load_parameters;
    my $analysis_id = $job->analysis_id;
    my $logic_name  = $job->analysis->logic_name;

    my $label = "[ Analysis $logic_name ($analysis_id) Job $job_id ]";
    return _stringify_params($job->{'_unsubstituted_param_hash'}, $label);
}

sub _stringify_params {
    my ($params, $label) = @_;
    
    local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Deepcopy = 1;
    local $Data::Dumper::Indent   = 1;
    
    return Data::Dumper->Dump( [ $params ], [ qq(*unsubstituted_param_hash $label) ] );
}

1;
