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

# This is an intentionally broken PipeConfig for testing purposes.
# It has a flow_into that goes to an analysis that is not defined
# in the pipeline.

package TestPipeConfig::MissingAnalysis_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;

sub pipeline_analyses {
    my ($self) = @_;
    return [
        { -logic_name  => 'first',
          -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
          -meadow_type => 'LOCAL',
          -flow_into   => {
              1 => [ 'oops_i_am_missing' ],
          }
        }
    ];
}
1;
