#!/usr/bin/env perl

use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}

use Getopt::Long qw(:config no_auto_abbrev);

use Bio::EnsEMBL::Hive::Version;

my $ehrd        = $ENV{'EHIVE_ROOT_DIR'}        or die "Environment variable 'EHIVE_ROOT_DIR' not defined, please check your setup";
my $erd         = $ENV{'ENSEMBL_CVS_ROOT_DIR'}  or die "Environment variable 'ENSEMBL_CVS_ROOT_DIR' not defined, please check your setup";
my $doxy_target = "$ehrd/docs/_build/doxygen/";
my $code_ver    = Bio::EnsEMBL::Hive::Version->get_code_version();


main();


sub main {
    my ($no_schema_desc, $no_script_docs, $no_doxygen);

    GetOptions(
            'no_schema_desc'    => \$no_schema_desc,
            'no_script_docs'    => \$no_script_docs,
            'no_doxygen'        => \$no_doxygen,
    ) or die "Error in command line arguments\n";

    if (@ARGV) {
        die "ERROR: There are invalid arguments on the command-line: ". join(" ", @ARGV). "\n";
    }

    generate_hive_schema_desc() unless($no_schema_desc);
    generate_docs_scripts()     unless($no_script_docs);
    unless($no_doxygen) {
        generate_docs_doxygen_perl();
        generate_docs_doxygen_python();
        generate_docs_doxygen_java();
    }
}


sub generate_hive_schema_desc {

    print "Regenerating $ehrd/docs/appendix/hive_schema.rst ...\n\n";

    my $sql2rst = "$ehrd/scripts/dev/sql2rst.pl";

    die "Cannot find '$sql2rst', please make sure ensembl-production API is intalled properly.\n" unless(-r $sql2rst);

    my @cmds = (
        "rm -rf $ehrd/docs/appendix/hive_schema",
        "$sql2rst -i $ehrd/sql/tables.mysql -fk $ehrd/sql/foreign_keys.sql -d Hive -sort_headers 0 -sort_tables 0 -intro /dev/null -o $ehrd/docs/appendix/hive_schema.rst -diagram_dir hive_schema",
    );

    foreach my $cmd (@cmds) {
        print "Running the following command:\n\t$cmd\n\n";

        system( $cmd );
    }
}


