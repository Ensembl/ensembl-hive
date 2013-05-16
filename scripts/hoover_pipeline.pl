#!/usr/bin/env perl

use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
our $hive_root_dir;
BEGIN {
    $hive_root_dir = File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, "$hive_root_dir/modules";
}

use Getopt::Long;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;
use Bio::EnsEMBL::Hive::Utils ('script_usage');


sub main {
    my ($reg_conf, $reg_alias, $url, $before_datetime, $days_ago);

    GetOptions(
                # connect to the database:
            'reg_conf|regfile=s'    => \$reg_conf,
            'reg_alias|regname=s'   => \$reg_alias,
            'url=s'                 => \$url,

                # specify the threshold datetime:
            'before_datetime=s'     => \$before_datetime,
            'days_ago=f'            => \$days_ago,
    );

    my $hive_dba;
    if($reg_conf and $reg_alias) {
        Bio::EnsEMBL::Registry->load_all($reg_conf);
        $hive_dba = Bio::EnsEMBL::Registry->get_DBAdaptor($reg_alias, 'hive');
    } elsif($url) {
        $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(-url => $url);
    } else {
        warn "\nERROR: Connection parameters (url or reg_conf+reg_alias) need to be specified\n";
        script_usage(1);
    }

    my $threshold_datetime_expression;

    if($before_datetime) {
        $threshold_datetime_expression = "'$before_datetime'";
    } else {
        unless($before_datetime or $days_ago) {
            warn "Neither -before_datetime or -days_ago was defined, assuming '-days_ago 7'\n";
            $days_ago = 7;
        }
        $threshold_datetime_expression = "from_unixtime(unix_timestamp(now())-3600*24*$days_ago)";
    }

    my $sql = qq{
        DELETE m,f,j
          FROM job j
     LEFT JOIN job_file f ON(f.job_id=j.job_id)
     LEFT JOIN log_message m ON(m.job_id=j.job_id)
     WHERE j.status='DONE'
       AND j.completed < $threshold_datetime_expression
    };

    my $dbc = $hive_dba->dbc();
    $dbc->do( "SET FOREIGN_KEY_CHECKS=0" );
    $dbc->do( $sql );
}

main();

__DATA__

=pod

=head1 NAME

    hoover_pipeline.pl

=head1 SYNOPSIS

    hoover_pipeline.pl {-url <url> | -reg_conf <reg_conf> -reg_alias <reg_alias>} [ { -before_datetime <datetime> | -days_ago <days_ago> } ]

=head1 DESCRIPTION

    hoover_pipeline.pl is a script used to remove old 'DONE' jobs from a continuously running pipeline database

=head1 USAGE EXAMPLES

        # delete all jobs that have been 'DONE' for at least a week (default threshold) :

    hoover_pipeline.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult"


        # delete all jobs that have been 'DONE' for at least a given number of days

    hoover_pipeline.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult" -days_ago 3


        # delete all jobs 'DONE' before a specific datetime:

    hoover_pipeline.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult" -before_datetime "2013-02-14 15:42:50"

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

