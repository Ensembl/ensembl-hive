=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::URL

=head1 DESCRIPTION

    A Hive-specific URL parser.

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


package Bio::EnsEMBL::Hive::Utils::URL;

use strict;
use warnings;

use Data::Dumper;


sub parse {
    my $url = shift @_ or return;

    if( my ($dbconn_part, $driver, $user, $pass, $host, $port, $dbname, $table_name, $tparam_name, $tparam_value, $conn_param_string) =
        $url =~ m{^((\w*)://(?:(\w+)(?:\:([^/\@]*))?\@)?(?:([\w\-\.]+)(?:\:(\d*))?)?/([\w\-]*))(?:/(\w+)(?:\?(\w+)=([\w\[\]\{\}]*))?)?((?:;(\w+)=(\w+))*)$} ) {

        my %conn_params = split(/[;=]/, 'type=hive;disconnect_when_inactive=0'.$conn_param_string );

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
