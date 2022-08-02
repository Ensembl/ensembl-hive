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

