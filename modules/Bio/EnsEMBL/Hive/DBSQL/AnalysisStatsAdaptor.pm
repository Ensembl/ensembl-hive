# Perl module for Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor
#
# Date of creation: 22.03.2004
# Original Creator : Jessica Severin <jessica@ebi.ac.uk>
#
# Copyright EMBL-EBI 2004
#
# You may distribute this module under the same terms as perl itself

=pod

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor

=head1 SYNOPSIS

  $analysisStatsAdaptor = $db_adaptor->get_AnalysisStatsAdaptor;
  $analysisStatsAdaptor = $analysisStats->adaptor;

=head1 DESCRIPTION

  Module to encapsulate all db access for persistent class AnalysisStats.
  There should be just one per application and database connection.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _

=cut



package Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor;

use strict;
use Bio::EnsEMBL::Hive::AnalysisStats;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;
use Bio::EnsEMBL::Hive::Utils::Stopwatch;

use base ('Bio::EnsEMBL::DBSQL::BaseAdaptor');


=head2 fetch_by_analysis_id

  Arg [1]    : int $id
               the unique database identifier for the feature to be obtained
  Example    : $feat = $adaptor->fetch_by_analysis_id(1234);
  Description: Returns the feature created from the database defined by the
               the id $id.
  Returntype : Bio::EnsEMBL::Hive::AnalysisStats
  Exceptions : thrown if $id is not defined
  Caller     : general

=cut

sub fetch_by_analysis_id {
  my ($self,$id) = @_;

  unless(defined $id) {
    throw("fetch_by_analysis_id must have an id");
  }

  my $constraint = "ast.analysis_id = $id";

  #return first element of _generic_fetch list
  my ($obj) = @{$self->_generic_fetch($constraint)};
  unless(defined($obj)) {
    $self->_create_new_for_analysis_id($id);
    ($obj) = @{$self->_generic_fetch($constraint)};  
  }

  if(!defined($obj)) {
    throw("unable to fetch analysis_stats for analysis_id = $id\n");
  }
  
  return $obj;
}


sub fetch_all {
  my $self = shift;
  return $self->_generic_fetch();
}


sub fetch_by_needed_workers {
    my ($self, $limit, $maximise_concurrency, $rc_id) = @_;

    my $constraint = "ast.num_required_workers>0 AND ast.status in ('READY','WORKING')"
                    .(defined($rc_id) ? " AND ast.rc_id = $rc_id" : '');

    my $final_clause = 'ORDER BY num_running_workers'
                        .($maximise_concurrency ? '' : ' DESC')
                        .', hive_capacity DESC, analysis_id'
                        .($limit ? " LIMIT $limit" : '');

    $self->_final_clause($final_clause);
    my $results = $self->_generic_fetch($constraint);
    $self->_final_clause(''); # reset final clause for other fetches

    return $results;
}


sub fetch_by_statuses {
  my ($self, $statuses, $rc_id) = @_;

  my $constraint = 'ast.status in ('.join(', ', map { "'$_'" } @$statuses).')'
                   .(defined($rc_id) ? " AND ast.rc_id = $rc_id" : '');

  $self->_final_clause('ORDER BY last_update');
  my $results = $self->_generic_fetch($constraint);
  $self->_final_clause(''); #reset final clause for other fetches

  return $results;
}


sub refresh {
  my ($self, $stats) = @_;

  my $constraint = "ast.analysis_id = " . $stats->analysis_id;

  #return first element of _generic_fetch list
  $stats = @{$self->_generic_fetch($constraint)};

  return $stats;
}


