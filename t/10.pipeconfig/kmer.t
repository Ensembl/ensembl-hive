#!/usr/bin/env perl

# Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
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

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} = File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

# Fasta file for calculating kmers in long sequence mode
my $inputfasta = File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ).'/input_fasta.fa';
# Fastq file for calculating kmers in short sequence mode
my $inputfastq = File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ).'/input_fastq.fastq';


my $dir = tempdir CLEANUP => 1;
my $original = chdir $dir;

my $base_ehive_test_pipeline_url = $ENV{'EHIVE_TEST_PIPELINE_URLS'} || 'sqlite:///ehive_test_pipeline_db';
my $ehive_test_pipeconfigs   = $ENV{'EHIVE_TEST_PIPECONFIGS'} || qw(KmerPipeline_conf KmerPipelineAoH_conf); 

my $kmer_pipeline_modes      = 'short long';
my $kmer_param_configs       = {'short' => [-seqtype => "short",
					    -inputfile => "$inputfastq",
					    -chunk_size => 40,
					    -output_prefix => "k_split_",
					    -output_suffix => ".fastq",
					    -input_format => "FASTQ",
					    -k => 5],
				'long' => [-seqtype => "long",
					   -inputfile => "$inputfasta",
					   -chunk_size => 40,
					   -output_prefix => "k_split_",
					   -output_suffix => ".fa",
					   -input_format => "FASTA",
					   -k => 5]
			       };


my @pipeline_urls = split( /[\s,]+/, $base_ehive_test_pipeline_url );
my @pipeline_cfgs = split( /[\s,]+/, $ehive_test_pipeconfigs ) ;
my @kmer_pipeline_modes = split( /[\s,]+/, $kmer_pipeline_modes ) ;

foreach my $pipeline_url ( @pipeline_urls ) {

  foreach my $kmer_version ( @pipeline_cfgs ) {

    foreach my $kmer_pipeline_mode ( @kmer_pipeline_modes ) {
      
      warn "\nInitializing the $kmer_version $kmer_pipeline_mode sequence pipeline into $pipeline_url ...\n\n";
      
      my $pipeline_options = [@{$kmer_param_configs->{$kmer_pipeline_mode}}, -pipeline_url => $pipeline_url, -hive_force_init => 1,];
      
      my $url              = init_pipeline('Bio::EnsEMBL::Hive::Examples::Kmer::PipeConfig::'.$kmer_version, $pipeline_options );
      
      my $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
							   -url                        => $url,
							   -disconnect_when_inactive   => 1,
							  );
      
      # override the 'take_time' PipelineWideParameter in the loaded HivePipeline object to make the internal test Worker run quicker:
      
      # First run a single worker in this process
      runWorker($pipeline, { can_respecialize => 1 });
      
      my $hive_dba    = $pipeline->hive_dba;
      my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;
      is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 0, 'All the runWorker jobs could be run');
      
      # Let's now try the combination of end-user scripts: seed_pipeline + beekeeper
      {
	# override the 'take_time' PipelineWideParameter directly in the database to make the external test Workers run quicker:
	$hive_dba->get_PipelineWideParametersAdaptor->update( {'param_name' => 'take_time', 'param_value' => 0} );
	
	my @beekeeper_cmd = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/beekeeper.pl', -url => $hive_dba->dbc->url, -sleep => 0.02, '-loop', '-local');
	
	system(@beekeeper_cmd);
	ok(!$?, 'beekeeper exited with the return code 0');
	is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 0, 'All the jobs could be run');
      }
      
      my $final_result_nta = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );
      my $final_results = $final_result_nta->fetch_all();
      
      if ($kmer_pipeline_mode eq 'long') {
	is(scalar(@$final_results), 66, 'There are exactly 66 final_results');
	
	my $sum_of_spotchecks = 0;
	foreach ( @$final_results ) {
	  if ($_->{'kmer'} eq 'ACGAT') {
	    $sum_of_spotchecks += $_->{'frequency'};
	  }
	  if ($_->{'kmer'} eq 'ACGTA') {
	    $sum_of_spotchecks += $_->{'frequency'};
	  }
	  
	}
	ok( 16 == $sum_of_spotchecks, # if last kmer isn't correctly discarded, this will be 17
	    sprintf("f(ACGAT) + f(ACGTA)=%f", , $sum_of_spotchecks) );
      }
      
      if ($kmer_pipeline_mode eq 'short') {
	is(scalar(@$final_results), 407, 'There are exactly 407 final_results');
	
	my $sum_of_spotchecks = 0;
	foreach ( @$final_results ) {
	  if ($_->{'kmer'} eq 'AGCGC') {
	    $sum_of_spotchecks += $_->{'frequency'};
	  }
	  if ($_->{'kmer'} eq 'ATGAT') {
	    $sum_of_spotchecks += $_->{'frequency'};
	  }
	}
	ok( 5 == $sum_of_spotchecks,
	    sprintf("f(AGCGC) + f(ATGAT)=%f", , $sum_of_spotchecks) );
      }
      #    system( @{ $hive_dba->dbc->to_cmd(undef, undef, undef, 'DROP DATABASE') } );
    }
  }
}

done_testing();

chdir $original;

