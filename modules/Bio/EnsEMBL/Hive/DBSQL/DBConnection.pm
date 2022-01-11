=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::DBConnection

=head1 SYNOPSIS

    my $url = $dbc->url();

=head1 DESCRIPTION

    Extends the functionality of Bio::EnsEMBL::Hive::DBSQL::CoreDBConnection with things needed by the Hive

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2022] EMBL-European Bioinformatics Institute

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
use Bio::EnsEMBL::Hive::Utils ('throw');
use Bio::EnsEMBL::Hive::Utils::URL ('parse', 'hash_to_url');

use base ('Bio::EnsEMBL::Hive::DBSQL::CoreDBConnection');


sub new {
    my $class = shift;
    my %flags = @_;

    if(my $url = delete $flags{'-url'}) {
        if(my $parsed_url = Bio::EnsEMBL::Hive::Utils::URL::parse( $url )) {

            foreach my $name ( 'driver', 'host', 'port', 'user', 'pass', 'dbname' ) {
                $flags{ "-$name" } //= $parsed_url->{$name};
            }
            foreach my $name ( keys %{$parsed_url->{'conn_params'}} ) {
                $flags{ "-$name" } //= $parsed_url->{'conn_params'}->{$name};
            }

            return $class->SUPER::new( %flags );

        } else {
            throw("Could not create DBC because could not parse the URL '$url'");
        }
    } else {
        return $class->SUPER::new( @_ );
    }
}


sub _optional_pair {     # helper function
    my ($key, $value) = @_;

    return defined($value) ? ($key => $value) : ();
}


sub to_url_hash {
    my ($self, $psw_env_var_name) = @_;

    my $psw_expression;
    if($psw_expression = $self->password) {
        if($psw_env_var_name) {
            $ENV{$psw_env_var_name} = $psw_expression;
            $psw_expression = '${'.$psw_env_var_name.'}';
        }
    }

    my $url_hash = {
        _optional_pair('driver',    $self->driver),
        _optional_pair('user',      $self->username),
        _optional_pair('pass',      $psw_expression),
        _optional_pair('host',      $self->host),
        _optional_pair('port',      $self->port),
        _optional_pair('dbname',    $self->dbname),

        'conn_params' => {
            _optional_pair('disconnect_when_inactive',  $self->disconnect_when_inactive),
            _optional_pair('wait_timeout',              $self->wait_timeout),
            _optional_pair('reconnect_when_lost',       $self->reconnect_when_lost),
        },
    };

    return $url_hash;
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

    return Bio::EnsEMBL::Hive::Utils::URL::hash_to_url( $self->to_url_hash( $psw_env_var_name ) );
}


