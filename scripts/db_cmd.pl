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
use Bio::EnsEMBL::Hive::Utils::URL;
use Bio::EnsEMBL::Hive::Utils ('script_usage', 'report_versions');


sub main {
    my ($reg_conf, $reg_type, $reg_alias, $executable, $url, @prepend, @append, $sqlcmd, $to_params, $verbose, $help, $report_versions);

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
            'to_params!'        => \$to_params,     # is being phased out and so no longer documented

            'verbose!'          => \$verbose,
            'help!'             => \$help,
            'v|versions!'       => \$report_versions,
    );

    my $dbc_hash;

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

    my @cmd = @{ dbc_hash_to_cmd( $dbc_hash, $executable, \@prepend, \@append, $sqlcmd, $to_params ) };

    my $flat_cmd = join(' ', map { ($_=~/^-?\w+$/) ? $_ : "\"$_\"" } @cmd);

    if($to_params) {
        print "$flat_cmd\n";
    } else {
        warn "\nRunning command:\n\t$flat_cmd\n\n" if($verbose);

        exec(@cmd);
    }
}

sub dbc_hash_to_cmd {
    my ($dbc_hash, $executable, $prepend, $append, $sqlcmd, $to_params) = @_;

    my $driver = $dbc_hash->{'driver'} || 'mysql';

    if($sqlcmd) {
        if($sqlcmd =~ /(DROP\s+DATABASE(?:\s+IF\s+EXISTS)?\s*?)(?:\s+(\w+))?/i) {
            my $dbname = $2 || $dbc_hash->{dbname};

            if($driver eq 'sqlite') {
                return ['rm', '-f', $dbname];
            } elsif(!$2) {
                if ($driver eq 'mysql') {
                    $sqlcmd = "$1 \`$dbname\`";
                } else {
                    $sqlcmd = "$1 $dbname";
                }
                $dbc_hash->{dbname} = '';
            }
        } elsif($sqlcmd =~ /(CREATE\s+DATABASE(?:\s+IF\s+NOT\s+EXISTS)?\s*?)(?:\s+(\w+))?/i ) {
            my $dbname = $2 || $dbc_hash->{dbname};

            if($driver eq 'sqlite') {
                return ['touch', $dbname];
            } elsif(!$2) {
                if ($driver eq 'mysql') {
                    $sqlcmd = "$1 \`$dbname\`";
                } else {
                    $sqlcmd = "$1 $dbname";
                }
                $dbc_hash->{dbname} = '';
            }
        }
    }

    my @cmd;

    if($driver eq 'mysql') {
        $executable ||= 'mysql';

        push @cmd, $executable                      unless $to_params;
        push @cmd, @$prepend                        if ($prepend && @$prepend);
        push @cmd, "-h$dbc_hash->{'host'}"          if $dbc_hash->{'host'};
        push @cmd, "-P$dbc_hash->{'port'}"          if $dbc_hash->{'port'};
        push @cmd, "-u$dbc_hash->{'user'}"          if $dbc_hash->{'user'};
        push @cmd, "-p$dbc_hash->{'pass'}"          if $dbc_hash->{'pass'};
        push @cmd, ('-e', $sqlcmd)                  if $sqlcmd;
        push @cmd, $dbc_hash->{'dbname'}            if $dbc_hash->{'dbname'};
        push @cmd, @$append                         if ($append && @$append);

    } elsif($driver eq 'pgsql') {
        $executable ||= 'psql';

        push @cmd, ('env', "PGPASSWORD='$dbc_hash->{'pass'}'")  if ($to_params && $dbc_hash->{'pass'});
        push @cmd, $executable                                  unless $to_params;
        push @cmd, @$prepend                                    if ($prepend && @$prepend);
        push @cmd, ('-h', $dbc_hash->{'host'})                  if defined($dbc_hash->{'host'});
        push @cmd, ('-p', $dbc_hash->{'port'})                  if defined($dbc_hash->{'port'});
        push @cmd, ('-U', $dbc_hash->{'user'})                  if defined($dbc_hash->{'user'});
        push @cmd, ('-c', $sqlcmd)                              if $sqlcmd;
        push @cmd, @$append                                     if ($append && @$append);
        push @cmd, $dbc_hash->{'dbname'}                        if defined($dbc_hash->{'dbname'});

    } elsif($driver eq 'sqlite') {
        $executable ||= 'sqlite3';

        die "sqlite requires a database (file) name\n" unless $dbc_hash->{dbname};

        push @cmd, $executable                                  unless $to_params;
        push @cmd, @$prepend                                    if ($prepend && @$prepend);
        push @cmd, @$append                                     if ($append && @$append);
        push @cmd, $dbc_hash->{'dbname'};
        push @cmd, $sqlcmd                                      if $sqlcmd;
    }

    return \@cmd;
}


main();

__DATA__

=pod

=head1 NAME

    db_cmd.pl

=head1 SYNOPSIS

    db_cmd.pl {-url <url> | [-reg_conf <reg_conf>] -reg_alias <reg_alias> [-reg_type <reg_type>] } [ -exec <alt_executable> ] [ -prepend <prepend_params> ] [ -append <append_params> ] [ -sql <sql_command> ] [ -to_params | -verbose ]

=head1 DESCRIPTION

    db_cmd.pl is a generic script that connects you interactively to your database using either URL or Registry and optionally runs an SQL command.
    -url is exclusive to -reg_alias. -reg_type is only needed if several databases map to that alias / species.

=head1 USAGE EXAMPLES

    db_cmd.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/" -sql 'CREATE DATABASE lg4_long_mult'
    db_cmd.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult"
    db_cmd.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult" -sql 'SELECT * FROM analysis_base' -append='--html'
    db_cmd.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost/lg4_long_mult" -exec mysqldump -prepend -t -append analysis_base -append job

    db_cmd.pl -reg_conf ${ENSEMBL_CVS_ROOT_DIR}/ensembl-compara/scripts/pipeline/production_reg_conf.pl -reg_alias compara_master
    db_cmd.pl -reg_conf ${ENSEMBL_CVS_ROOT_DIR}/ensembl-compara/scripts/pipeline/production_reg_conf.pl -reg_alias mus_musculus   -reg_type core
    db_cmd.pl -reg_conf ${ENSEMBL_CVS_ROOT_DIR}/ensembl-compara/scripts/pipeline/production_reg_conf.pl -reg_alias squirrel       -reg_type core -sql 'SELECT * FROM coord_system'

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2021] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

