# Perl module for Bio::EnsEMBL::Hive::URLFactory
#
# Date of creation: 22.03.2004
# Original Creator : Jessica Severin <jessica@ebi.ac.uk>
#
# Copyright EMBL-EBI 2004
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME
  Bio::EnsEMBL::Hive::URLFactory

=head1 SYNOPSIS
  $someObj = Bio::EnsEMBL::Hive::URLFactory->fetch($url_string);
  Bio::EnsEMBL::Hive::URLFactory->store($object);

=head1 DESCRIPTION  
  Module to parse URL strings and return EnsEMBL objects be them
  DBConnections, DBAdaptors, or specifics like Analysis, Member, Gene, ....

=head1 CONTACT
  Contact Jessica Severin on EnsEMBL::Hive implemetation/design detail: jessica@ebi.ac.uk
  Contact Ewan Birney on EnsEMBL in general: birney@sanger.ac.uk

=head1 APPENDIX
  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _
=cut


# Let the code begin...

# global variable to cache connection to limit the number of open DB connections
my $_URLFactory_connections = {};

package Bio::EnsEMBL::Hive::URLFactory;

use strict;
use Bio::EnsEMBL::Hive::Extensions;
use Bio::EnsEMBL::DBSQL::AnalysisAdaptor;
use Bio::EnsEMBL::DBSQL::DBConnection;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

our @ISA = qw(Bio::EnsEMBL::Root);


=head2 fetch
  Arg[1]     : string
  Example    : my $object = Bio::EnsEMBL::Hive::URLFactory->fetch($url);
  Description: parses URL, connects to appropriate DBConnection, determines
               appropriate Adaptor, fetches object
  Returntype : blessed instance of the object refered to or a
               Bio::EnsEMBL::DBSQL::DBConnection if simple URL
  Exceptions : none
  Caller     : ?
=cut
sub fetch
{
  my $class = shift;
  my $url = shift;
  
  return undef unless($url);

  my ($dbc, $path) = $class->_get_db_connection($url);

  return $dbc unless($path);
  
  if((my $p=index($path, "?")) != -1) {
    my $table = substr($path,0, $p);
    my $query = substr($path,$p+1,length($path));

    if($table eq 'analysis') {
      #my $adaptor = new Bio::EnsEMBL::DBSQL::AnalysisAdaptor($dbc);
      my $adaptor = $dbc->get_analysisAdaptor;
      return $adaptor->fetch_by_url_query($query);
    }
  }

  return undef;
}

=head2 store
  Title   : store
  Usage   : Bio::EnsEMBL::Hive::URLFactory->store($object);
  Function: Stores an object instance into a database
  Returns : -
  Args[1] : a blessed instance of an object
=cut
sub store {
  my ( $class, $object ) = @_;
  #print("\nURLFactory->store()\n");
  return undef;
}


sub cleanup {
  my $class = shift;
  foreach my $key (keys(%{$_URLFactory_connections})) {
    $_URLFactory_connections->{$key} = undef;
  }
}

############################
#
# Internals
#
############################

sub _get_db_connection
{
  my $class = shift;
  my $url = shift;

  return undef unless($url);

  my $user = 'ensro';
  my $pass = '';
  my $host = '';
  my $port = 3306;
  my $dbname = undef;
  my $path = undef;
  my ($p, $p2, $p3);

  #print("FETCH $url\n");
  return undef unless $url =~ s/^mysql\:\/\///;
  #print ("url=$url\n");
  $p = index($url, "/");
  return undef if($p == -1);

  my $conn   = substr($url, 0, $p);
  $dbname    = substr($url, $p+1, length($url));
  $p2        = index($dbname, "/");
  if($p2 != -1) {
    $path   = substr($dbname, $p2+1, length($dbname));
    $dbname = substr($dbname, 0, $p2);
  }

  #print("  conn=$conn\n  dbname=$dbname\n  path=$path\n");

  my($hostPort, $userPass);
  if(($p=index($conn, "@")) != -1) {
    $userPass = substr($conn,0, $p);
    $hostPort = substr($conn,$p+1,length($conn));

    if(($p2 = index($userPass, ':')) != -1) {
      $pass = substr($userPass, $p2+1, length($userPass));
      $user = substr($userPass, 0, $p2);
    } elsif(defined($userPass)) { $user = $userPass; }
  }
  else {
    $hostPort = $conn;
  }
  if(($p3 = index($hostPort, ':')) != -1) {
    $port = substr($hostPort, $p3+1, length($hostPort)) ;
    $host = substr($hostPort, 0, $p3);
  } else { $host=$hostPort; }

  return undef unless($host and $dbname);

  my $connectionKey = "$user:$pass\@$host:$port/$dbname";
  my $dbc;
  #print("key=$connectionKey\n");
  $dbc = $_URLFactory_connections->{$connectionKey};
  return ($dbc,$path) if($dbc);
  
  #print("CONNECT via  user=$user\n  pass=$pass\n  host=$host\n  port=$port\n  dbname=$dbname\n  path=$path\n");
  $dbc = new Bio::EnsEMBL::Hive::DBSQL::DBAdaptor(
          -disconnect_when_inactive => 1,
          -driver => 'mysql',
          -user   => $user,
          -pass   => $pass,
          -host   => $host,
          -port   => $port,
          -dbname => $dbname);

  $_URLFactory_connections->{$connectionKey} = $dbc;
  return ($dbc,$path);

}

1;
