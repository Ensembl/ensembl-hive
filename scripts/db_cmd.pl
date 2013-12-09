#!/usr/bin/env perl

use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} = File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}

use Getopt::Long;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Hive::Utils::URL;
use Bio::EnsEMBL::Hive::Utils ('script_usage');


sub main {
    my ($reg_conf, $reg_type, $reg_alias, $url, $sqlcmd, $extra, $to_params, $verbose, $help);

    GetOptions(
                # connect to the database:
            'reg_conf=s'        => \$reg_conf,
            'reg_type=s'        => \$reg_type,
            'reg_alias=s'       => \$reg_alias,

            'url=s'             => \$url,

            'sqlcmd=s'          => \$sqlcmd,
            'extra=s'           => \$extra,
            'to_params!'        => \$to_params,

            'verbose!'          => \$verbose,
            'help!'             => \$help,
    );

    my $dbc_hash;

    if($help) {
        script_usage(0);

    } elsif($reg_alias) {
        script_usage(1) if $url;
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

        my $dbc = $dba->dbc();

        $dbc_hash = {
            'driver'    => $dbc->driver,
            'host'      => $dbc->host,
            'port'      => $dbc->port,
            'user'      => $dbc->username,
            'pass'      => $dbc->password,
            'dbname'    => $dbc->dbname,
        };
    } elsif($url) {
        $dbc_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url )
            || die "Could not parse URL '$url'";
    } else {
        script_usage(1);
    }

    my $cmd = dbc_hash_to_cmd( $dbc_hash, $sqlcmd, $extra, $to_params );

    if($to_params) {
        print "$cmd\n";
    } else {
        warn "\nRunning command:\t$cmd\n\n" if($verbose);

        exec($cmd);
    }
}

sub dbc_hash_to_cmd {
    my ($dbc_hash, $sqlcmd, $extra, $to_params) = @_;

    my $driver = $dbc_hash->{'driver'} || 'mysql';

    if($sqlcmd) {
        if($sqlcmd =~ /(DROP\s+DATABASE(?:\s+IF\s+EXISTS)?\s*?)(?:\s+(\w+))?/i) {
            my $dbname = $2 || $dbc_hash->{dbname};

            if($driver eq 'sqlite') {
                return "rm -f $dbname";
            } elsif(!$2) {
                $sqlcmd = "$1 $dbname";
                $dbc_hash->{dbname} = '';
            }
        } elsif($sqlcmd =~ /(CREATE\s+DATABASE\s*?)(?:\s+(\w+))?/i ) {
            my $dbname = $2 || $dbc_hash->{dbname};

            if($driver eq 'sqlite') {
                return "touch $dbname";
            } elsif(!$2) {
                $sqlcmd = "$1 $dbname";
                $dbc_hash->{dbname} = '';
            }
        }
    }

    my $cmd;

    if($driver eq 'mysql') {

        $cmd = ($to_params ? '' : 'mysql ')
              ."--host=$dbc_hash->{host} "
              .(defined($dbc_hash->{port}) ? "--port=$dbc_hash->{port} " : '')
              ."--user=$dbc_hash->{user} --pass='$dbc_hash->{pass}' "
              .(defined($extra) ? "$extra " : '')
              .($dbc_hash->{dbname} || '')
              .(defined($sqlcmd) ? " -e '$sqlcmd'" : '');
    } elsif($driver eq 'pgsql') {

        $cmd = ($to_params ? '' : "env PGPASSWORD='$dbc_hash->{pass}' psql ")
              ."--host=$dbc_hash->{host} "
              .(defined($dbc_hash->{port}) ? "--port=$dbc_hash->{port} " : '')
              ."--username=$dbc_hash->{user} "
              .(defined($sqlcmd) ? "--command='$sqlcmd' " : '')
              .(defined($extra) ? "$extra " : '')
              .($dbc_hash->{dbname} || '');
    } elsif($driver eq 'sqlite') {

        die "sqlite requires a database (file) name\n" unless $dbc_hash->{dbname};
        $cmd = "sqlite3 "
              .(defined($extra) ? "$extra " : '')
              .$dbc_hash->{dbname}
              .(defined($sqlcmd) ? " '$sqlcmd'" : '');
    }

    return $cmd;
}


main();

__DATA__

=pod

=head1 NAME

    db_cmd.pl

=head1 SYNOPSIS

    db_cmd.pl {-url <url> | [-reg_conf <reg_conf>] -reg_alias <reg_alias> [-reg_type <reg_type>] } [ -sql <sql_command> ] [ -extra <extra_params> ] [ -to_params | -verbose ]

=head1 DESCRIPTION

    db_cmd.pl is a generic script that connects you interactively to your database using either URL or Registry and optionally runs an SQL command.
    -url is exclusive to -reg_alias. -reg_type is only needed if several databases map to that alias / species.

=head1 USAGE EXAMPLES

    db_cmd.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/" -sql 'CREATE DATABASE lg4_long_mult'
    db_cmd.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult"
    db_cmd.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult" -sql 'SELECT * FROM analysis_base' -extra='--html'
    eval mysqldump -t `db_cmd.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult" -to_params` worker

    db_cmd.pl -reg_conf ${ENSEMBL_CVS_ROOT_DIR}/ensembl-compara/scripts/pipeline/production_reg_conf.pl -reg_alias compara_master
    db_cmd.pl -reg_conf ${ENSEMBL_CVS_ROOT_DIR}/ensembl-compara/scripts/pipeline/production_reg_conf.pl -reg_alias mus_musculus   -reg_type core
    db_cmd.pl -reg_conf ${ENSEMBL_CVS_ROOT_DIR}/ensembl-compara/scripts/pipeline/production_reg_conf.pl -reg_alias squirrel       -reg_type core -sql 'SELECT * FROM coord_system'

=head1 LICENSE

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

