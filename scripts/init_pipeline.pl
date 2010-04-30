#!/usr/bin/env perl
#
# A generic loader of hive pipelines.
#
# Because all of the functionality is hidden in Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf
# you can create pipelines by calling the methods directly, so the script is just a commandline wrapper.

use strict;
use warnings;

my $default_config_module = 'Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf';
my $config_module = shift @ARGV || (warn "<config_module> undefined, using default '$default_config_module'\n" and $default_config_module);

eval "require $config_module;";

my $self = $config_module->new();

$self->process_options();
$self->run();

