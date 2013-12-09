=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::DBConnection

=head1 SYNOPSIS

    my $url = $dbc->url();

=head1 DESCRIPTION

    Extends the functionality of Bio::EnsEMBL::DBSQL::DBConnection with things needed by the Hive

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


package Bio::EnsEMBL::Hive::DBSQL::DBConnection;

use strict;
use warnings;

use base ('Bio::EnsEMBL::DBSQL::DBConnection');


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
    my $self        = shift @_;
    my $sql         = shift @_;

    my $retries     = 3;

    foreach (0..$retries) {
        eval {
            my $sth = $self->prepare($sql);
            $sth->execute( @_ );
            $sth->finish;
            1;
        } or do {
            if($@ =~ /Deadlock found when trying to get lock; try restarting transaction/) {    # ignore this particular error
                sleep 1;
                next;
            }
            die $@;     # but definitely report other errors
        };
        last;
    }
    die "After $retries retries the query '$sql' is still in a deadlock: $@" if($@);
}

1;