sub generate_docs_scripts {

    my $target_dir = "$ehrd/docs/appendix/scripts";
    print "Regenerating $target_dir...\n\n";

    my @cmds = (
        "rm -rf $target_dir",
        "mkdir  $target_dir",
    );
    opendir( my $script_dir, "$ehrd/scripts") || die "Can't opendir $ehrd/scripts: $!";
    foreach my $plname ( readdir($script_dir) ) {
        if( (-f "$ehrd/scripts/$plname") && $plname=~/^(\w+)\.pl$/) {
            my $rstname = $1.'.rst';
            push @cmds, "pod2html --noindex --title=$plname $ehrd/scripts/$plname | pandoc --standalone --base-header-level=2 -f html -t rst -o $target_dir/$rstname";
            push @cmds, ['sed', '-i', q{/^--/ s/\\\//g}, "$target_dir/$rstname"];
        }
    }
    closedir($script_dir);
    push @cmds, "rm   pod2htm?.tmp";                                            # clean up after pod2html

    foreach my $cmd (@cmds) {
        print "Running the following command:\n\t$cmd\n\n";

        system( ref($cmd) ? @$cmd : $cmd );
    }
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
        "rm   -f $doxy_target/ensembl-hive.tag",
        "doxygen -g -",
        "echo 'PROJECT_NAME           = ensembl-hive'",
        "echo 'PROJECT_NUMBER         = $code_ver'",
        "echo 'OUTPUT_DIRECTORY       = $doxy_target'",
        "echo 'STRIP_FROM_PATH        = $ehrd'",
        "echo 'INPUT                  = $ehrd'",
        "echo 'INPUT_FILTER           = $doxy_filter'",
        "echo 'HTML_OUTPUT            = perl'",
        "echo 'EXTENSION_MAPPING      = pm=C pl=C'",
        "echo 'EXTRACT_ALL            = YES'",
        "echo 'FILE_PATTERNS          = *.pm *.pl README.md'",
        "echo 'USE_MDFILE_AS_MAINPAGE = README.md'",
        "echo 'ENABLE_PREPROCESSING   = NO'",
        "echo 'RECURSIVE              = YES'",
        "echo 'EXAMPLE_PATTERNS       = *'",
        "echo 'HTML_TIMESTAMP         = NO'",
        "echo 'HTML_DYNAMIC_SECTIONS  = YES'",
        "echo 'GENERATE_TREEVIEW      = YES'",
        "echo 'GENERATE_LATEX         = NO'",
        "echo 'GENERATE_TAGFILE       = $doxy_target/ensembl-hive.tag'",
        "echo 'CLASS_DIAGRAMS         = NO'",
        "echo 'HAVE_DOT               = YES'",
        "echo 'COLLABORATION_GRAPH    = NO'",
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

    my $doxy_filter = `which doxypy`;
    chomp $doxy_filter;

    die "Cannot find the Doxygen Python filter 'doxypy' in the current PATH.\n" unless -e $doxy_filter;

    my @cmds = (
        "rm -rf $doxy_target/python3",
        "doxygen -g -",
        "echo 'PROJECT_NAME           = ensembl-hive-python3'",
        "echo 'PROJECT_NUMBER         = $code_ver'",
        "echo 'OUTPUT_DIRECTORY       = $doxy_target'",
        "echo 'STRIP_FROM_PATH        = $ehrd/wrappers/python3'",
        "echo 'INPUT                  = $ehrd/wrappers/python3'",
        "echo 'INPUT_FILTER           = $doxy_filter'",
        "echo 'HTML_OUTPUT            = python3'",
        "echo 'EXTRACT_ALL            = YES'",
        "echo 'EXTRACT_PRIVATE        = YES'",
        "echo 'EXTRACT_STATIC         = YES'",
        "echo 'FILE_PATTERNS          = *.py README.md'",
        "echo 'USE_MDFILE_AS_MAINPAGE = README.md'",
        "echo 'ENABLE_PREPROCESSING   = NO'",
        "echo 'RECURSIVE              = YES'",
        "echo 'EXAMPLE_PATTERNS       = *'",
        "echo 'HTML_TIMESTAMP         = NO'",
        "echo 'HTML_DYNAMIC_SECTIONS  = YES'",
        "echo 'GENERATE_TREEVIEW      = YES'",
        "echo 'GENERATE_LATEX         = NO'",
        "echo 'CLASS_DIAGRAMS         = YES'",
        "echo 'HAVE_DOT               = YES'",
        "echo 'CALL_GRAPH             = YES'",
        "echo 'CALLER_GRAPH           = YES'",
        "echo 'COLLABORATION_GRAPH    = NO'",
        "echo 'SOURCE_BROWSER         = YES'",
    );

    my $full_cmd = '('.join(' ; ', @cmds).") | doxygen -";

    print "Running the following command:\n\t$full_cmd\n\n";

    system( $full_cmd );
}


sub generate_docs_doxygen_java {

    print "Regenerating $doxy_target/java ...\n\n";

    my $doxy_bin    = `which doxygen`;
    chomp $doxy_bin;

    die "Cannot run doxygen binary, please make sure it is installed and is in the path.\n" unless(-r $doxy_bin);

    my @cmds = (
        "rm   -rf $doxy_target/java",
        "doxygen -g -",
        "echo 'PROJECT_NAME           = ensembl-hive-java'",
        "echo 'PROJECT_NUMBER         = $code_ver'",
        "echo 'OUTPUT_DIRECTORY       = $doxy_target'",
        "echo 'STRIP_FROM_PATH        = $ehrd/wrappers/java'",
        "echo 'INPUT                  = $ehrd/wrappers/java'",
        "echo 'HTML_OUTPUT            = java'",
        "echo 'EXTRACT_ALL            = YES'",
        "echo 'USE_MDFILE_AS_MAINPAGE = README.md'",
        "echo 'ENABLE_PREPROCESSING   = NO'",
        "echo 'RECURSIVE              = YES'",
        "echo 'EXAMPLE_PATTERNS       = *'",
        "echo 'HTML_TIMESTAMP         = NO'",
        "echo 'HTML_DYNAMIC_SECTIONS  = YES'",
        "echo 'GENERATE_TREEVIEW      = YES'",
        "echo 'GENERATE_LATEX         = NO'",
        "echo 'CLASS_DIAGRAMS         = YES'",
        "echo 'HAVE_DOT               = YES'",
        "echo 'CALL_GRAPH             = YES'",
        "echo 'CALLER_GRAPH           = YES'",
        "echo 'COLLABORATION_GRAPH    = YES'",
        "echo 'SOURCE_BROWSER         = YES'",
    );

    my $full_cmd = '('.join(' ; ', @cmds).") | doxygen -";

    print "Running the following command:\n\t$full_cmd\n\n";

    system( $full_cmd );
}


__DATA__

=pod

=head1 NAME

make_docs.pl

=head1 DESCRIPTION

An internal eHive script for regenerating the documentation both in docs/scripts (using pod2html) and docs/doxygen (using doxygen).

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2017] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

