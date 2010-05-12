#!/usr/bin/env perl
#
# A generic loader of hive pipelines.
#
# Because all of the functionality is hidden in Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf
# you can create pipelines by calling the right methods of HiveGeneric_conf directly,
# so this script is just a commandline wrapper that can conveniently find modules by their filename.

use strict;
use warnings;

sub usage {
    my $retvalue = shift @_;

    if(`which perldoc`) {
        system('perldoc', $0);
    } else {
        foreach my $line (<DATA>) {
            if($line!~s/\=\w+\s?//) {
                $line = "\t$line";
            }
            print $line;
        }
    }
    exit($retvalue);
}

sub module_from_file {
    my $filename = shift @_;

    if(my $package_line = `grep ^package $filename`) {
        if($package_line=~/^package\s+((?:\w|::)+)\s*;/) {
            return $1;
        } else {
            warn "Package line format unrecognized:\n$package_line\n";
            usage(1);
        }
    } else {
        warn "Could not find the package definition line in '$filename'\n";
        usage(1);
    }
}

sub process_options_and_run_module {
    my $config_module = shift @_;

    eval "require $config_module;";

    my $self = $config_module->new();

    $self->process_options();
    $self->run();
}

sub main {
    my $file_or_module = shift @ARGV || usage(0);

    if( $file_or_module=~/^(\w|::)+$/ ) {

        process_options_and_run_module( $file_or_module );
        
    } elsif(-r $file_or_module) {

        process_options_and_run_module( module_from_file( $file_or_module ) );

    } else {
        warn "The first parameter '$file_or_module' neither seems to be a valid module in PERL5LIB nor a valid readable file\n";
        usage(1);
    }
}

main();

__DATA__

=pod

=head1 NAME

    init_pipeline.pl

=head1 SYNOPSIS

    init_pipeline.pl <config_module_or_filename> [-help | [ [-analysis_topup | -job_topup] <options_for_this_particular_pipeline>]

=head1 DESCRIPTION

    init_pipeline.pl is a generic script that is used to create+setup=initialize eHive pipelines from PipeConfig configuration modules.

=head1 USAGE EXAMPLES

        # get this help message:
    init_pipeline.pl

        # initialize a generic eHive pipeline:
    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf -password <yourpassword>

        # see what command line options are available when initializing long multiplication example pipeline
        #   (assuming your current directory is ensembl-hive/modules/Bio/EnsEMBL/Hive) :
    init_pipeline.pl PipeConfig/LongMult_conf -help

        # initialize the long multiplicaton pipeline by supplying not only mandatory but also optional data:
        #   (assuming your current directory is ensembl-hive/modules/Bio/EnsEMBL/Hive/PipeConfig) :
    init_pipeline.pl LongMult_conf -password <yourpassword> -first_mult 375857335 -second_mult 1111333355556666 

=head1 OPTIONS

    -help           :   get automatically generated list of options that can be set/changed when initializing a particular pipeline

    -analysis_topup :   a special initialization mode when (1) pipeline_create_commands are switched off and (2) only newly defined analyses are added to the database
                        This mode is only useful in the process of putting together a new pipeline.

    -job_topup      :   another special initialization mode when only jobs are created - no other structural changes to the pipeline are acted upon.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

