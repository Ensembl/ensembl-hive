=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::DBConnection

=head1 SYNOPSIS

    my $url = $dbc->url();

=head1 DESCRIPTION

    Extends the functionality of Bio::EnsEMBL::Hive::DBSQL::CoreDBConnection with things needed by the Hive

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


package Bio::EnsEMBL::Hive::DBSQL::DBConnection;

use strict;
use warnings;

use Time::HiRes ('usleep');
use Bio::EnsEMBL::Hive::Utils::URL;

use base ('Bio::EnsEMBL::Hive::DBSQL::CoreDBConnection');


sub new {
    my $class = shift;
    my %flags = @_;

    if(my $url = $flags{'-url'}) {
        if(my $parsed_url = Bio::EnsEMBL::Hive::Utils::URL::parse( $url )) {

            return $class->SUPER::new(
                -driver => $parsed_url->{'driver'},
                -host   => $parsed_url->{'host'},
                -port   => $parsed_url->{'port'},
                -user   => $parsed_url->{'user'},
                -pass   => $parsed_url->{'pass'},
                -dbname => $parsed_url->{'dbname'},
                -disconnect_when_inactive       => $parsed_url->{'conn_params'}->{'discon'},
                -reconnect_when_connection_lost => $parsed_url->{'conn_params'}->{'recon'},
            );

        } else {
            die "Could not create DBC because could not parse the URL '$url'";
        }
    } else {
        return $class->SUPER::new( @_ );
    }
}

=head2 url

    Arg [1]    : String $environment_variable_name_to_store_password_in (optional)
    Example    : $url = $dbc->url;
    Description: Constructs a URL string for this database connection.
    Returntype : string of format  mysql://<user>:<pass>@<host>:<port>/<dbname>
                               or  sqlite:///<dbname>
    Exceptions : none
    Caller     : general

=cut

sub url {
    my ($self, $psw_env_var_name) = @_;

    my $url = $self->driver . '://';

    if($self->username) {
        $url .= $self->username;

        if(my $psw_expression = $self->password) {
            if($psw_env_var_name) {
                $ENV{$psw_env_var_name} = $psw_expression;
                $psw_expression = '${'.$psw_env_var_name.'}';
            }
            $url .= ':'.$psw_expression if($psw_expression);
        }

        $url .= '@';
    }

    if($self->host) {
        $url .= $self->host;

        if($self->port) {
            $url .= ':'.$self->port;
        }
    }
    $url .= '/' . $self->dbname;

    return $url;
}


sub protected_prepare_execute {     # try to resolve certain mysql "Deadlocks" by trying again (a useful workaround even in mysql 5.1.61)
    my $self                    = shift @_;
    my $sql_params              = shift @_;
    my $deadlock_log_callback   = shift @_;

    my $sql_cmd     = shift @$sql_params;

    my $attempts        = 4;
    my $sleep_max_sec   = 1;
    my $log_message_adaptor;

    my $retval;

    foreach my $attempt (1..$attempts) {
        eval {
            my $sth = $self->prepare( $sql_cmd );
            $retval = $sth->execute( @$sql_params );
            $sth->finish;
            1;
        } or do {
            if($@ =~ /Deadlock found when trying to get lock; try restarting transaction/) {    # ignore this particular error

                my $this_sleep_sec = rand( $sleep_max_sec );

                if( $deadlock_log_callback ) {
                    $deadlock_log_callback->( " temporarily failed due to a DEADLOCK in the database (attempt #$attempt). Will try again in $this_sleep_sec sec" );
                }

                usleep( $this_sleep_sec*1000000 );
                $sleep_max_sec *= 2;
                next;
            }
            die $@;     # but definitely report other errors
        };
        last;
    }
    die "After $attempts attempts the query '$sql_cmd' is still in a deadlock: $@" if($@);

    return $retval;
}

1;

