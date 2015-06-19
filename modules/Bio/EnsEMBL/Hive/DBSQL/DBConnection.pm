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

    if(my $url = delete $flags{'-url'}) {
        if(my $parsed_url = Bio::EnsEMBL::Hive::Utils::URL::parse( $url )) {

            return $class->SUPER::new(
                %flags,     # they act as overridable defaults

                ( map { ("-$_" => $parsed_url->{$_}) } ( 'driver', 'host', 'port', 'user', 'pass', 'dbname' ) ),    # parentheses are essential

                ( map { ("-$_" => $parsed_url->{'conn_params'}->{$_}) } keys %{$parsed_url->{'conn_params'}}  ),    # parentheses are essential
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

    my @opt_pairs = ();
    foreach my $option ('disconnect_when_inactive', 'wait_timeout', 'reconnect_when_lost') {
        if( defined(my $value = $self->$option()) ) {
            push @opt_pairs, "$option=$value";
        }
    }
    $url = join(';', $url, @opt_pairs);

    return $url;
}


sub connect {       # a wrapper that imitates CSMA/CD protocol's incremental backoff-and-retry approach
    my $self        = shift @_;

    my $attempts    = 8;
    my $sleep_sec   = 1;
    my $retval;

    foreach my $attempt (1..$attempts) {
        eval {
            $retval = $self->SUPER::connect( @_ );
            1;
        } or do {
            if( ($@ =~ /Could not connect to database.+?failed: Too many connections/s)                             # problem on server side (configured with not enough connections)
             or ($@ =~ /Could not connect to database.+?failed: Can't connect to \w+? server on '.+?' \(99\)/s)     # problem on client side (cooling down period after a disconnect)
            ) {

                warn "Possibly transient problem conecting to the database (attempt #$attempt). Will try again in $sleep_sec sec";

                usleep( $sleep_sec*1000000 );
                $sleep_sec *= 2;
                next;

            } else {     # but definitely report other errors

                die $@;
            }
        };
        last;   # stop looping once we succeeded
    }

    if($@) {
        die "After $attempts attempts still could not connect() : $@";
    }

    return $retval;
}


sub protected_prepare_execute {     # try to resolve certain mysql "Deadlocks" by imitating CSMA/CD protocol's incremental backoff-and-retry approach (a useful workaround even in mysql 5.1.61)
    my $self                    = shift @_;
    my $sql_params              = shift @_;
    my $deadlock_log_callback   = shift @_;

    my $sql_cmd         = shift @$sql_params;

    my $attempts        = 9;
    my $sleep_max_sec   = 1;

    my $retval;
    my $query_msg;

    foreach my $attempt (1..$attempts) {
        eval {
            my $sth = $self->prepare( $sql_cmd );
            $retval = $sth->execute( @$sql_params );
            $sth->finish;
            1;
        } or do {
            $query_msg = "QUERY: $sql_cmd, PARAMS: (".join(', ',@$sql_params).")";

            if( $@ =~ /Deadlock found when trying to get lock; try restarting transaction/ ) {

                my $this_sleep_sec = int( rand( $sleep_max_sec )*100 ) / 100.0;

                if( $deadlock_log_callback ) {
                    $deadlock_log_callback->( " temporarily failed due to a DEADLOCK in the database (attempt #$attempt). Will try again in $this_sleep_sec sec" );
                }

                usleep( $this_sleep_sec*1000000 );
                $sleep_max_sec *= 2;
                next;

            } else {     # but definitely report other errors

                die "$@ -- $query_msg";
            }
        };
        last;   # stop looping once we succeeded
    }

    die "After $attempts attempts the query $query_msg still cannot be run: $@" if($@);

    return $retval;
}

our $pass_internal_counter = 0;
sub to_cmd {
    my ($self, $executable, $prepend, $append, $sqlcmd, $hide_password_in_env) = @_;

    my $driver = $self->driver || 'mysql';

    my $dbname = $self->dbname;
    if($sqlcmd) {
        if($sqlcmd =~ /(DROP\s+DATABASE(?:\s+IF\s+EXISTS)?\s*?)(?:\s+(\w+))?/i) {
            $dbname = $2 if $2;

            if($driver eq 'sqlite') {
                return ['rm', '-f', $dbname];
            } else {
                if (not $dbname) {
                    die "'DROP DATABASE' needs a database name\n";
                }
                $sqlcmd = "$1 $dbname" unless $2;
                $dbname = '';
            }
        } elsif($sqlcmd =~ /(CREATE\s+DATABASE\s*?)(?:\s+(\w+))?/i ) {
            $dbname = $2 if $2;

            if($driver eq 'sqlite') {
                return ['touch', $dbname];
            } else {
                if (not $dbname) {
                    die "'CREATE DATABASE' needs a database name\n";
                }
                my %limits = ( 'mysql' => 64, 'pgsql' => 63 );
                if (length($dbname) > $limits{$driver}) {
                    die "Database name '$dbname' is too long (> $limits{$driver}). Cannot create the database\n";
                }
                $sqlcmd = "$1 $dbname" unless $2;
                $dbname = '';
            }
        }
    }

    my @cmd;

    my $hidden_password;
    if ($self->password) {
        if ($hide_password_in_env) {
            my $pass_variable = "EHIVE_TMP_PASSWORD_${pass_internal_counter}";
            $pass_internal_counter++;
            $ENV{$pass_variable} = $self->password;
            $hidden_password = '$'.$pass_variable;
        } else {
            $hidden_password = $self->password;
        }
    }

    if($driver eq 'mysql') {
        $executable ||= 'mysql';

        push @cmd, $executable;
        push @cmd, @$prepend                if ($prepend && @$prepend);
        push @cmd, '-h'.$self->host         if $self->host;
        push @cmd, '-P'.$self->port         if $self->port;
        push @cmd, '-u'.$self->username     if $self->username;
        push @cmd, '-p'.$hidden_password    if $self->password;
        push @cmd, ('-e', $sqlcmd)          if $sqlcmd;
        push @cmd, $dbname                  if $dbname;

    } elsif($driver eq 'pgsql') {
        $executable ||= 'psql';

        push @cmd, ('env', 'PGPASSWORD='.$hidden_password)  if ($self->password);
        push @cmd, $executable;
        push @cmd, @$prepend                if ($prepend && @$prepend);
        push @cmd, ('-h', $self->host)      if defined($self->host);
        push @cmd, ('-p', $self->port)      if defined($self->port);
        push @cmd, ('-U', $self->username)  if defined($self->username);
        push @cmd, ('-c', $sqlcmd)          if $sqlcmd;
        push @cmd, $dbname                  if $dbname;

    } elsif($driver eq 'sqlite') {
        $executable ||= 'sqlite3';

        die "sqlite requires a database (file) name\n" unless $dbname;

        push @cmd, $executable;
        push @cmd, @$prepend                if ($prepend && @$prepend);
        push @cmd, $dbname;
        push @cmd, $sqlcmd                  if $sqlcmd;
    }

    push @cmd, @$append                 if ($append && @$append);

    return \@cmd;
}
1;

