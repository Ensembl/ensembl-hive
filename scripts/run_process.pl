#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;
use Carp;
use Module::Load;
use JSON;

# List of param names that should be treated as arrays
# TO DO: make this somehow more generic
my $array_params = {
  'species_list' => 1, 'analysis_types' => 1, 'datacheck_groups' => 1
};

# Parse the command line parameters sent to the script
# TO DO: add option to parse dataflow file
my $params = parse_options();

if (!defined($params->{'class'})) {
  confess "--ERROR-- perl class not defined.";
}

# Create the module object and initialize it
my $class = $params->{'class'};
eval("use $class;");

my $runnable = $class->new($params);

# Run the job life cycle
$runnable->fetch_input();
$runnable->run();
$runnable->write_output();

sub parse_options {
  my $params;
  my %hash;

  foreach my $option (@ARGV) {
    next if ($option !~ /^-/);

    $option =~ s/^-//g;
    my @tmp = split("=", $option);

    if ($tmp[1] && ($tmp[1] =~ /,/ || $array_params->{$tmp[0]})) {
      my @values_array = split(",", $tmp[1]);
      $params->{$tmp[0]} = \@values_array;
    } else {
      $params->{$tmp[0]} = $tmp[1]
    }
  }

  return $params;
}

__DATA__

=pod

=head1 NAME

run_process.pl

=head1 SYNOPSIS

    run_process.pl -class=<module_name> [<options_for_the_particular_module>]

=head1 DESCRIPTION

run_process.pl is a generic script that is used to call runnables from a Nextflow .nf file. This script initializes the module object and runs the life cycle of that module: fetch_input(), run(), and write_output()

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2022] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=cut
