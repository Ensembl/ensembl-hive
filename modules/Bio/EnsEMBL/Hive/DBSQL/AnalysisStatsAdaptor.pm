# Perl module for Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor
#
# Date of creation: 22.03.2004
# Original Creator : Jessica Severin <jessica@ebi.ac.uk>
#
# Copyright EMBL-EBI 2004
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor

=head1 SYNOPSIS

  $analysisStatsAdaptor = $db_adaptor->get_AnalysisStatsAdaptor;
  $analysisStatsAdaptor = $analysisStats->adaptor;

=head1 DESCRIPTION

  Module to encapsulate all db access for persistent class AnalysisStats.
  There should be just one per application and database connection.

=head1 CONTACT

    Contact Jessica Severin on implemetation/design detail: jessica@ebi.ac.uk
    Contact Ewan Birney on EnsEMBL in general: birney@sanger.ac.uk

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut


# Let the code begin...

package Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor;

use strict;
use Bio::EnsEMBL::Hive::AnalysisStats;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;

our @ISA = qw(Bio::EnsEMBL::DBSQL::BaseAdaptor);


=head2 fetch_by_dbID

  Arg [1]    : int $id
               the unique database identifier for the feature to be obtained
  Example    : $feat = $adaptor->fetch_by_dbID(1234);
  Description: Returns the feature created from the database defined by the
               the id $id.
  Returntype : Bio::EnsEMBL::Hive::AnalysisStats
  Exceptions : thrown if $id is not defined
  Caller     : general

=cut

sub fetch_by_dbID {
  my ($self,$id) = @_;

  unless(defined $id) {
    $self->throw("fetch_by_dbID must have an id");
  }

  my $constraint = "ast.analysis_id = $id";

  #return first element of _generic_fetch list
  my ($obj) = @{$self->_generic_fetch($constraint)};
  unless(defined($obj)) {
    $self->_create_new_for_analysis_id($id);
    ($obj) = @{$self->_generic_fetch($constraint)};  
  }
  return $obj;
}

=head2 fetch_all

  Arg        : None
  Example    : 
  Description: 
  Returntype : 
  Exceptions : 
  Caller     : 

=cut

sub fetch_all {
  my $self = shift;

  return $self->_generic_fetch();
}



#
# INTERNAL METHODS
#
###################

=head2 _generic_fetch

  Arg [1]    : (optional) string $constraint
               An SQL query constraint (i.e. part of the WHERE clause)
  Arg [2]    : (optional) string $logic_name
               the logic_name of the analysis of the features to obtain
  Example    : $fts = $a->_generic_fetch('contig_id in (1234, 1235)', 'Swall');
  Description: Performs a database fetch and returns feature objects in
               contig coordinates.
  Returntype : listref of Bio::EnsEMBL::SeqFeature in contig coordinates
  Exceptions : none
  Caller     : BaseFeatureAdaptor, ProxyDnaAlignFeatureAdaptor::_generic_fetch

=cut
  
sub _generic_fetch {
  my ($self, $constraint, $join) = @_;
  
  my @tables = $self->_tables;
  my $columns = join(', ', $self->_columns());
  
  if ($join) {
    foreach my $single_join (@{$join}) {
      my ($tablename, $condition, $extra_columns) = @{$single_join};
      if ($tablename && $condition) {
        push @tables, $tablename;
        
        if($constraint) {
          $constraint .= " AND $condition";
        } else {
          $constraint = " $condition";
        }
      } 
      if ($extra_columns) {
        $columns .= ", " . join(', ', @{$extra_columns});
      }
    }
  }
      
  #construct a nice table string like 'table1 t1, table2 t2'
  my $tablenames = join(', ', map({ join(' ', @$_) } @tables));

  my $sql = "SELECT $columns FROM $tablenames";

  my $default_where = $self->_default_where_clause;
  my $final_clause = $self->_final_clause;

  #append a where clause if it was defined
  if($constraint) { 
    $sql .= " WHERE $constraint ";
    if($default_where) {
      $sql .= " AND $default_where ";
    }
  } elsif($default_where) {
    $sql .= " WHERE $default_where ";
  }

  #append additional clauses which may have been defined
  $sql .= " $final_clause";
  #rint STDOUT $sql,"\n";

  my $sth = $self->prepare($sql);
  $sth->execute;  


  return $self->_objs_from_sth($sth);
}

