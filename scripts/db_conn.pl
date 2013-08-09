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
    my ($reg_conf, $reg_type, $reg_alias, $url, $help);

    GetOptions(
                # connect to the database:
            'reg_conf=s'        => \$reg_conf,
            'reg_type=s'        => \$reg_type,
            'reg_alias=s'       => \$reg_alias,
            'url=s'             => \$url,

            'help!'             => \$help,
    );

    my $dbc_hash;

    if($help) {
        script_usage(0);
    } elsif($reg_conf and $reg_alias) {
        Bio::EnsEMBL::Registry->load_all($reg_conf);

        $reg_type ||= 'hive';
        my $hive_dba = Bio::EnsEMBL::Registry->get_DBAdaptor($reg_alias, $reg_type)
            || die "Could not connect to database via registry file '$reg_conf' and alias '$reg_alias' (assuming type '$reg_type')";
        my $dbc = $url = $hive_dba->dbc();

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

    my $cmd = dbc_hash_to_cmd( $dbc_hash );

    print "Connection command:\t$cmd\n";

    exec($cmd);
}

sub dbc_hash_to_cmd {
    my $dbc_hash = shift @_;

    my $driver = $dbc_hash->{'driver'} || 'mysql';

    if($driver eq 'mysql') {
        my $port = $dbc_hash->{port} || 3306;
        return "mysql --host=$dbc_hash->{host} --port=$port --user='$dbc_hash->{user}' --pass='$dbc_hash->{pass}' $dbc_hash->{dbname}";
    } elsif($driver eq 'pgsql') {
        my $port = $dbc_hash->{port} || 5432;
        return "env PGPASSWORD='$dbc_hash->{pass}' psql --host=$dbc_hash->{host} --port=$port --username='$dbc_hash->{user}' $dbc_hash->{dbname}";
    } elsif($driver eq 'sqlite') {
        return "sqlite3 $dbc_hash->{dbname}";
    }
}

main();

__DATA__

=pod

=head1 NAME

    db_conn.pl

=head1 SYNOPSIS

    db_conn.pl {-url <url> | -reg_conf <reg_conf> -reg_alias <reg_alias> [-reg_type <reg_type>] }

=head1 DESCRIPTION

    db_conn.pl is a generic script that connects you interactively to your database

=head1 USAGE EXAMPLES

    db_conn.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult"

    db_conn.pl -reg_conf ${ENSEMBL_CVS_ROOT_DIR}/ensembl-compara/scripts/pipeline/production_reg_conf.pl -reg_alias compara_master -reg_type compara

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

