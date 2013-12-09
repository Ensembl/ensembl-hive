=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor

=head1 SYNOPSIS

    $analysisStatsAdaptor = $db_adaptor->get_AnalysisStatsAdaptor;
    $analysisStatsAdaptor = $analysisStats->adaptor;

=head1 DESCRIPTION

    Module to encapsulate all db access for persistent class AnalysisStats.
    There should be just one per application and database connection.

=head1 LICENSE

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

    The rest of the documentation details each of the object methods.
    Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor;

use strict;

use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception ('throw');
use Bio::EnsEMBL::Hive::AnalysisStats;

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

  if(!defined($obj)) {
    throw("unable to fetch analysis_stats for analysis_id = $id\n");
  }
  return $obj;
}


sub fetch_all_by_suitability_rc_id_meadow_type {
    my ($self, $resource_class_id, $meadow_type) = @_;

    my $join = [[ ['analysis_base', 'a'], " ast.analysis_id=a.analysis_id "
                                                .( $resource_class_id ? "AND a.resource_class_id=$resource_class_id " : '')
                                                .( $meadow_type       ? "AND (a.meadow_type IS NULL OR a.meadow_type='$meadow_type') " : '')
               ]];

        # the ones that clearly have work to do:
        #
    my $primary_results = $self->_generic_fetch(
        "ast.num_required_workers>0 AND ast.status in ('READY', 'WORKING')" ,
        $join ,
        'ORDER BY a.priority DESC, ' . ( ($self->dbc->driver eq 'mysql') ? 'RAND()' : 'RANDOM()' ),
    );

        # the ones that may have work to do after a sync:
        #
    my $secondary_results = $self->_generic_fetch(
        "ast.status in ('LOADING', 'BLOCKED', 'ALL_CLAIMED', 'SYNCHING')" ,
        $join ,
        'ORDER BY last_update',     # FIXME: could mix in a.priority if sync is not too expensive?
    );

    return [ @$primary_results, @$secondary_results ];
}


=head2 refresh

  Arg [1]    : Bio::EnsEMBL::Hive::AnalysisStats object
  Description: reload the AnalysisStats object from the database
  Returntype : Bio::EnsEMBL::Hive::AnalysisStats object - same one with reloaded data

=cut


sub refresh {
    my ($self, $stats) = @_;

    my $new_stats = $self->fetch_by_analysis_id( $stats->analysis_id );     # fetch into a separate object

    %$stats = %$new_stats;                                                  # copy the data over

    return $stats;
}


################
#
# STORE / UPDATE METHODS
#
################


sub store {
    my ($self, $stats) = @_;

    my $sql = "INSERT INTO analysis_stats (analysis_id, batch_size, hive_capacity, status) VALUES (?, ?, ?, ?)";

    my $sth = $self->prepare($sql);
    $sth->execute($stats->analysis_id, $stats->batch_size, $stats->hive_capacity, $stats->status);
    $sth->finish;

    $stats->adaptor( $self );

    return $stats;
}


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

  my $hive_capacity = $stats->hive_capacity;

  if ($stats->behaviour eq "DYNAMIC") {

    my $max_hive_capacity = $stats->avg_input_msec_per_job
        ? int($stats->input_capacity * $stats->avg_msec_per_job / $stats->avg_input_msec_per_job)
        : $hive_capacity;

    if ($stats->avg_output_msec_per_job) {
      my $max_hive_capacity2 = int($stats->output_capacity * $stats->avg_msec_per_job / $stats->avg_output_msec_per_job);
      if ($max_hive_capacity2 < $max_hive_capacity) {
        $max_hive_capacity = $max_hive_capacity2;
      }
    }

    $stats->hive_capacity( int( ($hive_capacity+$max_hive_capacity+1)/2 ) );
  }

  my $sql = "UPDATE analysis_stats SET status='".$stats->status."' ";
  $sql .= ",batch_size=" . $stats->batch_size();
  $sql .= ",hive_capacity=" . (defined($stats->hive_capacity()) ? $stats->hive_capacity() : 'NULL');

  $sql .= ",avg_msec_per_job=" . $stats->avg_msec_per_job();
  $sql .= ",avg_input_msec_per_job=" . $stats->avg_input_msec_per_job();
  $sql .= ",avg_run_msec_per_job=" . $stats->avg_run_msec_per_job();
  $sql .= ",avg_output_msec_per_job=" . $stats->avg_output_msec_per_job();

  unless( $self->db->hive_use_triggers() ) {
      $sql .= ",total_job_count=" . $stats->total_job_count();
      $sql .= ",semaphored_job_count=" . $stats->semaphored_job_count();
      $sql .= ",ready_job_count=" . $stats->ready_job_count();
      $sql .= ",done_job_count=" . $stats->done_job_count();
      $sql .= ",failed_job_count=" . $stats->failed_job_count();

      $stats->num_running_workers( $self->db->get_Queen->count_running_workers( $stats->analysis_id() ) );
      $sql .= ",num_running_workers=" . $stats->num_running_workers();
  }

  $sql .= ",num_required_workers=" . $stats->num_required_workers();
  $sql .= ",last_update=CURRENT_TIMESTAMP";
  $sql .= ",sync_lock='0'";
  $sql .= " WHERE analysis_id='".$stats->analysis_id."' ";

  my $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;
  $sth = $self->prepare("INSERT INTO analysis_stats_monitor SELECT CURRENT_TIMESTAMP, analysis_stats.* from analysis_stats WHERE analysis_id = ".$stats->analysis_id);
  $sth->execute();
  $sth->finish;
  $stats->seconds_since_last_update(0); #not exact but good enough :)
}


