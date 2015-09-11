=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <dev@ensembl.org>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk@ensembl.org>.

=cut

=head1 NAME

Bio::EnsEMBL::Hive::DBSQL::CoreDBConnection

=head1 SYNOPSIS

  $dbc = Bio::EnsEMBL::DBSQL::DBConnection->new(
    -user   => 'anonymous',
    -dbname => 'homo_sapiens_core_20_34c',
    -host   => 'ensembldb.ensembl.org',
    -driver => 'mysql',
  );

  # SQL statements should be created/executed through this modules
  # prepare() and do() methods.

  $sth = $dbc->prepare("SELECT something FROM yourtable");

  $sth->execute();

  # do something with rows returned ...

  $sth->finish();

=head1 DESCRIPTION

This class is a wrapper around DBIs datbase handle.  It provides some
additional functionality such as the ability to automatically disconnect
when inactive and reconnect when needed.

Generally this class will be used through one of the object adaptors or
the Bio::EnsEMBL::Registry and will not be instantiated directly.

=head1 METHODS

=cut


package Bio::EnsEMBL::Hive::DBSQL::CoreDBConnection;

use strict;
use warnings;

use DBI;
use Bio::EnsEMBL::Hive::DBSQL::StatementHandle;

use Bio::EnsEMBL::Hive::Utils ('throw');


use vars qw(@ISA);      # If Ensembl Core code is available, inherit from its' DBConnection for compatibility.
BEGIN {
    if (eval { require Bio::EnsEMBL::DBSQL::DBConnection; 1 }) {
        @ISA = ('Bio::EnsEMBL::DBSQL::DBConnection');
    } else {
        @ISA = ();
    }
}


=head2 new

  Arg [DBNAME] : (optional) string
                 The name of the database to connect to.
  Arg [HOST] : (optional) string
               The domain name of the database host to connect to.  
               'localhost' by default. 
  Arg [USER] : string
               The name of the database user to connect with 
  Arg [PASS] : (optional) string
               The password to be used to connect to the database
  Arg [PORT] : (optional) int
               The port to use when connecting to the database
               3306 by default if the driver is mysql.
  Arg [DRIVER] : (optional) string
                 The type of database driver to use to connect to the DB
                 mysql by default.
  Arg [DBCONN] : (optional)
                 Open another handle to the same database as another connection
                 If this argument is specified, no other arguments should be
                 specified.
  Arg [DISCONNECT_WHEN_INACTIVE]: (optional) boolean
                 If set to true, the database connection will be disconnected
                 everytime there are no active statement handles. This is
                 useful when running a lot of jobs on a compute farm
                 which would otherwise keep open a lot of connections to the
                 database.  Database connections are automatically reopened
                 when required.Do not use this option together with RECONNECT_WHEN_LOST.
  Arg [WAIT_TIMEOUT]: (optional) integer
                 Time in seconds for the wait_timeout to happen. Time after which
                 the connection is deleted if not used. By default this is 28800 (8 hours)
                 on most systems. 
                 So set this to greater than this if your connection are getting deleted.
                 Only set this if you are having problems and know what you are doing.
  Arg [RECONNECT_WHEN_LOST]: (optional) boolean
                 In case you're reusing the same database connection, i.e. DISCONNECT_WHEN_INACTIVE is 
                 set to false and running a job which takes a long time to process (over 8hrs), 
                 which means that the db connection may be lost, set this option to true. 
                 On each prepare or do statement the db handle will be pinged and the database 
                 connection will be reconnected if it's lost.
                
  Example    : $dbc = Bio::EnsEMBL::DBSQL::DBConnection->new
                  (-user   => 'anonymous',
                   -dbname => 'homo_sapiens_core_20_34c',
                   -host   => 'ensembldb.ensembl.org',
                   -driver => 'mysql');

  Description: Constructor for a Database Connection. Any adaptors that require
               database connectivity should inherit from this class.
  Returntype : Bio::EnsEMBL::DBSQL::DBConnection
  Exceptions : thrown if USER or DBNAME are not specified, or if the database
               cannot be connected to.
  Caller     : Bio::EnsEMBL::Utils::ConfigRegistry ( for newer code using the registry)
               Bio::EnsEMBL::DBSQL::DBAdaptor        ( for old style code)
  Status     : Stable

=cut

