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

use Bio::EnsEMBL::Utils::Exception;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DBSQL::DBConnection;
use Bio::EnsEMBL::DBSQL::AnalysisAdaptor;
use Bio::EnsEMBL::Pipeline::RunnableDB;
#use Bio::EnsEMBL::Analysis::RunnableDB;


=head2 Bio::EnsEMBL::Analysis::runnableDB

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

  #make copy of analysis ($self) to pass into the runnableDB
  #to insulate the infrastructure from any modification the runnableDB may
  #do to the analysis object
  my $copy_self = new Bio::EnsEMBL::Analysis;
  %$copy_self = %$self;
  
  $runnable =~ s/\//::/g;
  my $runobj = "$runnable"->new(-db       => $self->adaptor->db,
                                -input_id => '1',
                                -analysis => $self,
                                );
  print STDERR "Instantiated ".$runnable." runnabledb\n" if($self->{'verbose'});

  return $runobj
}


=head2 Bio::EnsEMBL::DBSQL::DBConnection::url

  Arg [1]    : none
  Example    : $url = $dbc->url;
  Description: Constructs a URL string for this database connection. Follows
               the format defined for FTP urls and adopted by
               
  Returntype : string of format  mysql://<user>:<pass>@<host>:<port>/<dbname>
  Exceptions : none
  Caller     : general

=cut

sub Bio::EnsEMBL::DBSQL::DBConnection::url
{
  my $self = shift;
  return undef unless($self->host and $self->port and $self->dbname);
  my $url = "mysql://";
  if($self->username) {
    $url .= $self->username;
    $url .= ":".$self->password if($self->password);
    $url .= "@";
  }
  $url .= $self->host .":". $self->port ."/" . $self->dbname;
  return $url;
}


=head2 Bio::EnsEMBL::Analysis::url

  Arg [1]    : none
  Example    : $url = $dbc->url;
  Description: Constructs a URL string for this database connection
               Follows the general URL rules.
  Returntype : string of format
               mysql://<user>:<pass>@<host>:<port>/<dbname>/analysis?logic_name=<name>
  Exceptions : none
  Caller     : general

=cut

sub Bio::EnsEMBL::Analysis::url
{
  my $self = shift;
  my $url;

  return undef unless($self->adaptor);
  $url = $self->adaptor->db->dbc->url;
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


=head2 Bio::EnsEMBL::Analysis::stats

  Arg [1]    : none
  Example    : $stats = $analysis->stats;
  Description: returns the AnalysisStats object associated with this Analysis
               object.  Does not cache, but pull from database by using the
               Analysis objects adaptor->db.
  Returntype : Bio::EnsEMBL::Hive::AnalysisStats object
  Exceptions : none
  Caller     : general

=cut

sub Bio::EnsEMBL::Analysis::stats
{
  my $self = shift;
  my $stats = undef;

  #not cached internally since I want it to always be in sync with the database
  #otherwise the user application would need to be aware of the sync state and send
  #explicit 'sync' calls.
  $stats = $self->adaptor->db->get_AnalysisStatsAdaptor->fetch_by_analysis_id($self->dbID);
  return $stats;
}

#######################################
# extensions to
# Bio::EnsEMBL::Pipeline::RunnableDB
#######################################

sub Bio::EnsEMBL::Pipeline::RunnableDB::reset_job
{
  my $self = shift;
  return 1;
}

=head2 Bio::EnsEMBL::Pipeline::RunnableDB::global_cleanup

  Arg [1]    : none
  Description: method which user RunnableDB can override if it needs to clean up
               any 'global within worker run time' files or data.
  Returntype : 1
  Exceptions : none
  Caller     : Bio::EnsEMBL::Hive::Worker

=cut

sub Bio::EnsEMBL::Pipeline::RunnableDB::global_cleanup
{
  my $self = shift;
  return 1;
}

=head2 Bio::EnsEMBL::Pipeline::RunnableDB::branch_code

  Arg [1]       : none
  Description   : method which user RunnableDB can override if it needs to return
                  a specific branch code.  Used by the dataflow rules to determine which
                  job to create/run next
  Returntype    : int (default 1)
  Exceptions    : none
  Caller        : Bio::EnsEMBL::Hive::Worker

=cut

sub Bio::EnsEMBL::Pipeline::RunnableDB::branch_code
{
  my $self = shift;
  $self->{'_branch_code'} = shift if(@_);
  $self->{'_branch_code'}=1 unless($self->{'_branch_code'});
  return $self->{'_branch_code'};
}

sub Bio::EnsEMBL::Pipeline::RunnableDB::analysis_job_id
{
  my $self = shift;
  $self->{'_analysis_job_id'} = shift if(@_);
  $self->{'_analysis_job_id'}=0 unless($self->{'_analysis_job_id'});
  return $self->{'_analysis_job_id'};
}

sub Bio::EnsEMBL::Pipeline::RunnableDB::debug {
  my $self = shift;
  $self->{'_debug'} = shift if(@_);
  $self->{'_debug'}=0 unless(defined($self->{'_debug'}));  
  return $self->{'_debug'};
}

#######################################
# extensions to
# Bio::EnsEMBL::Analysis::RunnableDB
#######################################

sub Bio::EnsEMBL::Analysis::RunnableDB::reset_job
{
  my $self = shift;
  return 1;
}

sub Bio::EnsEMBL::Analysis::RunnableDB::global_cleanup
{
  my $self = shift;
  return 1;
}

sub Bio::EnsEMBL::Analysis::RunnableDB::branch_code
{
  my $self = shift;
  $self->{'_branch_code'} = shift if(@_);
  $self->{'_branch_code'}=1 unless($self->{'_branch_code'});
  return $self->{'_branch_code'};
}

sub Bio::EnsEMBL::Analysis::RunnableDB::analysis_job_id
{
  my $self = shift;
  $self->{'_analysis_job_id'} = shift if(@_);
  $self->{'_analysis_job_id'}=0 unless($self->{'_analysis_job_id'});
  return $self->{'_analysis_job_id'};
}

sub Bio::EnsEMBL::Analysis::RunnableDB::debug {
  my $self = shift;
  $self->{'_debug'} = shift if(@_);
  $self->{'_debug'}=0 unless(defined($self->{'_debug'}));  
  return $self->{'_debug'};
}

#######################################
# top level functions
#######################################

sub main::encode_hash
{
  my $hash_ref = shift;

  return "" unless($hash_ref);

  my $hash_string = "{";
  my @keys = sort(keys %{$hash_ref});
  foreach my $key (@keys) {
    if(defined($hash_ref->{$key})) {
      $hash_string .= "'$key'=>'" . $hash_ref->{$key} . "',";
    }
  }
  $hash_string .= "}";

  return $hash_string;
}

1;

