package Bio::EnsEMBL::Hive::Utils::URL;

use strict;
use warnings;

use Data::Dumper;


sub parse {
    my $url = shift @_ or return;

    if( my ($dbconn_part, $driver, $user, $pass, $host, $port, $dbname, $table_name, $tparam_name, $tparam_value, $conn_param_string) =
        $url =~ m{^((\w*)://(?:(\w+)(?:\:([^/\@]*))?\@)?(?:([\w\-\.]+)(?:\:(\d+))?)?/([\w\-]*))(?:/(\w+)(?:\?(\w+)=([\w\[\]\{\}]+))?)?((?:;(\w+)=(\w+))*)$} ) {

        my %conn_params = split(/[;=]/, 'type=hive;discon=0'.$conn_param_string );

        my $parsed_url = {
            'dbconn_part'   => $dbconn_part,
            'driver'        => $driver,
            'user'          => $user,
            'pass'          => $pass,
            'host'          => $host,
            'port'          => $port,
            'dbname'        => $dbname,
            'table_name'    => $table_name,
            'tparam_name'   => $tparam_name,
            'tparam_value'  => $tparam_value,
            'conn_params'   => \%conn_params,
        };

        return $parsed_url;

    } else {

        return;
    }
}

1;
