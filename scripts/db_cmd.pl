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
use Pod::Usage;

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Version ('report_versions');


sub main {
    my ($reg_conf, $reg_type, $reg_alias, $executable, $url, @prepend, @append, $sqlcmd, $verbose, $help, $report_versions);

    GetOptions(
                # connect to the database:
            'reg_conf=s'        => \$reg_conf,
            'reg_type=s'        => \$reg_type,
            'reg_alias=s'       => \$reg_alias,

            'exec|executable=s' => \$executable,
            'url=s'             => \$url,
            'prepend=s@'        => \@prepend,
            'append|extra=s@'   => \@append,
            'sqlcmd|sql=s'      => \$sqlcmd,

            'verbose!'          => \$verbose,
            'help!'             => \$help,
            'v|version|versions!'  => \$report_versions,
    ) or die "Error in command line arguments\n";

    my $dbc;

    if($help) {

        pod2usage({-exitvalue => 0, -verbose => 2});

    } elsif($report_versions) {

        report_versions();
        exit(0);

    } elsif( not ($url xor $reg_alias) ) {
        die "\nERROR: Connection parameters (url or reg_conf+reg_alias) need to be specified\n";

    } else {
        my $dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(
            -url                            => $url,
            -reg_conf                       => $reg_conf,
            -reg_type                       => $reg_type,
            -reg_alias                      => $reg_alias,
            -no_sql_schema_version_check    => 1,
        );

        $dbc = $dba->dbc;
    }

    if (@append) {
        warn qq{In db_cmd.pl, final arguments don't have to be declared with --append any more. All the remaining arguments are considered to be appended.\n};
    }

    my @cmd = @{ $dbc->to_cmd( $executable, \@prepend, [@append, @ARGV], $sqlcmd ) };
    $dbc->disconnect_if_idle;

    if( $verbose ) {
        my $flat_cmd = join(' ', map { ($_=~/^-?\w+$/) ? $_ : "\"$_\"" } @cmd);

        warn "\nThe actual command I am running is:\n\t$flat_cmd\n\n";
    }

    exec(@cmd);
}


main();

__DATA__

=pod

=head1 NAME

db_cmd.pl

=head1 SYNOPSIS

    db_cmd.pl {-url <url> | [-reg_conf <reg_conf>] -reg_alias <reg_alias> [-reg_type <reg_type>] } [ -exec <alt_executable> ] [ -prepend <prepend_params> ] [ -sql <sql_command> ] [ -verbose ] [other arguments to append to the command line]

=head1 DESCRIPTION

db_cmd.pl is a generic script that connects you interactively to your database using either URL or Registry and optionally runs an SQL command.

=head1 OPTIONS

=over

=item --url <url>

URL defining where eHive database is located

=item --reg_conf <path>

path to a Registry configuration file

=item --reg_alias <str>

species/alias name for the eHive DBAdaptor

=item --executable <name|path>

The executable to run instead of the driver's default (which is the command-line client)

=item --prepend <string>

Argument that has to be prepended to the connection details. This option can be repeated

=item --sql <string>

SQL command to execute

=item --verbose

Print the command before running it.

=item --help

Print this help message

=back

All the remaining arguments are passed on to the command to be run.
If some of them start with a dash, first use a double-dash to indicate the end of db_cmd.pl's options and the start of the arguments that have to be passed as is (see the example below with --html)

=head1 USAGE EXAMPLES

    db_cmd.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/" -sql 'CREATE DATABASE lg4_long_mult'
    db_cmd.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult"
    db_cmd.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult" -sql 'SELECT * FROM analysis_base' -- --html
    db_cmd.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost/lg4_long_mult" -exec mysqldump -prepend -t analysis_base job

    db_cmd.pl -reg_conf ${ENSEMBL_CVS_ROOT_DIR}/ensembl-compara/scripts/pipeline/production_reg_conf.pl -reg_alias compara_master
    db_cmd.pl -reg_conf ${ENSEMBL_CVS_ROOT_DIR}/ensembl-compara/scripts/pipeline/production_reg_conf.pl -reg_alias mus_musculus   -reg_type core
    db_cmd.pl -reg_conf ${ENSEMBL_CVS_ROOT_DIR}/ensembl-compara/scripts/pipeline/production_reg_conf.pl -reg_alias squirrel       -reg_type core -sql 'SELECT * FROM coord_system'

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2024] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

Please subscribe to the eHive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss eHive-related questions or to be notified of our updates

=cut