sub new {
    my $class = shift @_;
    my %flags = @_;

    my ($driver, $user, $password, $host, $port, $dbname,
        $dbconn, $disconnect_when_inactive, $wait_timeout, $reconnect_when_lost)
     = @flags{qw(-driver -user -pass -host -port -dbname -dbconn
                 -disconnect_when_inactive -wait_timeout -reconnect_when_lost)};

    my $self = {};
    bless $self, $class;

  if($dbconn) {
    if($dbname || $host || $driver || $password || $port || $disconnect_when_inactive || $reconnect_when_lost) {
      throw("Cannot specify other arguments when -DBCONN argument used.");
    }

    $self->driver($dbconn->driver());
    $self->host($dbconn->host());
    $self->port($dbconn->port());
    $self->username($dbconn->username());
    $self->password($dbconn->password());
    $self->dbname($dbconn->dbname());

    if($dbconn->disconnect_when_inactive()) {
      $self->disconnect_when_inactive(1);
    }
  } else {
    $driver ||= 'mysql';
    
    if($driver eq 'mysql') {
        $user || throw("-USER argument is required.");
        $host ||= 'mysql';
        if(!defined($port)){
            $port   = 3306;
            if($host eq "ensembldb.ensembl.org"){
                if( $dbname =~ /\w+_\w+_\w+_(\d+)/){
                    if($1 >= 48){
                        $port = 5306;
                    }
                }
            }
        }
    } elsif($driver eq 'pgsql') {
        if(!defined($port)){
            $port   = 5432;
        }
    }

    $self->driver($driver);
    $self->host( $host );
    $self->port($port);
    $self->username( $user );
    $self->password( $password );
    $self->dbname( $dbname );
    $self->wait_timeout($wait_timeout);

    if($disconnect_when_inactive) {
      $self->disconnect_when_inactive($disconnect_when_inactive);
    }
    if($reconnect_when_lost) {
      $self->reconnect_when_lost($reconnect_when_lost);
    }
  }

#  if(defined $dnadb) {
#    $self->dnadb($dnadb);
#  }
  return $self;
}


=head2 connect

  Example    : $dbcon->connect()
  Description: Connects to the database using the connection attribute 
               information.
  Returntype : none
  Exceptions : none
  Caller     : new, db_handle
  Status     : Stable

=cut

sub connect {
  my ($self) = @_;

  if ( $self->connected() ) { return }

  $self->connected(1);

  if ( defined( $self->db_handle() ) and $self->db_handle()->ping() ) {
    warn(   "unconnected db_handle is still pingable, "
             . "reseting connected boolean\n" );
  }

  my ( $dsn, $dbh );
  my $dbname = $self->dbname();

  if ( $self->driver() eq "Oracle" ) {

    $dsn = "DBI:Oracle:";

    eval {
      $dbh = DBI->connect( $dsn,
                           sprintf( "%s@%s",
                                    $self->username(), $dbname ),
                           $self->password(),
                           { 'RaiseError' => 1, 'PrintError' => 0 } );
    };

  } elsif ( $self->driver() eq "ODBC" ) {

    $dsn = sprintf( "DBI:ODBC:%s", $self->dbname() );

    eval {
      $dbh = DBI->connect( $dsn,
                           $self->username(),
                           $self->password(), {
                             'LongTruncOk'     => 1,
                             'LongReadLen'     => 2**16 - 8,
                             'RaiseError'      => 1,
                             'PrintError'      => 0,
                             'odbc_cursortype' => 2 } );
    };

  } elsif ( $self->driver() eq "Sybase" ) {
    my $dbparam = ($dbname) ? ";database=${dbname}" : q{};

    $dsn = sprintf( "DBI:Sybase:server=%s%s;tdsLevel=CS_TDS_495",
                    $self->host(), $dbparam );

    eval {
      $dbh = DBI->connect( $dsn,
                           $self->username(),
                           $self->password(), {
                             'LongTruncOk' => 1,
                             'RaiseError'  => 1,
                             'PrintError'  => 0 } );
    };

  } elsif ( lc( $self->driver() ) eq 'sqlite' ) {

    throw "We require a dbname to connect to a SQLite database"
      if !$dbname;

    $dsn = sprintf( "DBI:SQLite:%s", $dbname );

    eval {
      $dbh = DBI->connect( $dsn, '', '', { 'RaiseError' => 1, } );
    };

  } else {

    my $dbparam = ($dbname) ? "database=${dbname};" : q{};

    my $driver = $self->driver();
    $driver = 'Pg' if($driver eq 'pgsql');

    $dsn = sprintf( "DBI:%s:%shost=%s;port=%s",
                    $driver, $dbparam,
                    $self->host(),   $self->port() );

    eval {
      $dbh = DBI->connect( $dsn, $self->username(), $self->password(),
                           { 'RaiseError' => 1 } );
    };
  }
  my $error = $@;

  if ( !$dbh || $error || !$dbh->ping() ) {
    warn(   "Could not connect to database "
          . $self->dbname()
          . " as user "
          . $self->username()
          . " using [$dsn] as a locator:\n"
          . $error );

    $self->connected(0);

    throw(   "Could not connect to database "
           . $self->dbname()
           . " as user "
           . $self->username()
           . " using [$dsn] as a locator:\n"
           . $error );
  }

  $self->db_handle($dbh);

  if ( $self->wait_timeout() ) {
    my $driver = $self->driver();

    if( $driver eq 'mysql' ) {
        $dbh->do( "SET SESSION wait_timeout=" . $self->wait_timeout() );
    } else {
        warn "Don't know how to set the wait_timeout for '$driver' driver, skipping.\n";
    }
  }

  #print("CONNECT\n");
} ## end sub connect


