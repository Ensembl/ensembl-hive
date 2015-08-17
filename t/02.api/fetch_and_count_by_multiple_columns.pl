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
use Data::Dumper;
use Getopt::Long;

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

my $url;
GetOptions( 'url=s' => \$url );
die "Please specify the -url\n" unless($url);

$ENV{'EHIVE_ROOT_DIR'} = $ENV{'ENSEMBL_CVS_ROOT_DIR'}.'/ensembl-hive';  # I'm just being lazy. For the correct way to set this variable check eHive scripts
my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $url );

print "Filtering on 1 column:\n";
print join("\n", map { "\t".$_->toString } @{ $hive_dba->get_DataflowRuleAdaptor->fetch_all_by_from_analysis_id(1) } )."\n";

print "Filtering on 2 columns:\n";
print join("\n", map { "\t".$_->toString } @{ $hive_dba->get_DataflowRuleAdaptor->fetch_all_by_from_analysis_id_AND_branch_code(1, 2) } )."\n";

print "Count(filter by 1 'from_analysis_id' column) ".$hive_dba->get_DataflowRuleAdaptor->count_all_by_from_analysis_id(1)."\n";
print "Count(filter by 1 'branch_code' column) ".$hive_dba->get_DataflowRuleAdaptor->count_all_by_branch_code(1)."\n";
print "Count(filter by 2 columns) ".$hive_dba->get_DataflowRuleAdaptor->count_all_by_from_analysis_id_AND_branch_code(1, 2)."\n";

print "Count workers: ".$hive_dba->get_WorkerAdaptor->count_all()."\n";
print "Count workers by meadow_user: ".$hive_dba->get_WorkerAdaptor->count_all_by_meadow_user('lg4')."\n";
print "Count workers HASHED FROM meadow_user: ".Dumper($hive_dba->get_WorkerAdaptor->count_all_HASHED_FROM_meadow_user())."\n";
print "Count workers HASHED FROM meadow_type, meadow_user: ".Dumper($hive_dba->get_WorkerAdaptor->count_all_HASHED_FROM_meadow_type_AND_meadow_user())."\n";

