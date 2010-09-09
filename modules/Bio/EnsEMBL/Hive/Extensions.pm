#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::Extensions

=head1 SYNOPSIS

  Object categories to extend the functionality of existing classes

=head1 DESCRIPTION

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

  The rest of the documentation details each of the object methods. 
  Internal methods are usually preceded with a _

=cut


use strict;

use Bio::EnsEMBL::Utils::Exception;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DBSQL::DBConnection;
use Bio::EnsEMBL::Hive::URLFactory;
#use Bio::EnsEMBL::Pipeline::RunnableDB;
#use Bio::EnsEMBL::Analysis::RunnableDB;


=head2 Bio::EnsEMBL::Analysis::process

  Arg [1]    : none
  Example    : $process = $analysis->process;
  Description: from the $analysis->module construct a Process object
  Returntype : Bio::EnsEMBL::Hive::Process subclass 
  Exceptions : none
  Caller     : general

=cut

sub Bio::EnsEMBL::Analysis::process {
    my $self = shift;  #self is an Analysis object

  return undef unless($self);
  die("self must be a [Bio::EnsEMBL::Analysis] not a [$self]")
    unless($self->isa('Bio::EnsEMBL::Analysis'));

  throw("analysis ". $self->logic_name . " has an undefined analysis.module")
    unless($self->module);

  my $process_class;
  if($self->module =~ /::/) { $process_class = $self->module; }
  else { $process_class = "Bio::EnsEMBL::Pipeline::RunnableDB::".$self->module; }
  (my $file = $process_class) =~ s/::/\//g;
  require "$file.pm";
  print STDERR "creating runnable ".$file."\n" if($self->{'verbose'});

  $process_class =~ s/\//::/g;
  my $runobj = "$process_class"->new(
                                -db       => $self->adaptor->db,
                                -input_id => '1',
                                -analysis => $self,
                                );
  print STDERR "Instantiated ". $process_class. " runnabledb\n" if($self->{'verbose'});

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

=head2 Bio::EnsEMBL::Analysis::data

  Arg [1]    : none
  Example    : $stats = $analysis->data;
  Description: returns the analysis data associated with this Analysis
               object. The data is stored in the analysis_data table. 
               Does not cache, but pull from database by using the
               Analysis objects adaptor->db.
  Returntype : String 
  Exceptions : none
  Caller     : general

=cut

sub Bio::EnsEMBL::Analysis::data
{
  my $self = shift;
  my $data = "";

  my $analysis_data_id = eval($self->parameters)->{'analysis_data_id'};  
  unless ( $analysis_data_id) {  
    warning( " analysis_data_id undefined for analysis " .$self->logic_name. " in analysis_data table.") ; 
  }else {  
    $data  = $self->adaptor->db->get_AnalysisDataAdaptor->fetch_by_dbID($analysis_data_id) ; 
  }
  return $data;
}


#######################################
# extensions to
# Bio::EnsEMBL::Pipeline::RunnableDB
#######################################

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

sub Bio::EnsEMBL::Analysis::RunnableDB::debug {
  my $self = shift;
  $self->{'_debug'} = shift if(@_);
  $self->{'_debug'}=0 unless(defined($self->{'_debug'}));  
  return $self->{'_debug'};
}

sub Bio::EnsEMBL::Analysis::RunnableDB::analyze_tables {
  my $self = shift;  

  my $starttime = time();

  my $gdb = $self->{'comparaDBA'}->get_GenomeDBAdaptor;   

  foreach my $genome_db ( @{$gdb->fetch_all} ) { 
    my $gdb_id = $genome_db->dbID;
    my $species_name = lc($genome_db->name);
    $species_name =~ s/\ /\_/g;
    my $tbl_name = "peptide_align_feature"."_"."$species_name"."_"."$gdb_id";
    # Re-enable the keys before starting the queries
    my $sql = "ALTER TABLE $tbl_name ENABLE KEYS";
  
    print("$sql\n") if ($self->debug);
    my $sth = $self->dbc->prepare($sql);
    $sth->execute();
    $sql = "ANALYZE TABLE $tbl_name";
    $sth = $self->dbc->prepare($sql);
    $sth->execute();
    printf("  %1.3f secs to ANALYZE TABLE\n", (time()-$starttime));
  }
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

