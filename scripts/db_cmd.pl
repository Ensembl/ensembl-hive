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

use Getopt::Long;

use Bio::EnsEMBL::Hive::DBSQL::DBConnection;
use Bio::EnsEMBL::Hive::Utils ('script_usage', 'report_versions');


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
            'sqlcmd=s'          => \$sqlcmd,

            'verbose!'          => \$verbose,
            'help!'             => \$help,
            'v|versions!'       => \$report_versions,
    );

    my $dbc;

    if($help) {

        script_usage(0);

    } elsif($report_versions) {

        report_versions();
        exit(0);

    } elsif($reg_alias) {
        script_usage(1) if $url;

        require Bio::EnsEMBL::Registry;
        Bio::EnsEMBL::Registry->load_all($reg_conf);

        my $species = Bio::EnsEMBL::Registry->get_alias($reg_alias)
            || die "Could not solve the alias '$reg_alias'".($reg_conf ? " via the registry file '$reg_conf'" : "");

        my $dba;
        if ($reg_type) {
            $dba = Bio::EnsEMBL::Registry->get_DBAdaptor($species, $reg_type)
                || die "Could not find any database for '$species' (alias: '$reg_alias') with the type '$reg_type'".($reg_conf ? " via the registry file '$reg_conf'" : "");

        } else {

            my $dbas = Bio::EnsEMBL::Registry->get_all_DBAdaptors(-species => $species);
            if (scalar(@$dbas) == 0) {
                # I think this case cannot happen: if there are no databases, the alias does not exist and get_alias() should have failed
                die "Could not find any database for '$species' (alias: '$reg_alias')".($reg_conf ? " via the registry file '$reg_conf'" : "");

            } elsif (scalar(@$dbas) >= 2) {
                die "There are several databases for '$species' (alias: '$reg_alias'). Please set -reg_type to one of: ".join(", ", map {$_->group} @$dbas);
            };
            $dba = $dbas->[0];
        }

        $dbc = $dba->dbc();

    } elsif($url) {
        $dbc = Bio::EnsEMBL::Hive::DBSQL::DBConnection->new( -url => $url );
    } else {
        script_usage(1);
    }

    if (@append) {
        warn qq{In db_cmd.pl, final arguments don't have to be declared with --append any more. All the remaining arguments are considered to be appended.\n};
    }

    my @cmd = @{ $dbc->to_cmd( $executable, \@prepend, [@append, @ARGV], $sqlcmd ) };

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
    -url is exclusive to -reg_alias. -reg_type is only needed if several databases map to that alias / species.
    If the arguments that have to be appended contain options (i.e. start with dashes), first use a double-dash to indicate the end of db_cmd.pl's options and the start of the arguments that have to be passed as-is (see the example below with --html)

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

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

