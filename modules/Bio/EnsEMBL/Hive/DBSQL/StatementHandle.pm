=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::StatementHandle

=head1 SYNOPSIS

    Do not use this class directly.
    It will automatically be used by the Bio::EnsEMBL::Hive::DBSQL::DBConnection class.

=head1 DESCRIPTION

    This class extends DBI::st via containment, intercepts possible "gone away" errors,
    automatically reconnects and re-prepares the statement. It should take much less resources
    than pinging or worrying about disconnecting before and reconnecting after external processes
    whose duration we do not control.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2023] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::DBSQL::StatementHandle;

use strict;
no strict 'refs';
use warnings;
use Bio::EnsEMBL::Hive::Utils ('throw', 'stringify');
use Bio::EnsEMBL::Hive::Utils::SQLErrorParser;


sub new {
    my ($class, $dbc, $sql, $attr) = @_;

    my $dbi_sth;
    eval {
        $dbi_sth = $dbc->protected_prepare( $sql, $attr );
        1;
    } or do {
        throw( "FAILED_SQL(".$dbc->dbname."): " . join(' ', $sql, stringify($attr)) . "\nGot: ".$@."\n" );
    };

    my $self = bless {}, $class;

    my $real_self = {};
    # $self will remain empty whereas $real_self will actually have all the data
    # Its only purpose is to offer a hash-reference on which perl allows
    # calling hash accessors, e.g. $sth->{Active}
    tie %$self, 'DBIstHashProxy', $dbi_sth, $real_self;

    $self->dbc( $dbc );
    $self->sql( $sql );
    $self->attr( $attr );

    $self->dbi_sth( $dbi_sth );

    return $self;
}

## Since $self is a tied hash and doesn't have any data,
## real_self returns the real underlying hash and is used
## in most of the function calls below

sub real_self {
    my $self = shift;
    return (tied %$self)->[1];
}


sub dbc {
    my $self = shift;
    $self = $self->real_self;
    $self->{'_dbc'} = shift if(@_);
    return $self->{'_dbc'};
}


sub sql {
    my $self = shift;
    $self = $self->real_self;
    $self->{'_sql'} = shift if(@_);
    return $self->{'_sql'};
}


sub attr {
    my $self = shift;
    $self = $self->real_self;
    $self->{'_attr'} = shift if(@_);
    return $self->{'_attr'};
}


## dbi_sth is the exception since it has to be in the first position
## of the tied structure for Tie::ExtraHash to work.
sub dbi_sth {
    my $self = shift;
    my $self_array = tied %$self;
    $self_array->[0] = shift if(@_);
    return $self_array->[0];
}


sub AUTOLOAD {
    our $AUTOLOAD;

    $AUTOLOAD=~/^.+::(\w+)$/;
    my $method_name = $1;

#    warn "[AUTOLOAD instantiating '$method_name'] ($AUTOLOAD)\n";

    *$AUTOLOAD = sub {
#        warn "[AUTOLOADed method '$method_name' running] ($AUTOLOAD)\n";

        my $self = shift @_;
        my $dbi_sth = $self->dbi_sth() or throw( "dbi_sth returns false" );
        my $wantarray = wantarray;

        my @retval;
        eval {
            if( $wantarray ) {
                @retval = $dbi_sth->$method_name( @_ );
            } else {
                $retval[0] = $dbi_sth->$method_name( @_ );
            }
            1;
        } or do {
            my $error = $@;
            my $dbc = $self->dbc();
            if (Bio::EnsEMBL::Hive::Utils::SQLErrorParser::is_connection_lost($dbc->driver, $error)) {

                my $sql = $self->sql();
                my $attr = $self->attr();

                warn "trying to reconnect...";
                $dbc->reconnect();

                warn "trying to re-prepare [$sql". ($attr ? (', '.stringify($attr)) : '') ."]...";
                # NOTE: parameters set via the hash interface of $sth will be lost
                $dbi_sth = $dbc->db_handle->prepare( $sql, $attr );
                $self->dbi_sth( $dbi_sth );

                warn "trying to re-$method_name...";
                if( $wantarray ) {
                    @retval = $dbi_sth->$method_name( @_ );
                } else {
                    $retval[0] = $dbi_sth->$method_name( @_ );
                }
            } else {
                throw( $error );
            }
        };

        return $wantarray ? @retval : $retval[0];
    };
    goto &$AUTOLOAD;
}


sub DESTROY {   # note AUTOLOAD/DESTROY interdependence!
    my ($self) = @_;

    my $dbc = $self->dbc;
    $self->dbc(undef);

    my $sql = $self->sql;
    $self->sql(undef);

    $self->dbi_sth( undef );  # make sure it goes through its own DESTROY *now*

    #
    # Forgetting $dbi_sth gets it out of scope, which decrements $db_handle->{Kids} .
    # If as the result the $db_handle has no more Kids, we can safely trigger the disconnect if it was requested.
    #

    if (   $dbc
        && $dbc->disconnect_when_inactive()
        && $dbc->connected
        && ( $dbc->db_handle->{Kids} == 0 ) ) {

        if ( $dbc->disconnect_if_idle() ) {
            warn("Problem disconnect $self around sql = $sql\n");
        }
    }
}


## Just like AUTOLOAD for function calls, we need to redirect
## the HASH methods to the DBI::st instance
## We can conveniently use Tie::ExtraHash, which maps the methods
## to the first element of the array, allowing us to store
## other things in the other elements.

package DBIstHashProxy;

use Tie::Hash;
use base ('Tie::ExtraHash');

# Pass the target hash as the first argument
sub TIEHASH {
    my $class = shift;
    my $self = [@_];
    bless $self, $class;
    return $self;
}


1;
