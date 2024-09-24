#!/usr/bin/env perl

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Version;

my $ehrd        = $ENV{'EHIVE_ROOT_DIR'}        or die "Environment variable 'EHIVE_ROOT_DIR' not defined, please check your setup";
my $erd         = $ENV{'ENSEMBL_CVS_ROOT_DIR'}  or die "Environment variable 'ENSEMBL_CVS_ROOT_DIR' not defined, please check your setup";
my $doxy_target = $ARGV[0]                      or die "Command-line argument <doxygen_target_path> not defined, please check your setup";
my $code_ver    = Bio::EnsEMBL::Hive::Version->get_code_version();

my @shared_params = (
    "echo 'PROJECT_NUMBER         = $code_ver'",
    "echo 'OUTPUT_DIRECTORY       = $doxy_target'",
    "echo 'EXCLUDE_PATTERNS       = */_build/*'",
    "echo 'USE_MDFILE_AS_MAINPAGE = README.md'",
    "echo 'ENABLE_PREPROCESSING   = NO'",
    "echo 'RECURSIVE              = YES'",
    "echo 'EXAMPLE_PATTERNS       = *'",
    "echo 'HTML_TIMESTAMP         = YES'",
    "echo 'HTML_DYNAMIC_SECTIONS  = YES'",
    "echo 'GENERATE_TREEVIEW      = YES'",
    "echo 'GENERATE_LATEX         = NO'",
    "echo 'HAVE_DOT               = YES'",
    "echo 'EXTRACT_ALL            = YES'",
    "echo 'SOURCE_BROWSER         = YES'",
);


main();


sub main {

        generate_docs_doxygen_perl();
        generate_docs_doxygen_python();
}


sub generate_docs_doxygen_perl {

    print "Regenerating $doxy_target/perl ...\n\n";

    my $doxy_bin    = `which doxygen`;
    chomp $doxy_bin;

    die "Cannot run doxygen binary, please make sure it is installed and is in the path.\n" unless(-r $doxy_bin);

    my $doxy_filter = "$erd/ensembl/misc-scripts/doxygen_filter/ensembldoxygenfilter.pl";

    die "Cannot run the Ensembl-Doxygen Perl filter at '$doxy_filter', please make sure Ensembl core API is intalled properly.\n" unless(-x $doxy_filter);

    my @cmds = (
        "rm   -rf $doxy_target/perl",
        "mkdir -p $doxy_target/perl",
        "rm   -f $doxy_target/ensembl-hive.tag",
        "doxygen -g -",
        "echo 'PROJECT_NAME           = ensembl-hive'",
        "echo 'STRIP_FROM_PATH        = $ehrd'",
        "echo 'INPUT                  = $ehrd'",
        "echo 'INPUT_FILTER           = $doxy_filter'",
        "echo 'HTML_OUTPUT            = perl'",
        "echo 'EXTENSION_MAPPING      = pm=C pl=C'",
        "echo 'FILE_PATTERNS          = *.pm *.pl README.md'",
        "echo 'GENERATE_TAGFILE       = $doxy_target/ensembl-hive.tag'",
        "echo 'CLASS_DIAGRAMS         = NO'",
        "echo 'COLLABORATION_GRAPH    = NO'",
        @shared_params,
    );

    my $full_cmd = '('.join(' ; ', @cmds).") | doxygen -";

    print "Running the following command:\n\t$full_cmd\n\n";

    system( $full_cmd );
}


sub generate_docs_doxygen_python {

    print "Regenerating $doxy_target/python3 ...\n\n";

    my $doxy_bin    = `which doxygen`;
    chomp $doxy_bin;
    die "Cannot run doxygen binary, please make sure it is installed and is in the path.\n" unless(-r $doxy_bin);

    my $doxypypy = `which doxypypy`;
    chomp $doxypypy;
    die "Cannot find the Doxygen Python filter 'doxypypy' in the current PATH.\n" unless -e $doxypypy;

    my @cmds = (
        "rm -rf $doxy_target/python3",
        "mkdir -p $doxy_target/python3",
        "doxygen -g -",
        "echo 'PROJECT_NAME           = ensembl-hive-python3'",
        "echo 'PROJECT_NUMBER         = $code_ver'",
        "echo 'OUTPUT_DIRECTORY       = $doxy_target'",
        "echo 'STRIP_FROM_PATH        = $ehrd/wrappers/python3'",
        "echo 'INPUT                  = $ehrd/wrappers/python3'",
        "echo 'HTML_OUTPUT            = python3'",
        "echo 'FILE_PATTERNS          = *.py README.md'",
        "echo 'FILTER_PATTERNS        = *.py=$ehrd/scripts/dev/doxypypy_filter.sh'",
        "echo 'EXTRACT_PRIVATE        = YES'",
        "echo 'EXTRACT_STATIC         = YES'",
        "echo 'CLASS_DIAGRAMS         = YES'",
        "echo 'CALL_GRAPH             = YES'",
        "echo 'CALLER_GRAPH           = YES'",
        "echo 'COLLABORATION_GRAPH    = NO'",
        @shared_params,
    );

    my $full_cmd = '('.join(' ; ', @cmds).") | doxygen -";

    print "Running the following command:\n\t$full_cmd\n\n";

    system( $full_cmd );
}



__DATA__

=pod

=head1 NAME

make_doxygen.pl

=head1 DESCRIPTION

An internal eHive script for regenerating the Doxygen documentation.

=head1 LICENSE

    See the NOTICE file distributed with this work for additional information
    regarding copyright ownership.

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

Please subscribe to the eHive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss eHive-related questions or to be notified of our updates

=cut

