=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::URL

=head1 DESCRIPTION

    A Hive-specific URL parser.

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


package Bio::EnsEMBL::Hive::Utils::URL;

use strict;
use warnings;
use Bio::EnsEMBL::Hive::Utils ('stringify');


sub parse {
    my $url = shift @_ or return;

    my ($old_parse, $new_parse,
        $dbconn_part, $driver, $user, $pass, $host, $port, $dbname, $table_name, $tparam_name, $tparam_value, $conn_param_string, $query_part);

    if( $url=~/^\w+$/ ) {

        $new_parse = {
            'unambig_url'   => ':///',
            'query_params'  => { 'object_type' => 'Analysis', 'logic_name' => $url, },
        };

    } else {

        if( ($dbconn_part, $driver, $user, $pass, $host, $port, $dbname, $table_name, $tparam_name, $tparam_value, $conn_param_string) =
            $url =~ m{^((\w*)://(?:(\w+)(?:\:([^/\@]*))?\@)?(?:([\w\-\.]+)(?:\:(\d*))?)?/([\w\-\.]*))(?:/(\w+)(?:\?(\w+)=([\w\[\]\{\}]*))?)?((?:;(\w+)=(\w+))*)$} ) {

            my %conn_params = split(/[;=]/, 'type=hive;disconnect_when_inactive=0'.$conn_param_string );
            my $query_params;
            my $exception_from_OLD_format;

            if($table_name) {
                if($table_name eq 'analysis') {
                    $query_params->{'object_type'}          = 'Analysis';
                    $query_params->{$tparam_name}           = $tparam_value;    # $tparam_name is 'logic_name' or 'dbID', $tparam_value is the analysis_name or dbID
                } elsif($table_name eq 'accu') {
                    $query_params->{'object_type'}          = 'Accumulator';
                    $query_params->{'accu_name'}            = $tparam_name;
                    $query_params->{'accu_address'}         = $tparam_value;
                } elsif($table_name eq 'job') {
                    die "Jobs cannot yet be located by URLs, sorry";
                } else {
                    $query_params->{'object_type'}          = 'NakedTable';
                    $query_params->{'table_name'}           = $table_name;
                    if($tparam_name) {
                        if( $tparam_name eq 'insertion_method' ) {  # extra hint on the OLD format from the insertion_method
                            $query_params->{'insertion_method'} = $tparam_value;
                        } elsif( $tparam_name eq 'table_name' ) {   # hinting this is NEW format with a bipartite dbpath
                            $exception_from_OLD_format = 1;
                        }
                    }
                }
            }

            if($exception_from_OLD_format) {
                warn "\nOLD URL parser thinks you are using the NEW URL syntax for a remote $query_params->{'object_type'}, so skipping it (it may be wrong!)\n";
            } else {
                my $unambig_port    = $port // { 'mysql' => 3306, 'pgsql' => 5432, 'sqlite' => '' }->{$driver//''} // '';
                my $unambig_host    = ($host//'') eq 'localhost' ? '127.0.0.1' : ($host//'');
                my $unambig_url     = ($driver//'') .'://'. ($user ? $user.'@' : '') . $unambig_host . ( $unambig_port ? ':'.$unambig_port : '') .'/'. ($dbname//'');

                $old_parse = {
                    'dbconn_part'   => $dbconn_part,
                    'driver'        => $driver,
                    'user'          => $user,
                    'pass'          => $pass,
                    'host'          => $host,
                    'port'          => $port,
                    'dbname'        => $dbname,
                    'conn_params'   => \%conn_params,
                    'query_params'  => $query_params,
                    'unambig_url'   => $unambig_url,
                };
            }
        } # /if OLD format
    
        if( ($dbconn_part, $driver, $user, $pass, $host, $port, $dbname, $query_part, $conn_param_string) =
            $url =~ m{^((\w+)://(?:(\w+)(?:\:([^/\@]*))?\@)?(?:([\w\-\.]+)(?:\:(\d*))?)?(?:/([/~\w\-\.]*))?)?(?:\?(\w+=[\w\[\]\{\}]*(?:&\w+=[\w\[\]\{\}]*)*))?(;\w+=\w+(?:;\w+=\w+)*)?$} ) {

            my %conn_params  = split(/[;=]/, 'type=hive;disconnect_when_inactive=0'.($conn_param_string // '') );
            my $query_params = $query_part ? { split(/[&=]/, $query_part ) } : undef;
            my $exception_from_NEW_format;

            if(!$query_params and ($driver eq 'mysql' or $driver eq 'pgsql') and $dbname and $dbname=~m{/}) {   # a special case of multipart dbpath hints at the OLD format (or none at all)

                $query_params = { 'object_type' => 'NakedTable' };
                $exception_from_NEW_format = 1;

            } elsif($query_params and not (my $object_type = $query_params->{'object_type'})) {    # do a bit of guesswork:

                if($query_params->{'logic_name'}) {
                    $object_type = 'Analysis';
                    if($dbname and $dbname=~m{^([/~\w\-\.]*)/analysis$}) {
                        $exception_from_NEW_format = 1;
                    }
                } elsif($query_params->{'accu_name'}) { # we don't require $query_params->{'accu_address'} to support scalar accu
                    $object_type = 'Accumulator';
                } elsif($query_params->{'table_name'}) {  # NB: the order is important here, in case table_name is reset for non-NakedTables
                    $object_type = 'NakedTable';
                } elsif($query_params->{'insertion_method'}) {
                    $object_type = 'NakedTable';
                    if($dbname and $dbname=~m{^([/~\w\-\.]*)/(\w+)$}) {
                        $exception_from_NEW_format = 1;
                    }
                }

                $query_params->{'object_type'} = $object_type;
            }

            if($exception_from_NEW_format) {
                warn "\nNEW URL parser thinks you are using the OLD URL syntax for a remote $query_params->{'object_type'}, so skipping it (it may be wrong!)\n";
            } else {
                my $unambig_port    = $port // { 'mysql' => 3306, 'pgsql' => 5432, 'sqlite' => '' }->{$driver//''} // '';
                my $unambig_host    = ($host//'') eq 'localhost' ? '127.0.0.1' : ($host//'');
                my $unambig_url     = ($driver//'') .'://'. ($user ? $user.'@' : '') . $unambig_host . ( $unambig_port ? ':'.$unambig_port : '') .'/'. ($dbname//'');

                $new_parse = {
                    'dbconn_part'   => $dbconn_part,
                    'driver'        => $driver,
                    'user'          => $user,
                    'pass'          => $pass,
                    'host'          => $host,
                    'port'          => $port,
                    'dbname'        => $dbname,
                    'conn_params'   => \%conn_params,
                    'query_params'  => $query_params,
                    'unambig_url'   => $unambig_url,
                };
            }
        } # /if NEW format

    }

    if($new_parse and $old_parse) {
        if(stringify($old_parse) eq stringify($new_parse)) {
            return $new_parse;
        } else {
            warn "\nThe URL '$url' can be parsed ambiguously:\n\t".stringify($old_parse)."\nvs\n\t".stringify($new_parse)."\n). Using the OLD parser at the moment.\nPlease change your URL to match the new format if you see weird behaviour\n\n";
            return $old_parse;
        }
    } elsif($new_parse) {
        return $new_parse;
    } elsif($old_parse) {
        warn "\nThe URL '$url' only works with the old parser, please start using the new syntax as the old parser will soon be deprecated\n\n";
        return $old_parse;
    } else {
        warn "\nThe URL '$url' could not be parsed, please check it\n";
        return;
    }
}

1;
