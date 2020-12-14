#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2021] EMBL-European Bioinformatics Institute
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

use Cwd;
use File::Spec;
use File::Basename qw/dirname/;
use Test::More;
use Test::Warnings;
use Term::ANSIColor;
use Bio::EnsEMBL::Hive::Utils::Test qw(all_source_files);

if ( not $ENV{TEST_AUTHOR} ) {
  my $msg = 'Author test. Set $ENV{TEST_AUTHOR} to a true value to run.';
  plan( skip_all => $msg );
}


#chdir into the file's target & request cwd() which should be fully resolved now.
#then go back
my $file_dir = dirname(__FILE__);
my $original_dir = cwd();
chdir($file_dir);
my $cur_dir = cwd();
chdir($original_dir);
my $root = File::Spec->catdir($cur_dir, File::Spec->updir(), File::Spec->updir());


sub is_ascii {
    my $filename = shift;

    my $has_non_ascii;
    open(my $fh, '<', $filename) or die "Cannot open '$filename' because '$!'\n";
    while(<$fh>) {
        if (/[^[:space:][:print:]]/) {
            $has_non_ascii = 1;
            s/([^[:space:][:print:]]+)/colored($1, 'on_red')/eg;
            diag($filename.' has '.$_);
        }
    }
    close($fh);
    if ($has_non_ascii) {
        fail($filename);
    } else {
        pass($filename);
    }
}

my @source_files = all_source_files($root);
#Find all files & run
foreach my $f (@source_files) {
    # Docker-swarm tutorial
    next if $f =~ /docs\/contrib\/docker-swarm\/tutorial\.rst$/;
    # Binary files
    next if $f =~ /\.(jar|class|png|jpg|pdf|pyc|tgz)$/;
    # Simulated program output
    next if $f =~ /lsf_detection\/.*/;
    next if $f =~ /deceptive_bin\/.*/;
    next if $f =~ /fake_bin\/.*/;
    # Unicode-art
    next if $f =~ /modules\/Bio\/EnsEMBL\/Hive\/(Analysis|HivePipeline)\.pm$/;
    next if $f =~ /\/generate_graph\/.*::PipeConfig::.*\.txt$/;
    is_ascii($f);
}

done_testing();