=head2 connected

  Example    : $dbcon->connected()
  Description: Boolean which tells if DBConnection is connected or not.
               State is set internally, and external processes should not alter state.
  Returntype : undef or 1
  Exceptions : none
  Caller     : db_handle, connect, disconnect_if_idle, user processes
  Status     : Stable

=cut

sub connected {
  my $self = shift;

  # Use the process id ($$) as part of the key for the connected flag.
  # This forces the opening of another connection in a forked subprocess.
  $self->{'connected'.$$} = shift if(@_);
  return $self->{'connected'.$$};
}

sub disconnect_count {
  my $self = shift;
  return $self->{'disconnect_count'} = shift if(@_);
  $self->{'disconnect_count'}=0 unless(defined($self->{'disconnect_count'}));
  return $self->{'disconnect_count'};
}

sub wait_timeout{
  my($self, $arg ) = @_;

  (defined $arg) &&
    ($self->{_wait_timeout} = $arg );

  return $self->{_wait_timeout};

}

sub query_count {
  my $self = shift;
  return $self->{'_query_count'} = shift if(@_);
  $self->{'_query_count'}=0 unless(defined($self->{'_query_count'}));
  return $self->{'_query_count'};
}

=head2 equals

  Example    : warn 'Same!' if($dbc->equals($other_dbc));
  Description: Equality checker for DBConnection objects
  Returntype : boolean
  Exceptions : none
  Caller     : new
  Status     : Stable

=cut

  
sub equals {
  my ( $self, $dbc ) = @_;
  return 0 if ! defined $dbc;
  my $return = 0;
  my $undef_str = q{!-undef-!};
  my $undef_num = -1;

  $return = 1 if  ( 
    (($self->host() || $undef_str)      eq ($dbc->host() || $undef_str)) &&
    (($self->dbname() || $undef_str)    eq ($dbc->dbname() || $undef_str)) &&
    (($self->port() || $undef_num)      == ($dbc->port() || $undef_num)) &&
    (($self->username() || $undef_str)  eq ($dbc->username() || $undef_str)) &&
    ($self->driver() eq $dbc->driver())
  );
  
  return $return;
}

=head2 driver

  Arg [1]    : (optional) string $arg
               the name of the driver to use to connect to the database
  Example    : $driver = $db_connection->driver()
  Description: Getter / Setter for the driver this connection uses.
               Right now there is no point to setting this value after a
               connection has already been established in the constructor.
  Returntype : string
  Exceptions : none
  Caller     : new
  Status     : Stable

=cut

sub driver {
  my($self, $arg ) = @_;

  (defined $arg) &&
    ($self->{_driver} = $arg );
  return $self->{_driver};
}


=head2 port

  Arg [1]    : (optional) int $arg
               the TCP or UDP port to use to connect to the database
  Example    : $port = $db_connection->port();
  Description: Getter / Setter for the port this connection uses to communicate
               to the database daemon.  There currently is no point in 
               setting this value after the connection has already been 
               established by the constructor.
  Returntype : string
  Exceptions : none
  Caller     : new
  Status     : Stable

=cut

sub port {
  my ( $self, $value ) = @_;

  if ( defined($value) ) {
    $self->{'_port'} = $value;
  }

  return $self->{'_port'};
}


