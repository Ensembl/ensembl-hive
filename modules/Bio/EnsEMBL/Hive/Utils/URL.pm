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

    my ($old_parse, $new_parse,
        $dbconn_part, $driver, $user, $pass, $host, $port, $dbname, $table_name, $tparam_name, $tparam_value, $conn_param_string, $query_part);

    if( $url=~/^\w+$/ ) {

        $new_parse = $old_parse = {
            'table_name'    => 'analysis',
            'tparam_name'   => 'logic_name',
            'tparam_value'  => $url,
            'unambig_url'   => ':///',
        };

    } else {

        if( ($dbconn_part, $driver, $user, $pass, $host, $port, $dbname, $table_name, $tparam_name, $tparam_value, $conn_param_string) =
            $url =~ m{^((\w*)://(?:(\w+)(?:\:([^/\@]*))?\@)?(?:([\w\-\.]+)(?:\:(\d*))?)?/([\w\-]*))(?:/(\w+)(?:\?(\w+)=([\w\[\]\{\}]*))?)?((?:;(\w+)=(\w+))*)$} ) {

            my %conn_params = split(/[;=]/, 'type=hive;disconnect_when_inactive=0'.$conn_param_string );

            $old_parse = {
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
        }
    
        if( ($dbconn_part, $driver, $user, $pass, $host, $port, $dbname, $query_part) =
            $url =~ m{^((\w+)://(?:(\w+)(?:\:([^/\@]*))?\@)?(?:([\w\-\.]+)(?:\:(\d*))?)?/([/~\w\-\.]*))?(?:\?(\w+=[\w\[\]\{\}]*(?:[&;]\w+=[\w\[\]\{\}]*)*))?$} ) {

            my %query_params = split(/[&;=]/, $query_part // '');

            $new_parse = {
                'dbconn_part'   => $dbconn_part,
                'driver'        => $driver,
                'user'          => $user,
                'pass'          => $pass,
                'host'          => $host,
                'port'          => $port,
                'dbname'        => $dbname,
                'query_part'    => $query_part,
                'query_params'  => \%query_params,
            };
        }

        $port ||= { 'mysql' => 3306, 'pgsql' => 5432, 'sqlite' => '' }->{$driver//''} // '';
        $host = '127.0.0.1' if(($host//'') eq 'localhost');
        my $unambig_url = ($driver//'') .'://'. ($user ? $user.'@' : '') . ($host//'') . ( $port ? ':'.$port : '') .'/'. ($dbname//'');

        $old_parse->{'unambig_url'} = $unambig_url if($old_parse);
        $new_parse->{'unambig_url'} = $unambig_url if($new_parse);
    }

    if($new_parse and $old_parse and $old_parse->{'table_name'}) {
        warn "The URL '$url' can be parsed ambiguously. Using the NEW parser at the moment.\nPlease change your URL to match the new format if you see weird behaviour";
        return $new_parse;
    } elsif($new_parse) {
        return $new_parse;
    } elsif($old_parse) {
        warn "The URL '$url' only works with the old parser, please re-form it according to the new rules as the old parser will soon be deprecated";
        return $old_parse;
    } else {
        warn "The URL '$url' could not be parsed, please check it";
        return;
    }
}

1;
