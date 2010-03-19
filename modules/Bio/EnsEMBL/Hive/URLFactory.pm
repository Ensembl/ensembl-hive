# Perl module for Bio::EnsEMBL::Hive::URLFactory
#
# Date of creation: 22.03.2004
# Original Creator : Jessica Severin <jessica@ebi.ac.uk>
#
# Copyright EMBL-EBI 2004
#
# You may distribute this module under the same terms as perl itself

=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::URLFactory

=head1 SYNOPSIS

  $someObj = Bio::EnsEMBL::Hive::URLFactory->fetch($url_string);
  Bio::EnsEMBL::Hive::URLFactory->store($object);

=head1 DESCRIPTION  

  Module to parse URL strings and return EnsEMBL objects be them
  DBConnections, DBAdaptors, or specifics like Analysis, Member, Gene, ....

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _

=cut


# global instance to cache connection to limit the number of open DB connections
my $_URLFactory_global_instance;

package Bio::EnsEMBL::Hive::URLFactory;

use strict;
use Switch;
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;

use Bio::EnsEMBL::Hive::Extensions;
use Bio::EnsEMBL::DBSQL::AnalysisAdaptor;
use Bio::EnsEMBL::DBSQL::DBConnection;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

sub new
{
  my ($class, @args) = @_;
  unless($_URLFactory_global_instance) {
    $_URLFactory_global_instance = bless {}, $class;
    $_URLFactory_global_instance->_load_aliases;
  }
  return $_URLFactory_global_instance;
}

sub DESTROY {
  my ($obj) = @_;
  #print("Bio::EnsEMBL::Hive::URLFactory::DESTROY - cleanup connections\n");
  foreach my $key (keys(%{$_URLFactory_global_instance})) {
    $_URLFactory_global_instance->{$key} = undef;
  }
}

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
  my $type = shift;
  
  return undef unless($url);

  new Bio::EnsEMBL::Hive::URLFactory;  #make sure global instance is created

  my ($dba, $path) = $class->_get_db_connection($url, $type);  

  return $dba unless($path);
  
  if((my $p=index($path, "?")) != -1) {
    my $table = substr($path,0, $p);
    my $query = substr($path,$p+1,length($path));

    if($table eq 'analysis') {
      #my $adaptor = new Bio::EnsEMBL::DBSQL::AnalysisAdaptor($dba);
      my $adaptor = $dba->get_AnalysisAdaptor;
      return $adaptor->fetch_by_url_query($query);
    }
    if($table eq 'analysis_job') {
      #my $adaptor = new Bio::EnsEMBL::DBSQL::AnalysisAdaptor($dba);
      my $adaptor = $dba->get_AnalysisJobAdaptor;
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


############################
#
# Internals
#
############################

sub _get_db_connection
{
  #e.g. mysql://ensadmin:<pass>@ecs2:3362/compara_hive_23c
  #e.g. mysql://ensadmin:<pass>@ecs2:3362/ensembl_compara_22_1;type=compara
  #e.g. mysql://ensadmin:<pass>@ecs2:3362/ensembl_core_homo_sapiens_22_34;type=core
  my $class = shift;
  my $url = shift;
  my $type = shift;

  return undef unless($url);

  my $user = 'ensro';
  my $pass = '';
  my $host = '';
  my $port = 3306;
  my $dbname = undef;
  my $path = '';
  my $module = "Bio::EnsEMBL::Hive::DBSQL::DBAdaptor";
  $type   = 'hive' unless($type);
  my $discon = 0;
  my ($p, $p2, $p3);

  #print("FETCH $url\n");
  return undef unless $url =~ s/^mysql\:\/\///;
  #print ("url=$url\n");
  $p = index($url, "/");
  return undef if($p == -1);

  my $conn   = substr($url, 0, $p);
  $dbname    = substr($url, $p+1, length($url));
  my $params = undef;
  if(($p2=index($dbname, ";")) != -1) {
    $params = substr($dbname, $p2+1, length($dbname));
    $dbname = substr($dbname, 0, $p2);
  }
  if(($p2=index($dbname, "/")) != -1) {
    $path   = substr($dbname, $p2+1, length($dbname));
    $dbname = substr($dbname, 0, $p2);
  }
  while($params) {
    my $token = $params;
    if(($p2=rindex($params, ";")) != -1) {
      $token  = substr($params, 0, $p2);
      $params = substr($params, $p2+1, length($params));
    } else { $params= undef; }
    if($token =~ /type=(.*)/) {
      $type = $1;
    }
    if($token =~ /discon=(.*)/) {
      $discon = $1;
    }
  }

  #print("  conn=$conn\n  dbname=$dbname\n  path=$path\n");

  my($hostPort, $userPass);
  if(($p=rindex($conn, "@")) != -1) {
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
  
  ($host,$port) = $_URLFactory_global_instance->_check_alias($host,$port);

  my $connectionKey = "$user:$pass\@$host:$port/$dbname;$type";
  my $dba;
  #print("key=$connectionKey\n");
  $dba = $_URLFactory_global_instance->{$connectionKey};
  return ($dba,$path) if($dba);
  
  #print("CONNECT via\n  user=$user\n  pass=$pass\n  host=$host\n  port=$port\n  dbname=$dbname\n  path=$path\n  type=$type\n  discon=$discon\n");
  switch ($type) {
    case 'core' { $module = "Bio::EnsEMBL::DBSQL::DBAdaptor"; }
    case 'pipeline' { $module = "Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor"; }
    case 'compara' {
      eval "require Bio::EnsEMBL::Compara::DBSQL::DBAdaptor";
      $module = "Bio::EnsEMBL::Compara::DBSQL::DBAdaptor"; 
    }
  }

  $dba = "$module"->new (
          -disconnect_when_inactive => $discon,
          -driver => 'mysql',
          -user   => $user,
          -pass   => $pass,
          -host   => $host,
          -port   => $port,
          -dbname => $dbname,
          -species => $dbname
	  );

  $_URLFactory_global_instance->{$connectionKey} = $dba;
  return ($dba,$path);

}

sub _load_aliases {
  my $self = shift;

  $self->{'_aliases'} = {};

  my $alias_file = $ENV{'HOME'} . "/.hive_url_alias";
  return unless(-e $alias_file);
  #print("found ALIAS file $alias_file\n");
  
  open (ALIASFP,$alias_file) || return;
  while(<ALIASFP>) {
    chomp;
    my($from, $to) = split(/\s+/);
    $self->{'_aliases'}->{$from} = $to;
  }
  close(ALIASFP);
}


sub _check_alias {
  my $self = shift;
  my $host = shift;
  my $port = shift;

  my $key = "$host:$port";
  my $alias = $self->{'_aliases'}->{$key};
  return ($host,$port) unless($alias);
  
  ($host,$port) = split(/:/, $alias);
  #print("translate alias $key into $host : $port\n");
  return ($host,$port);
}


1;