=head2 dbname

  Arg [1]    : (optional) string $arg
               The new value of the database name used by this connection. 
  Example    : $dbname = $db_connection->dbname()
  Description: Getter/Setter for the name of the database used by this 
               connection.  There is currently no point in setting this value
               after the connection has already been established by the 
               constructor.
  Returntype : string
  Exceptions : none
  Caller     : new
  Status     : Stable

=cut

sub dbname {
  my ($self, $arg ) = @_;
  ( defined $arg ) &&
    ( $self->{_dbname} = $arg );
  $self->{_dbname};
}


=head2 username

  Arg [1]    : (optional) string $arg
               The new value of the username used by this connection. 
  Example    : $username = $db_connection->username()
  Description: Getter/Setter for the username used by this 
               connection.  There is currently no point in setting this value
               after the connection has already been established by the 
               constructor.
  Returntype : string
  Exceptions : none
  Caller     : new
  Status     : Stable

=cut

sub username {
  my ($self, $arg ) = @_;
  ( defined $arg ) &&
    ( $self->{_username} = $arg );
  $self->{_username};
}

=head2 user

  Arg [1]    : (optional) string $arg
               The new value of the username used by this connection. 
  Example    : $user = $db_connection->user()
  Description: Convenience alias for the username method
  Returntype : String

=cut

sub user {
  my ($self, $arg) = @_;
  return $self->username($arg);
}


=head2 host

  Arg [1]    : (optional) string $arg
               The new value of the host used by this connection. 
  Example    : $host = $db_connection->host()
  Description: Getter/Setter for the domain name of the database host use by 
               this connection.  There is currently no point in setting 
               this value after the connection has already been established 
               by the constructor.
  Returntype : string
  Exceptions : none
  Caller     : new
  Status     : Stable

=cut

sub host {
  my ($self, $arg ) = @_;
  ( defined $arg ) &&
    ( $self->{_host} = $arg );
  $self->{_host};
}

=head2 hostname

  Arg [1]    : (optional) string $arg
               The new value of the host used by this connection. 
  Example    : $hostname = $db_connection->hostname()
  Description: Convenience alias for the host method
  Returntype : String

=cut

sub hostname {
  my ($self, $arg) = @_;
  return $self->host($arg);
}


=head2 password

  Arg [1]    : (optional) string $arg
               The new value of the password used by this connection.
  Example    : $host = $db_connection->password()
  Description: Getter/Setter for the password of to use for this
               connection.  There is currently no point in setting
               this value after the connection has already been
               established by the constructor.
  Returntype : string
  Exceptions : none
  Caller     : new
  Status     : Stable

=cut

sub password {
  my ( $self, $arg ) = @_;

  if ( defined($arg) ) {
    # Use an anonymous subroutine that will return the password when
    # invoked.  This will prevent the password from being accidentally
    # displayed when using e.g. Data::Dumper on a structure containing
    # one of these objects.

    $self->{_password} = sub { $arg };
  }

  return ( ref( $self->{_password} ) && &{ $self->{_password} } ) || '';
}

=head2 pass

  Arg [1]    : (optional) string $arg
               The new value of the password used by this connection. 
  Example    : $pass = $db_connection->pass()
  Description: Convenience alias for the password method
  Returntype : String

=cut

sub pass {
  my ($self, $arg) = @_;
  return $self->password($arg);
}

=head2 disconnect_when_inactive

  Arg [1]    : (optional) boolean $newval
  Example    : $dbc->disconnect_when_inactive(1);
  Description: Getter/Setter for the disconnect_when_inactive flag.  If set
               to true this DBConnection will continually disconnect itself
               when there are no active statement handles and reconnect as
               necessary.  Useful for farm environments when there can be
               many (often inactive) open connections to a database at once.
  Returntype : boolean
  Exceptions : none
  Caller     : Pipeline
  Status     : Stable

=cut

sub disconnect_when_inactive {
  my ( $self, $value ) = @_;

  if ( defined($value) ) {
    $self->{'disconnect_when_inactive'} = $value;
    if ($value) {
      $self->disconnect_if_idle();
    }
  }

  return $self->{'disconnect_when_inactive'};
}


=head2 reconnect_when_lost

  Arg [1]    : (optional) boolean $newval
  Example    : $dbc->reconnect_when_lost(1);
  Description: Getter/Setter for the reconnect_when_lost flag.  If set
               to true the db handle will be pinged on each prepare or do statement 
               and the connection will be reestablished in case it's lost.
               Useful for long running jobs (over 8hrs), which means that the db 
               connection may be lost.
  Returntype : boolean
  Exceptions : none
  Caller     : Pipeline
  Status     : Stable