sub _tables {
  my $self = shift;

  return (['analysis_stats', 'ast']);
}

sub _columns {
  my $self = shift;
=head3
CREATE TABLE analysis_stats (
  analysis_id           int(10) NOT NULL,
  status                enum('BLOCKED', 'READY', 'WORKING', 'ALL_CLAIMED', 'DONE')
                          DEFAULT 'READY' NOT NULL,
  batch_size            int(10) NOT NULL,
  hive_capacity         int(10) NOT NULL,
  total_job_count       int(10) NOT NULL,
  unclaimed_job_count   int(10) NOT NULL,
  done_job_count        int(10) NOT NULL,
  num_required_workers  int(10) NOT NULL,
  last_update           datetime NOT NULL,

  UNIQUE KEY   (analysis_id)
);
=cut
  my @columns = qw (ast.analysis_id
                    ast.status
                    ast.batch_size
                    ast.hive_capacity
                    ast.total_job_count
                    ast.unclaimed_job_count
                    ast.done_job_count
                    ast.num_required_workers
                    ast.last_update
                   );
  push @columns , "NOW()-ast.last_update seconds_since_last_update";
  return @columns;            
}

sub _objs_from_sth {
  my ($self, $sth) = @_;
  
  my %column;
  $sth->bind_columns( \( @column{ @{$sth->{NAME_lc} } } ));

  my @statsArray = ();

  while ($sth->fetch()) {
    my $analStats = new Bio::EnsEMBL::Hive::AnalysisStats;

    $analStats->dbID($column{'analysis_id'});
    $analStats->status($column{'status'});
    $analStats->batch_size($column{'batch_size'});
    $analStats->hive_capacity($column{'hive_capacity'});
    $analStats->total_job_count($column{'total_job_count'});
    $analStats->unclaimed_job_count($column{'unclaimed_job_count'});
    $analStats->done_job_count($column{'done_job_count'});
    $analStats->num_required_workers($column{'num_required_workers'});
    $analStats->seconds_since_last_update($column{'seconds_since_last_update'});
    $analStats->adaptor($self);

    push @statsArray, $analStats;    
  }
  $sth->finish;
  
  return \@statsArray
}

sub _default_where_clause {
  my $self = shift;
  return '';
}

sub _final_clause {
  my $self = shift;
  return '';
}


#
# STORE / UPDATE METHODS
#
################

=head2 update

  Arg [1]    : Bio::EnsEMBL::Hive::AnalysisStats object
  Example    :
  Description:
  Returntype : Bio::EnsEMBL::Hive::Worker
  Exceptions :
  Caller     :

=cut

sub update {
  my ($self, $stats) = @_;

  my $sql = "UPDATE analysis_stats SET status='".$stats->status."' ";
  $sql .= ",batch_size=" . $stats->batch_size();
  $sql .= ",hive_capacity=" . $stats->hive_capacity();
  $sql .= ",total_job_count=" . $stats->total_job_count();
  $sql .= ",unclaimed_job_count=" . $stats->unclaimed_job_count();
  $sql .= ",done_job_count=" . $stats->done_job_count();
  $sql .= ",num_required_workers=" . $stats->num_required_workers(); 
  $sql .= ",last_update=NOW()";
  $sql .= " WHERE analysis_id='".$stats->dbID."' ";
  
  my $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;
  $stats->seconds_since_last_update(0); #not exact but good enough :)
}


sub update_status
{
  my ($self, $analysis_id, $status) = @_;

  my $sql = "UPDATE analysis_stats SET status='$status' ";
  $sql .= " WHERE analysis_id='$analysis_id' ";

  my $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;
}


sub _create_new_for_analysis_id {
  my ($self, $analysis_id) = @_;

  my $sql;

  $sql = "INSERT ignore INTO analysis_stats SET analysis_id='$analysis_id' ";
  print("$sql\n");
  my $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;
}

1;


