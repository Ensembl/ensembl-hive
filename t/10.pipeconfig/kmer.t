#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2023] EMBL-European Bioinformatics Institute
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

use Bio::EnsEMBL::Hive::Utils ('find_submodules');
use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker get_test_url_or_die safe_drop_database);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

SKIP: {
    eval { require Bio::SeqIO; };

    skip "Bioperl not installed", 2 if $@;

# Fasta file for calculating kmers in long sequence mode
my $inputfasta = $ENV{'EHIVE_ROOT_DIR'}.'/t/input_fasta.fa';
# Fastq file for calculating kmers in short sequence mode
my $inputfastq = $ENV{'EHIVE_ROOT_DIR'}.'/t/input_fastq.fastq';


my $dir = tempdir CLEANUP => 1;


my $all_longmult_configs = find_submodules 'Bio::EnsEMBL::Hive::Examples::Kmer::PipeConfig';
my $ehive_test_pipeconfigs   = $ENV{'EHIVE_TEST_PIPECONFIGS'} || join(' ', @$all_longmult_configs);

my $kmer_pipeline_modes      = 'short long';
my $kmer_param_configs       = {'short' => [-seqtype => "short",
					    -inputfile => "$inputfastq",
					    -chunk_size => 40,
					    -output_dir => $dir,
					    -output_prefix => "k_split_",
					    -output_suffix => ".fastq",
					    -input_format => "FASTQ",
					    -k => 5],
				'long' => [-seqtype => "long",
					   -inputfile => "$inputfasta",
					   -chunk_size => 40,
					   -output_dir => $dir,
					   -output_prefix => "k_split_",
					   -output_suffix => ".fa",
					   -input_format => "FASTA",
					   -k => 5]
			       };


my @pipeline_cfgs = split( /[\s,]+/, $ehive_test_pipeconfigs ) ;
my @kmer_pipeline_modes = split( /[\s,]+/, $kmer_pipeline_modes ) ;

my $pipeline_url = get_test_url_or_die();

  foreach my $kmer_version ( @pipeline_cfgs ) {

    foreach my $kmer_pipeline_mode ( @kmer_pipeline_modes ) {
      
      note("\nInitializing the $kmer_version $kmer_pipeline_mode sequence pipeline into $pipeline_url ...\n\n");
      
      init_pipeline($kmer_version, $pipeline_url, $kmer_param_configs->{$kmer_pipeline_mode});
      
      # First run a single worker in this process
      runWorker($pipeline_url, [ '-can_respecialize' ]);
      
      my $hive_dba    = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );
      my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;
      is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 0, 'All the runWorker jobs could be run');
      
      my $final_result_nta = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );
      my $final_results = $final_result_nta->fetch_all();
      
      if ($kmer_pipeline_mode eq 'long') {
	is(scalar(@$final_results), 68, 'There are exactly 68 final_results');
	
	my $sum_of_spotchecks = 0;
	my $total_kmers = 0;
	foreach ( @$final_results ) {
	  $total_kmers += $_->{'count'};
	  if ($_->{'kmer'} eq 'ACTGA') {
	    $sum_of_spotchecks += $_->{'count'};
	  }
	  if ($_->{'kmer'} eq 'CGTAG') {
	    $sum_of_spotchecks += $_->{'count'};
	  }
	  if ($_->{'kmer'} eq 'GAGTC') {
	    $sum_of_spotchecks += $_->{'count'};
	  }
	  if ($_->{'kmer'} eq 'TGTTT') {
	    $sum_of_spotchecks += $_->{'count'};
	  }
	  
	}
	ok( 210 == $sum_of_spotchecks, 
	    sprintf("For FASTA: ACTGA + CGTAG + GAGTC + TGTTT = %f", , $sum_of_spotchecks) );
	ok( 3348 == $total_kmers,
	    sprintf("%f kmers found in input fasta file", , $total_kmers) );
      }
      
      if ($kmer_pipeline_mode eq 'short') {
	is(scalar(@$final_results), 411, 'There are exactly 411 final_results');
	
	my $sum_of_spotchecks = 0;
	my $total_kmers = 0;
	foreach ( @$final_results ) {
	  $total_kmers += $_->{'count'};
	  if ($_->{'kmer'} eq 'AACCG') { # last in a sequence
	    $sum_of_spotchecks += $_->{'count'};
	  }
	  if ($_->{'kmer'} eq 'CCAAC') { # first in a sequence
	    $sum_of_spotchecks += $_->{'count'};
	  }
	  if ($_->{'kmer'} eq 'TTGTC') { # most common
	    $sum_of_spotchecks += $_->{'count'};
	  }
	}
	ok( 6 == $sum_of_spotchecks,
	    sprintf("in FASTQ: AACCG + CCAAC + TTGTC =%f", , $sum_of_spotchecks) );
	ok ( 520 == $total_kmers,
	     sprintf("%f kmers found in input FASTQ file", , $total_kmers));
      }

      safe_drop_database( $hive_dba );
    }
  }

}

done_testing();