=cut

sub reconnect_when_lost {
  my ( $self, $value ) = @_;

  if ( defined($value) ) {
    $self->{'reconnect_when_lost'} = $value;
  }

  return $self->{'reconnect_when_lost'};
}



=head2 locator

  Arg [1]    : none
  Example    : $locator = $dbc->locator;
  Description: Constructs a locator string for this database connection
               that can, for example, be used by the DBLoader module
  Returntype : string
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut


sub locator {
  my ($self) = @_;

  return sprintf(
    "%s/host=%s;port=%s;dbname=%s;user=%s;pass=%s",
    ref($self),      $self->host(),     $self->port(),
    $self->dbname(), $self->username(), $self->password() );
}


=head2 db_handle

  Arg [1]    : DBI Database Handle $value
  Example    : $dbh = $db_connection->db_handle() 
  Description: Getter / Setter for the Database handle used by this
               database connection.
  Returntype : DBI Database Handle
  Exceptions : none
  Caller     : new, DESTROY
  Status     : Stable

=cut

sub db_handle {
   my $self = shift;

   # Use the process id ($$) as part of the key for the database handle
   # this makes this object fork safe.  fork() does not makes copies
   # of the open socket which creates problems when one of the forked
   # processes disconnects,
   return $self->{'db_handle'.$$} = shift if(@_);
   return $self->{'db_handle'.$$} if($self->connected);

   $self->connect();
   return $self->{'db_handle'.$$};
}


=head2 prepare

  Arg [1]    : string $string
               the SQL statement to prepare
  Example    : $sth = $db_connection->prepare("SELECT column FROM table");
  Description: Prepares a SQL statement using the internal DBI database handle
               and returns the DBI statement handle.
  Returntype : DBI statement handle
  Exceptions : thrown if the SQL statement is empty, or if the internal
               database handle is not present
  Caller     : Adaptor modules
  Status     : Stable

=cut

sub prepare {
   my ($self,@args) = @_;

   if( ! $args[0] ) {
     throw("Attempting to prepare an empty SQL query.");
   }

   #warn "SQL(".$self->dbname."): " . join(' ', @args) . "\n";
   if ( ($self->reconnect_when_lost()) and (!$self->db_handle()->ping()) ) { 
       $self->reconnect();
   }
   my $sth;
   eval {
       $sth = $self->db_handle->prepare(@args);
       1;
   } or do {
       throw( "FAILED_SQL(".$self->dbname."): " . join(' ', @args) );
   };

   # return an overridden statement handle that provides us with
   # the means to disconnect inactive statement handles automatically
   bless $sth, "Bio::EnsEMBL::Hive::DBSQL::StatementHandle";
   $sth->dbc($self);
   $sth->sql($args[0]);

   $self->query_count($self->query_count()+1);
   return $sth;
}

=head2 reconnect

  Example    : $dbcon->reconnect()
  Description: Reconnects to the database using the connection attribute 
               information if db_handle no longer pingable.
  Returntype : none
  Exceptions : none
  Caller     : new, db_handle
  Status     : Stable

=cut

sub reconnect {
  my ($self) = @_;
  $self->connected(undef);
  $self->db_handle(undef);
  $self->connect();
  return;
}


=head2 do

  Arg [1]    : string $string
               the SQL statement to prepare
  Example    : $sth = $db_connection->do("SELECT column FROM table");
  Description: Executes a SQL statement using the internal DBI database handle.
  Returntype : Result of DBI dbh do() method
  Exceptions : thrown if the SQL statement is empty, or if the internal
               database handle is not present.
  Caller     : Adaptor modules
  Status     : Stable

=cut

sub do {
   my ($self,$string, $attr, @bind_values) = @_;

   if( ! $string ) {
     throw("Attempting to do an empty SQL query.");
   }

   # warn "SQL(".$self->dbname."): $string";
   my $error;
   
   my $do_result = $self->work_with_db_handle(sub {
     my ($dbh) = @_;
     my $result = eval { $dbh->do($string, $attr, @bind_values) };
     $error = $@ if $@;
     return $result;
   });
   
   throw "Detected an error whilst executing statement '$string': $error" if $error;
 
   return $do_result;
}

=head2 work_with_db_handle

  Arg [1]    : CodeRef $callback
  Example    : my $q_t = $dbc->work_with_db_handle(sub { my ($dbh) = @_; return $dbh->quote_identifier('table'); });
  Description: Gives access to the DBI handle to execute methods not normally
               provided by the DBConnection interface
  Returntype : Any from callback
  Exceptions : If the callback paramater is not a CodeRef; all other 
               errors are re-thrown after cleanup.
  Caller     : Adaptor modules
  Status     : Stable

