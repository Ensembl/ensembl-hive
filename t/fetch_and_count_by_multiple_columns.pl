#!/usr/bin/env perl

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

