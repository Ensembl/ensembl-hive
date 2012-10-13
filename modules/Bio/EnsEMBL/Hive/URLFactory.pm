# Perl module for Bio::EnsEMBL::Hive::URLFactory
#
# Date of creation: 22.03.2004
# Original Creator : Jessica Severin <jessica@ebi.ac.uk>
#
# Copyright EMBL-EBI 2004
#
# You may distribute this module under the same terms as perl itself

=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::URLFactory

=head1 SYNOPSIS

    $url_string1 = 'mysql://ensadmin:<pass>@ecs2:3362/compara_hive_23c';                 # type=hive by default
    $url_string2 = 'mysql://ensadmin:<pass>@ecs2:3362/ensembl_compara_22_1;type=compara'
    $url_string3 = 'mysql://ensadmin:<pass>@ecs2:3362/ensembl_core_homo_sapiens_22_34;type=core'

    $hive_dba    = Bio::EnsEMBL::Hive::URLFactory->fetch($url_string1);
    $compara_dba = Bio::EnsEMBL::Hive::URLFactory->fetch($url_string2);
    $core_dba    = Bio::EnsEMBL::Hive::URLFactory->fetch($url_string3);

=head1 DESCRIPTION  

    Module to parse URL strings and return EnsEMBL objects.
    At the moment, DBAdaptors as well as Analyses, Jobs and NakedTables are supported.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


    # global instance to cache connections and limit the number of open DB connections:
my $_URLFactory_global_instance;

package Bio::EnsEMBL::Hive::URLFactory;

use strict;
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;

use Bio::EnsEMBL::Hive::Extensions;
use Bio::EnsEMBL::DBSQL::AnalysisAdaptor;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::NakedTable;

#use Data::Dumper;

sub new {
    my $class = shift @_;

    unless($_URLFactory_global_instance) {
        $_URLFactory_global_instance = bless {}, $class;
    }
    return $_URLFactory_global_instance;
}

sub DESTROY {
    my ($obj) = @_;

    foreach my $key (keys(%$_URLFactory_global_instance)) {
        $_URLFactory_global_instance->{$key} = undef;
    }
}

=head2 fetch

  Arg[1]     : string $url
  Example    :  $url = 'mysql://user:pass@host:3306/dbname/table_name?tparam_name=tparam_value;type=compara;discon=1'
                my $object = Bio::EnsEMBL::Hive::URLFactory->fetch($url);
  Description: parses the URL, connects to appropriate DBAdaptor,
               determines appropriate object_adaptor, fetches the object
  Returntype : blessed instance of the object refered to or a DBAdaptor if simple URL
  Exceptions : none
  Caller     : ?

=cut

sub fetch {
    my $class       = shift @_;
    my $url         = shift @_ or return;
    my $default_dba = shift @_;

    Bio::EnsEMBL::Hive::URLFactory->new();  # make sure global instance is created

    if( my ($conn, $driver, $user, $pass, $host, $port, $dbname, $table_name, $tparam_name, $tparam_value, $conn_param_string) =
        $url =~ m{^((\w*)://(?:(\w+)(?:\:([^/\@]*))?\@)?(?:([\w\-\.]+)(?:\:(\d+))?)?/([\w\-]*))(?:/(\w+)(?:\?(\w+)=(\w+))?)?((?:;(\w+)=(\w+))*)$} ) {

        my %conn_param = split(/[;=]/, 'type=hive;discon=0'.$conn_param_string );

#warn "URLPARSER: conn='$conn', driver='$driver', user='$user', pass='$pass', host='$host', port='$port', dbname='$dbname', table_name='$table_name', tparam_name='$tparam_name', tparam_value='$tparam_value'";
#warn "CONN_PARAMS: ".Dumper(\%conn_param);

        my $dba = ($conn =~ m{^\w*:///$} ) ? $default_dba : $class->create_cached_dba($driver, $user, $pass, $host, $port, $dbname, %conn_param);

        if(not $table_name) {
        
            return $dba;

        } elsif($table_name eq 'analysis') {

            return $dba->get_AnalysisAdaptor->fetch_by_url_query($tparam_name, $tparam_value);

        } elsif($table_name eq 'job') {

            return $dba->get_AnalysisJobAdaptor->fetch_by_url_query($tparam_name, $tparam_value);

        } else {

            return Bio::EnsEMBL::Hive::NakedTable->new(
                -adaptor    => $dba->get_NakedTableAdaptor,
                -table_name => $table_name,
                $tparam_value ? (-insertion_method => $tparam_value) : ()
            );
        }
    }
    return;
}

sub create_cached_dba {
    my ($class, $driver, $user, $pass, $host, $port, $dbname, %conn_param) = @_;

    if($driver eq 'mysql') {
        $user ||= 'ensro';
        $pass ||= '';
        $host ||= '';
        $port ||= 3306;
    }

    my $type   = $conn_param{'type'};
    my $discon = $conn_param{'discon'};

    my $connectionKey = "$driver://$user:$pass\@$host:$port/$dbname;$type";
    my $dba = $_URLFactory_global_instance->{$connectionKey};

    unless($dba) {

        my $module = {
            'hive'     => 'Bio::EnsEMBL::Hive::DBSQL::DBAdaptor',
            'compara'  => 'Bio::EnsEMBL::Compara::DBSQL::DBAdaptor',
            'core'     => 'Bio::EnsEMBL::DBSQL::DBAdaptor',
            'pipeline' => 'Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor',
        }->{$type};

        eval "require $module";

        $_URLFactory_global_instance->{$connectionKey} = $dba = $module->new (
            -driver => $driver,
            -host   => $host,
            -port   => $port,
            -user   => $user,
            -pass   => $pass,
            -dbname => $dbname,
            -species => $dbname,
            -disconnect_when_inactive => $discon,
        );
    }
    return $dba;
}

1;