=cut

sub work_with_db_handle {
  my ($self, $callback) = @_;
  my $wantarray = wantarray;
  if( $self->reconnect_when_lost() && !$self->db_handle()->ping()) { 
    $self->reconnect();
  }
  my @results;
  eval {
    if($wantarray) { 
      @results = $callback->($self->db_handle())
    }
    elsif(defined $wantarray) {
      $results[0] = $callback->($self->db_handle());
    }
    else {
      $callback->($self->db_handle());
    }
  };
  my $original_error = $@;
  
  $self->query_count($self->query_count()+1);
  eval {
    if($self->disconnect_when_inactive()) {
      $self->disconnect_if_idle();
    }
  };
  if($@) {
    warn "Detected an error whilst attempting to disconnect the DBI handle: $@";
  }
  if($original_error) {
    throw "Detected an error when running DBI wrapper callback:\n$original_error";
  }
  
  if(defined $wantarray) {
    return ($wantarray) ? @results : $results[0];
  }
  return;
}

=head2 prevent_disconnect

  Arg[1]      : CodeRef $callback
  Example     : $dbc->prevent_disconnect(sub { $dbc->do('do something'); $dbc->do('something else')});
  Description : A wrapper method which prevents database disconnection for the
                duration of the callback. This is very useful if you need
                to make multiple database calls avoiding excessive database
                connection creation/destruction but still want the API
                to disconnect after the body of work. 
                
                The value of C<disconnect_when_inactive()> is set to 0 no
                matter what the original value was & after $callback has
                been executed. If C<disconnect_when_inactive()> was 
                already set to 0 then this method will be an effective no-op.
  Returntype  : None
  Exceptions  : Raised if there are issues with reverting the connection to its
                default state.
  Caller      : DBConnection methods
  Status      : Beta

=cut

sub prevent_disconnect {
  my ($self, $callback) = @_;
  my $original_dwi = $self->disconnect_when_inactive();
  $self->disconnect_when_inactive(0);
  eval { $callback->(); };
  my $original_error = $@;
  eval {
    $self->disconnect_when_inactive($original_dwi);    
  };
  if($@) {
    warn "Detected an error whilst attempting to reset disconnect_when_idle: $@";
  }
  if($original_error) {
    throw "Detected an error when running DBI wrapper callback:\n$original_error";
  }
  return;
}


=head2 disconnect_if_idle

  Arg [1]    : none
  Example    : $dbc->disconnect_if_idle();
  Description: Disconnects from the database if there are no currently active
               statement handles. 
               It is called automatically by the DESTROY method of the
               Bio::EnsEMBL::Hive::DBSQL::StatementHandle if the
               disconect_when_inactive flag is set.
               Users may call it whenever they want to disconnect. Connection will
               reestablish on next access to db_handle()
  Returntype : 1 or 0
               1=problem trying to disconnect while a statement handle was still active
  Exceptions : none
  Caller     : Bio::EnsEMBL::Hive::DBSQL::StatementHandle::DESTROY
               Bio::EnsEMBL::Hive::DBSQL::CoreDBConnection::do
  Status     : Stable

=cut

sub disconnect_if_idle {
  my $self = shift;

  return 0 if(!$self->connected());
  my $db_handle = $self->db_handle();
  return 0 unless(defined($db_handle));

  #printf("disconnect_if_idle : kids=%d activekids=%d\n",
  #       $db_handle->{Kids}, $db_handle->{ActiveKids});

  #If InactiveDestroy is set, don't disconnect.
  #To comply with DBI specification
  return 0 if($db_handle->{InactiveDestroy});

  #If any statement handles are still active, don't allow disconnection
  #In this case it is being called before a query has been fully processed
  #either by not reading all rows of data returned, or not calling ->finish
  #on the statement handle.  Don't disconnect, send warning
  if($db_handle->{ActiveKids} != 0) {
     warn("Problem disconnect : kids=",$db_handle->{Kids},
            " activekids=",$db_handle->{ActiveKids},"\n");
     return 1;
  }
  
  $db_handle->disconnect();
  $self->connected(undef);
  $self->disconnect_count($self->disconnect_count()+1);
  #print("DISCONNECT\n");
  $self->db_handle(undef);
  return 0;
}


1;