sub get_running_worker_count {
  my ($self, $stats) = @_;

  my $sql = "SELECT count(*) FROM hive WHERE cause_of_death='' and analysis_id=?";
  my $sth = $self->prepare($sql);
  $sth->execute($stats->analysis_id);
  my ($liveCount) = $sth->fetchrow_array();
  $sth->finish;

  return $liveCount;
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

  my $running_worker_count = $self->get_running_worker_count($stats);
  $stats->num_running_workers($running_worker_count);
  my $hive_capacity = $stats->hive_capacity;

  if ($stats->behaviour eq "DYNAMIC") {
    my $max_hive_capacity = $hive_capacity;
    if ($stats->avg_input_msec_per_job) {
      $max_hive_capacity = int($stats->input_capacity * $stats->avg_msec_per_job / $stats->avg_input_msec_per_job);
    }
    if ($stats->avg_output_msec_per_job) {
      my $max_hive_capacity2 = int($stats->output_capacity * $stats->avg_msec_per_job / $stats->avg_output_msec_per_job);
      if ($max_hive_capacity2 < $max_hive_capacity) {
        $max_hive_capacity = $max_hive_capacity2;
      }
    }
    if (($hive_capacity > $max_hive_capacity) or ($hive_capacity < $max_hive_capacity )) {
      if (abs($hive_capacity - $max_hive_capacity) > 2) {
        $stats->hive_capacity(($hive_capacity + $max_hive_capacity) / 2);
      } elsif ($hive_capacity > $max_hive_capacity) {
        $stats->hive_capacity($hive_capacity - 1);
      } elsif ($hive_capacity < $max_hive_capacity) {
        $stats->hive_capacity($hive_capacity + 1);
      }
    }
  }

  my $sql = "UPDATE analysis_stats SET status='".$stats->status."' ";
  $sql .= ",batch_size=" . $stats->batch_size();
  $sql .= ",avg_msec_per_job=" . $stats->avg_msec_per_job();
  $sql .= ",avg_input_msec_per_job=" . $stats->avg_input_msec_per_job();
  $sql .= ",avg_run_msec_per_job=" . $stats->avg_run_msec_per_job();
  $sql .= ",avg_output_msec_per_job=" . $stats->avg_output_msec_per_job();
  $sql .= ",hive_capacity=" . $stats->hive_capacity();
  $sql .= ",total_job_count=" . $stats->total_job_count();
  $sql .= ",unclaimed_job_count=" . $stats->unclaimed_job_count();
  $sql .= ",done_job_count=" . $stats->done_job_count();
  $sql .= ",max_retry_count=" . $stats->max_retry_count();
  $sql .= ",failed_job_count=" . $stats->failed_job_count();
  $sql .= ",failed_job_tolerance=" . $stats->failed_job_tolerance();
  $sql .= ",num_running_workers=" . $stats->num_running_workers();
  $sql .= ",num_required_workers=" . $stats->num_required_workers();
  $sql .= ",last_update=NOW()";
  $sql .= ",sync_lock='0'";
  $sql .= ",rc_id=". $stats->rc_id();
  $sql .= " WHERE analysis_id='".$stats->analysis_id."' ";

  my $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;
  $sth = $self->prepare("INSERT INTO analysis_stats_monitor SELECT now(), analysis_stats.* from analysis_stats WHERE analysis_id = ".$stats->analysis_id);
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


=head2 interval_update_work_done

  Arg [1]     : int $analysis_id
  Arg [2]     : int $jobs_done_in_interval
  Arg [3]     : int $interval_msec
  Arg [4]     : int $fetching_msec
  Arg [5]     : int $running_msec
  Arg [6]     : int $writing_msec
  Arg [7]     : real $weight_factor [optional]
  Example     : $statsDBA->interval_update_work_done($analysis_id, $jobs_done, $interval_msec, $fetching_msec, $running_msec, $writing_msec);
  Description : does a database update to recalculate the avg_msec_per_job and done_job_count
                does an interval equation by multiplying out the previous done_job_count with the
                previous avg_msec_per_job and then expanding by new interval values to give a better average.
  Caller      : Bio::EnsEMBL::Hive::Worker

=cut

sub interval_update_work_done {
  my ($self, $analysis_id, $job_count, $interval_msec, $fetching_msec, $running_msec, $writing_msec, $weight_factor) = @_;

  $weight_factor ||= 3; # makes it more sensitive to the dynamics of the farm

  my $sql = qq{
    UPDATE analysis_stats SET
        unclaimed_job_count = unclaimed_job_count - $job_count, 
        avg_msec_per_job = (((done_job_count*avg_msec_per_job)/$weight_factor + $interval_msec) / (done_job_count/$weight_factor + $job_count)), 
        avg_input_msec_per_job = (((done_job_count*avg_input_msec_per_job)/$weight_factor + $fetching_msec) / (done_job_count/$weight_factor + $job_count)), 
        avg_run_msec_per_job = (((done_job_count*avg_run_msec_per_job)/$weight_factor + $running_msec) / (done_job_count/$weight_factor + $job_count)), 
        avg_output_msec_per_job = (((done_job_count*avg_output_msec_per_job)/$weight_factor + $writing_msec) / (done_job_count/$weight_factor + $job_count)), 
        done_job_count = done_job_count + $job_count 
    WHERE analysis_id= $analysis_id
  };

  $self->dbc->do($sql);
}




sub decrease_hive_capacity
{
  my $self = shift;
  my $analysis_id = shift;

  my $sql = "UPDATE analysis_stats ".
      " SET hive_capacity = hive_capacity - 1, ".
      " num_required_workers = IF(num_required_workers > 0, num_required_workers - 1, 0) ".
      " WHERE analysis_id='$analysis_id' and hive_capacity > 1";

  $self->dbc->do($sql);
}


sub increase_hive_capacity
{
  my $self = shift;
  my $analysis_id = shift;

  my $sql = "UPDATE analysis_stats ".
      " SET hive_capacity = hive_capacity + 1, num_required_workers = 1".
      " WHERE analysis_id='$analysis_id' and hive_capacity <= 500 and num_required_workers = 0";

  $self->dbc->do($sql);
}


sub increase_running_workers
{
  my $self = shift;
  my $analysis_id = shift;

  my $sql = "UPDATE analysis_stats SET num_running_workers = num_running_workers + 1 ".
      " WHERE analysis_id='$analysis_id'";

  $self->dbc->do($sql);
}


sub decrease_running_workers
{
  my $self = shift;
  my $analysis_id = shift;

  my $sql = "UPDATE analysis_stats SET num_running_workers = num_running_workers - 1 ".
      " WHERE analysis_id='$analysis_id'";

  $self->dbc->do($sql);
}

sub decrease_running_workers_on_hive_overload {
    my $self        = shift;
    my $analysis_id = shift;

    my $sql = "UPDATE analysis_stats SET num_running_workers = num_running_workers - 1 ".
              "WHERE num_running_workers > hive_capacity AND analysis_id = $analysis_id ";

    my $row_count = $self->dbc->do($sql);
    return $row_count;
}

sub decrease_needed_workers
{
  my $self = shift;
  my $analysis_id = shift;

  my $sql = "UPDATE analysis_stats SET num_required_workers=num_required_workers-1 ".
            "WHERE analysis_id='$analysis_id' ";

  $self->dbc->do($sql);
}


sub increase_needed_workers
{
  my $self = shift;
  my $analysis_id = shift;

  my $sql = "UPDATE analysis_stats SET num_required_workers=num_required_workers+1 ".
            "WHERE analysis_id='$analysis_id' ";

  $self->dbc->do($sql);
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

  my @columns = qw (ast.analysis_id
                    ast.status
                    ast.batch_size
                    ast.avg_msec_per_job
                    ast.avg_input_msec_per_job
                    ast.avg_run_msec_per_job
                    ast.avg_output_msec_per_job
                    ast.hive_capacity
                    ast.behaviour
                    ast.input_capacity
                    ast.output_capacity
                    ast.total_job_count
                    ast.unclaimed_job_count
                    ast.done_job_count
                    ast.max_retry_count
                    ast.failed_job_count
                    ast.failed_job_tolerance
                    ast.num_running_workers
                    ast.num_required_workers
                    ast.last_update
                    ast.sync_lock
                    ast.rc_id
                   );
  push @columns , "UNIX_TIMESTAMP()-UNIX_TIMESTAMP(ast.last_update) seconds_since_last_update ";
  return @columns;            
}

sub _objs_from_sth {
  my ($self, $sth) = @_;
  
  my %column;
  $sth->bind_columns( \( @column{ @{$sth->{NAME_lc} } } ));

  my @statsArray = ();

  while ($sth->fetch()) {
    my $analStats = new Bio::EnsEMBL::Hive::AnalysisStats;

    $analStats->analysis_id($column{'analysis_id'});
    $analStats->status($column{'status'});
    $analStats->sync_lock($column{'sync_lock'});
    $analStats->rc_id($column{'rc_id'});
    $analStats->batch_size($column{'batch_size'});
    $analStats->avg_msec_per_job($column{'avg_msec_per_job'});
    $analStats->avg_input_msec_per_job($column{'avg_input_msec_per_job'});
    $analStats->avg_run_msec_per_job($column{'avg_run_msec_per_job'});
    $analStats->avg_output_msec_per_job($column{'avg_output_msec_per_job'});
    $analStats->hive_capacity($column{'hive_capacity'});
    $analStats->behaviour($column{'behaviour'});
    $analStats->input_capacity($column{'input_capacity'});
    $analStats->output_capacity($column{'output_capacity'});
    $analStats->total_job_count($column{'total_job_count'});
    $analStats->unclaimed_job_count($column{'unclaimed_job_count'});
    $analStats->done_job_count($column{'done_job_count'});
    $analStats->max_retry_count($column{'max_retry_count'});
    $analStats->failed_job_count($column{'failed_job_count'});
    $analStats->failed_job_tolerance($column{'failed_job_tolerance'});
    $analStats->num_running_workers($column{'num_running_workers'});
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
  $self->{'_final_clause'} = shift if(@_);
  $self->{'_final_clause'} = "" unless($self->{'_final_clause'});
  return $self->{'_final_clause'};
}


sub _create_new_for_analysis_id {
  my ($self, $analysis_id) = @_;

  my $sql;

  $sql = "INSERT ignore INTO analysis_stats (analysis_id) VALUES ($analysis_id)";
  #print("$sql\n");
  my $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;
}

1;

