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

use Bio::EnsEMBL::Hive::Version;

my $ehrd        = $ENV{'EHIVE_ROOT_DIR'}        or die "Environment variable 'EHIVE_ROOT_DIR' not defined, please check your setup";
my $erd         = $ENV{'ENSEMBL_CVS_ROOT_DIR'}  or die "Environment variable 'ENSEMBL_CVS_ROOT_DIR' not defined, please check your setup";
my $code_ver    = Bio::EnsEMBL::Hive::Version->get_code_version();


generate_hive_schema_desc();
generate_docs_scripts();
generate_docs_doxygen_perl();
generate_docs_doxygen_python();


sub generate_hive_schema_desc {

    print "Regenerating $ehrd/docs/hive_schema.html ...\n\n";

    my $sql2html = "$erd/ensembl-production/scripts/sql2html.pl";

    die "Cannot find '$sql2html', please make sure ensembl-production API is intalled properly.\n" unless(-r $sql2html);

    my @cmds = (
        "perl $sql2html -i $ehrd/sql/tables.mysql -d Hive -intro $ehrd/docs/hive_schema.inc -sort_headers 0 -sort_tables 0 -o $ehrd/docs/tmp_hive_schema.html",
        "(head -n 3 $ehrd/docs/tmp_hive_schema.html ; cat $ehrd/docs/hive_schema.hdr ; tail -n +4 $ehrd/docs/tmp_hive_schema.html) > $ehrd/docs/hive_schema.html",
        "rm $ehrd/docs/tmp_hive_schema.html",       # remove the non-patched version
    );

    foreach my $cmd (@cmds) {
        print "Running the following command:\n\t$cmd\n\n";

        system( $cmd );
    }
}


sub generate_docs_scripts {

    print "Regenerating $ehrd/docs/scripts ...\n\n";

    my @cmds = (
        "find $ehrd/docs/scripts -type f -not -name index.html | xargs rm",     # delete all but index.html
        "cd   $ehrd/scripts",
    );
    opendir( my $script_dir, "$ehrd/scripts") || die "Can't opendir $ehrd/scripts: $!";
    foreach my $plname ( readdir($script_dir) ) {
        if( (-f "$ehrd/scripts/$plname") && $plname=~/^(\w+)\.pl$/) {
            my $htmlname = $1.'.html';
            push @cmds, "pod2html --noindex --title=$plname $ehrd/scripts/$plname >$ehrd/docs/scripts/$htmlname";
        }
    }
    closedir($script_dir);
    push @cmds, "rm   pod2htm?.tmp";                                            # clean up after pod2html

    foreach my $cmd (@cmds) {
        print "Running the following command:\n\t$cmd\n\n";

        system( $cmd );
    }
}


sub generate_docs_doxygen_perl {

    print "Regenerating $ehrd/docs/doxygen ...\n\n";

    my $doxy_bin    = `which doxygen`;
    chomp $doxy_bin;

    die "Cannot run doxygen binary, please make sure it is installed and is in the path.\n" unless(-r $doxy_bin);

    my $doxy_ver    = `$doxy_bin --version`;
    chomp $doxy_ver;
    my $doxy_intver = sprintf("%d%03d%03d", split(/\./, $doxy_ver) );

    die "The doxygen I found ($doxy_bin) being version $doxy_ver is not supported, please downgrade to at most 1.8.6 \n" if($doxy_intver > 1008006);

    my $doxy_filter = "$erd/ensembl/misc-scripts/doxygen_filter/ensembldoxygenfilter.pl";

    die "Cannot run the Ensembl-Doxygen Perl filter at '$doxy_filter', please make sure Ensembl core API is intalled properly.\n" unless(-x $doxy_filter);

    my @cmds = (
        "rm   -rf $ehrd/docs/doxygen",
        "doxygen -g -",
        "echo 'PROJECT_NAME           = ensembl-hive'",
        "echo 'PROJECT_NUMBER         = $code_ver'",
        "echo 'OUTPUT_DIRECTORY       = $ehrd/docs'",
        "echo 'STRIP_FROM_PATH        = $ehrd'",
        "echo 'INPUT                  = $ehrd'",
        "echo 'INPUT_FILTER           = $doxy_filter'",
        "echo 'HTML_OUTPUT            = doxygen'",
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
        "echo 'CLASS_DIAGRAMS         = NO'",
        "echo 'HAVE_DOT               = YES'",
        "echo 'CALL_GRAPH             = YES'",
        "echo 'CALLER_GRAPH           = YES'",
    );

    my $full_cmd = '('.join(' ; ', @cmds).") | doxygen -";

    print "Running the following command:\n\t$full_cmd\n\n";

    system( $full_cmd );
}


sub generate_docs_doxygen_python {

    print "Regenerating $ehrd/wrappers/python3/doxygen ...\n\n";

    my $doxy_bin    = `which doxygen`;
    chomp $doxy_bin;
    die "Cannot run doxygen binary, please make sure it is installed and is in the path.\n" unless(-r $doxy_bin);

    my $doxy_filter = `which doxypy`;
    chomp $doxy_filter;

    die "Cannot find the Doxygen Python filter 'doxypy' in the current PATH.\n" unless -e $doxy_filter;

    my @cmds = (
        "rm -rf $ehrd/wrappers/python3/doxygen",
        "doxygen -g -",
        "echo 'PROJECT_NAME           = ensembl-hive-python3'",
        "echo 'PROJECT_NUMBER         = $code_ver'",
        "echo 'OUTPUT_DIRECTORY       = $ehrd/wrappers/python3'",
        "echo 'STRIP_FROM_PATH        = $ehrd/wrappers/python3'",
        "echo 'INPUT                  = $ehrd/wrappers/python3'",
        "echo 'INPUT_FILTER           = $doxy_filter'",
        "echo 'HTML_OUTPUT            = doxygen'",
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


__DATA__

=pod

=head1 NAME

    make_docs.pl

=head1 DESCRIPTION

    An internal eHive script for regenerating the documentation both in docs/scripts (using pod2html) and docs/doxygen (using doxygen).

    The script doesn't have any options at the moment.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

