#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME
  Bio::EnsEMBL::Hive::Extensions
=cut

=head1 SYNOPSIS
  Object categories to extend the functionality of existing classes
=cut

=head1 DESCRIPTION
=cut

=head1 CONTACT
  Contact Jessica Severin on EnsEMBL::Hive implemetation/design detail: jessica@ebi.ac.uk
  Contact Ewan Birney on EnsEMBL in general: birney@sanger.ac.uk
=cut

=head1 APPENDIX
  The rest of the documentation details each of the object methods. 
  Internal methods are usually preceded with a _
=cut

use strict;

use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DBSQL::DBConnection;
use Bio::EnsEMBL::DBSQL::AnalysisAdaptor;


=head2 runnableDB
  Arg [1]    : none
  Example    : $runnable_db = $analysis->runnableDB;
  Description: from the $analysis->module construct a runnableDB object
  Returntype : Bio::EnsEMBL::Pipeline::RunnableDB
  Exceptions : none
  Caller     : general
=cut
sub Bio::EnsEMBL::Analysis::runnableDB
{
  my $self = shift;  #self is an Analysis object

  return undef unless($self);
  die("self must be a [Bio::EnsEMBL::Analysis] not a [$self]")
    unless($self->isa('Bio::EnsEMBL::Analysis'));

  my $runnable;
  if($self->module =~ "Bio::") { $runnable = $self->module; }
  else { $runnable = "Bio::EnsEMBL::Pipeline::RunnableDB::".$self->module; }
  (my $file = $runnable) =~ s/::/\//g;
  require "$file.pm";
  print STDERR "creating runnable ".$file."\n" if($self->{'verbose'});

  $runnable =~ s/\//::/g;
  my $runobj = "$runnable"->new(-db       => $self->adaptor->db,
                                -input_id => '1',
                                -analysis => $self,
                                );
  print STDERR "Instantiated ".$runnable." runnabledb\n" if($self->{'verbose'});

  return $runobj
}


=head2 url
  Arg [1]    : none
  Example    : $url = $dbc->url;
  Description: Constructs a URL string for this database connection. Follows
               the format defined for FTP urls and adopted by
               
  Returntype : string of format  mysql://<user>:<pass>@<host>:<port>/<dbname>'
  Exceptions : none
  Caller     : general
=cut
sub Bio::EnsEMBL::DBSQL::DBConnection::url
{
  my $self = shift;
  return undef unless($self->host and $self->username and $self->password and $self->dbname);
  
  return "mysql:://". $self->username .":". $self->password
         ."@". $self->host .":". $self->port ."/" . $self->dbname;
}


=head2 url
  Arg [1]    : none
  Example    : $url = $dbc->URL;
  Description: Constructs a URL string for this database connection
               Follows the general URL rules.
  Returntype : string of format
               mysql://<user>:<pass>@<host>:<port>/<dbname>/analysis?logic_name=<name>'
  Exceptions : none
  Caller     : general
=cut
sub Bio::EnsEMBL::Analysis::url
{
  my $self = shift;
  my $url;

  return undef unless($self->adaptor);
  $url = $self->adaptor->url;
  $url .= "/analysis?logic_name=" . $self->logic_name;
  return $url;  
}


sub Bio::EnsEMBL::DBSQL::AnalysisAdaptor::fetch_by_url_query
{
  my $self = shift;
  my $query = shift;

  return undef unless($query);
  #print("Bio::EnsEMBL::DBSQL::AnalysisAdaptor::fetch_by_url_query : $query\n");

  if((my $p=index($query, "=")) != -1) {
    my $type = substr($query,0, $p);
    my $value = substr($query,$p+1,length($query));

    if($type eq 'logic_name') {
      return $self->fetch_by_logic_name($value);
    }
    if($type eq 'dbID') {
      return $self->fetch_by_dbID($value);
    }
  }
  return undef;

}

1;