sub connect {       # a wrapper that imitates CSMA/CD protocol's incremental backoff-and-retry approach
    my $self        = shift @_;

    my $attempts    = 9;
    my $sleep_sec   = 30;
    my $retval;

    foreach my $attempt (1..$attempts) {
        eval {
            $retval = $self->SUPER::connect( @_ );
            1;
        } or do {
            if( ($@ =~ /Could not connect to database.+?failed: Too many connections/s)                             # problem on server side (configured with not enough connections)
             or ($@ =~ /Could not connect to database.+?failed: Can't connect to \w+? server on '.+?' \(99\)/s)     # problem on client side (cooling down period after a disconnect)
             or ($@ =~ /Could not connect to database.+?failed: Can't connect to \w+? server on '.+?' \(110\)/s)    # problem on server side ("Connection timed out"L the server is temporarily dropping connections until it reaches a reasonable load)
             or ($@ =~ /Could not connect to database.+?failed: Lost connection to MySQL server at 'reading authorization packet', system error: 0/s)     # problem on server side (server too busy ?)
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

            if( ($@ =~ /Deadlock found when trying to get lock; try restarting transaction/)                        # MySQL error
             or ($@ =~ /Lock wait timeout exceeded; try restarting transaction/)                                    # MySQL error
            ) {

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
                if ($driver eq 'mysql') {
                    $sqlcmd = "$1 \`$dbname\`" unless $2;
                } else {
                    $sqlcmd = "$1 $dbname" unless $2;
                }
                $dbname = '';
            }
        } elsif($sqlcmd =~ /(CREATE\s+DATABASE(?:\s+IF\s+NOT\s+EXISTS)?\s*?)(?:\s+(\w+))?/i ) {
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
                if ($driver eq 'mysql') {
                    $sqlcmd = "$1 \`$dbname\`" unless $2;
                } else {
                    $sqlcmd = "$1 $dbname" unless $2;
                }
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

        push @cmd, ('env', 'MYSQL_PWD='.$hidden_password)  if ($self->password);
        push @cmd, $executable;
        push @cmd, @$prepend                        if ($prepend && @$prepend);
        push @cmd, '--host='.$self->host            if $self->host;
        push @cmd, '--port='.$self->port            if $self->port;
        push @cmd, '--user='.$self->username        if $self->username;
#        push @cmd, '--password='.$hidden_password   if $self->password;
        push @cmd, ('-e', $sqlcmd)                  if $sqlcmd;
        push @cmd, $dbname                          if $dbname;

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


=head2 run_in_transaction

    Description : Wrapper that first sets AutoCommit to 0, runs some user code, and at the end issues a commit() / rollback()
                  It also has to temporarily set disconnect_when_inactive() to 1 because a value of 0 would cause the
                  DBConnection object to disconnect early, which would rollback the transaction.
                  NB: This is essentially a trimmed copy of Ensembl's Utils::SqlHelper::transaction()

=cut

sub run_in_transaction {
    my ($self, $callback) = @_;

    # Save the original value of disconnect_when_inactive()
    my $original_dwi = $self->disconnect_when_inactive();
    $self->disconnect_when_inactive(0);

    $self->reconnect() unless $self->db_handle()->ping();

    # Save the original value of "AutoCommit"
    my $original_ac = $self->db_handle()->{'AutoCommit'};
    $self->db_handle()->{'AutoCommit'} = 0;

    my $result;
    eval {
        $result = $callback->();
        # FIXME: does this work if the "MySQL server has gone away" ?
        $self->db_handle()->commit();
    };
    my $error = $@;

    #If there is an error then we apply rollbacks
    if($error) {
        eval { $self->db_handle()->rollback(); };
    }

    # Restore the original values
    $self->db_handle()->{'AutoCommit'} = $original_ac;
    $self->disconnect_when_inactive($original_dwi);

    die "ABORT: Transaction aborted because of error: ${error}" if $error;
    return $result;
}


=head2 has_write_access

  Example     : my $can_do = $dbc->has_write_access();
  Description : Tells whether the underlying database connection has write access to the database
  Returntype  : Boolean
  Exceptions  : none
  Caller      : general
  Status      : Stable

=cut

sub has_write_access {
    my $self = shift;
    if ($self->driver eq 'mysql') {
        my $user_entries =  $self->selectall_arrayref('SELECT Insert_priv, Update_priv, Delete_priv FROM mysql.user WHERE user = ?', undef, $self->username);
        my $has_write_access_from_some_host = 0;
        foreach my $entry (@$user_entries) {
            $has_write_access_from_some_host ||= !scalar(grep {$_ eq 'N'} @$entry);
        }
        return $has_write_access_from_some_host;
    } else {
        # TODO: implement this for other drivers
        return 1;
    }
}

=head2 requires_write_access

  Example     : $dbc->requires_write_access();
  Description : See Exceptions
  Returntype  : none
  Exceptions  : Throws if the current user hasn't write access to the database
  Caller      : general
  Status      : Stable

=cut

sub requires_write_access {
    my $self = shift;
    unless ($self->has_write_access) {
        die sprintf("It appears that %s doesn't have INSERT/UPDATE/DELETE privileges on this database (%s). Please check the credentials\n", $self->username, $self->dbname);
    }
}


1;