sub update_status {
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

  my $sql = $self->db->hive_use_triggers()
  ? qq{
    UPDATE analysis_stats SET
        avg_msec_per_job = (((done_job_count*avg_msec_per_job)/$weight_factor + $interval_msec) / (done_job_count/$weight_factor + $job_count)), 
        avg_input_msec_per_job = (((done_job_count*avg_input_msec_per_job)/$weight_factor + $fetching_msec) / (done_job_count/$weight_factor + $job_count)), 
        avg_run_msec_per_job = (((done_job_count*avg_run_msec_per_job)/$weight_factor + $running_msec) / (done_job_count/$weight_factor + $job_count)), 
        avg_output_msec_per_job = (((done_job_count*avg_output_msec_per_job)/$weight_factor + $writing_msec) / (done_job_count/$weight_factor + $job_count))
    WHERE analysis_id= $analysis_id
  }
  : qq{
    UPDATE analysis_stats SET
        avg_msec_per_job = (((done_job_count*avg_msec_per_job)/$weight_factor + $interval_msec) / (done_job_count/$weight_factor + $job_count)), 
        avg_input_msec_per_job = (((done_job_count*avg_input_msec_per_job)/$weight_factor + $fetching_msec) / (done_job_count/$weight_factor + $job_count)), 
        avg_run_msec_per_job = (((done_job_count*avg_run_msec_per_job)/$weight_factor + $running_msec) / (done_job_count/$weight_factor + $job_count)), 
        avg_output_msec_per_job = (((done_job_count*avg_output_msec_per_job)/$weight_factor + $writing_msec) / (done_job_count/$weight_factor + $job_count)), 
        ready_job_count = ready_job_count - $job_count, 
        done_job_count = done_job_count + $job_count 
    WHERE analysis_id= $analysis_id
  };

  $self->dbc->do($sql);
}


sub increase_running_workers {
  my $self = shift;
  my $analysis_id = shift;

  my $sql = "UPDATE analysis_stats SET num_running_workers = num_running_workers + 1 ".
      " WHERE analysis_id='$analysis_id'";

  $self->dbc->do($sql);
}


sub decrease_running_workers {
  my $self = shift;
  my $analysis_id = shift;

  my $sql = "UPDATE analysis_stats SET num_running_workers = num_running_workers - 1 ".
      " WHERE analysis_id='$analysis_id'";

  $self->dbc->do($sql);
}


sub decrease_required_workers {
  my $self = shift;
  my $analysis_id = shift;

  my $sql = "UPDATE analysis_stats SET num_required_workers=num_required_workers-1 ".
            "WHERE analysis_id='$analysis_id' ";

  $self->dbc->do($sql);
}


sub increase_required_workers {
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
  my ($self, $constraint, $join, $final_clause) = @_;
  
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
  $sql .= " $final_clause" if($final_clause);
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
                    ast.batch_size
                    ast.hive_capacity
                    ast.status

                    ast.total_job_count
                    ast.semaphored_job_count
                    ast.ready_job_count
                    ast.done_job_count
                    ast.failed_job_count
                    ast.num_running_workers
                    ast.num_required_workers

                    ast.behaviour
                    ast.input_capacity
                    ast.output_capacity

                    ast.avg_msec_per_job
                    ast.avg_input_msec_per_job
                    ast.avg_run_msec_per_job
                    ast.avg_output_msec_per_job

                    ast.last_update
                    ast.sync_lock
                   );

    push @columns, {
            'mysql'     => "UNIX_TIMESTAMP()-UNIX_TIMESTAMP(ast.last_update) seconds_since_last_update ",
            'sqlite'    => "strftime('%s','now')-strftime('%s',ast.last_update) seconds_since_last_update ",
            'pgsql'     => "EXTRACT(EPOCH FROM CURRENT_TIMESTAMP - ast.last_update) seconds_since_last_update ",
        }->{ $self->dbc->driver };

    return @columns;            
}

sub _objs_from_sth {
  my ($self, $sth) = @_;
  
  my %column;
  $sth->bind_columns( \( @column{ @{$sth->{NAME_lc} } } ));

  my @statsArray = ();

  while ($sth->fetch()) {
    my $analStats = Bio::EnsEMBL::Hive::AnalysisStats->new();

    $analStats->analysis_id($column{'analysis_id'});
    $analStats->batch_size($column{'batch_size'});
    $analStats->hive_capacity($column{'hive_capacity'});
    $analStats->status($column{'status'});

    $analStats->total_job_count($column{'total_job_count'});
    $analStats->semaphored_job_count($column{'semaphored_job_count'});
    $analStats->ready_job_count($column{'ready_job_count'});
    $analStats->done_job_count($column{'done_job_count'});
    $analStats->failed_job_count($column{'failed_job_count'});
    $analStats->num_running_workers($column{'num_running_workers'});
    $analStats->num_required_workers($column{'num_required_workers'});

    $analStats->behaviour($column{'behaviour'});
    $analStats->input_capacity($column{'input_capacity'});
    $analStats->output_capacity($column{'output_capacity'});

    $analStats->avg_msec_per_job($column{'avg_msec_per_job'});
    $analStats->avg_input_msec_per_job($column{'avg_input_msec_per_job'});
    $analStats->avg_run_msec_per_job($column{'avg_run_msec_per_job'});
    $analStats->avg_output_msec_per_job($column{'avg_output_msec_per_job'});

    $analStats->seconds_since_last_update($column{'seconds_since_last_update'});
    $analStats->sync_lock($column{'sync_lock'});

    $analStats->adaptor($self);

    push @statsArray, $analStats;
  }
  $sth->finish;

  return \@statsArray
}


1;

