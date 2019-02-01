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

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2019] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=head1 APPENDIX

    The rest of the documentation details each of the object methods.
    Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


sub default_table_name {
    return 'analysis_stats';
}


sub default_input_column_mapping {
    my $self    = shift @_;
    return  {
        'when_updated' => $self->dbc->_interval_seconds_sql('when_updated') . ' seconds_since_when_updated',
    };
}


sub do_not_update_columns {
    return ['when_updated'];
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::AnalysisStats';
}


sub objectify {     # turn the hashref into an object
    my ($self, $hashref) = @_;

    my $object = $self->SUPER::objectify( $hashref );

    $object->seconds_since_last_fetch(0);

    return $object;
}


################
#
# UPDATE METHODS
#
################


sub update_stats_and_monitor {
  my ($self, $stats) = @_;

  my $sql = "UPDATE analysis_stats SET status='".$stats->status."' ";

  $sql .= ",avg_msec_per_job=" . $stats->avg_msec_per_job();
  $sql .= ",avg_input_msec_per_job=" . $stats->avg_input_msec_per_job();
  $sql .= ",avg_run_msec_per_job=" . $stats->avg_run_msec_per_job();
  $sql .= ",avg_output_msec_per_job=" . $stats->avg_output_msec_per_job();
  $sql .= ",is_excluded=" . $stats->is_excluded();

  unless( $stats->hive_pipeline->hive_use_triggers() ) {
      $sql .= ",total_job_count=" . $stats->total_job_count();
      $sql .= ",semaphored_job_count=" . $stats->semaphored_job_count();
      $sql .= ",ready_job_count=" . $stats->ready_job_count();
      $sql .= ",done_job_count=" . $stats->done_job_count();
      $sql .= ",failed_job_count=" . $stats->failed_job_count();

      $stats->num_running_workers( $self->db->get_RoleAdaptor->count_active_roles( $stats->analysis_id() ) );
      $sql .= ",num_running_workers=" . $stats->num_running_workers();
  }

  $sql .= ",when_updated=CURRENT_TIMESTAMP";
  $sql .= ",sync_lock='0'";
  $sql .= " WHERE analysis_id='".$stats->analysis_id."' ";

  my $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;
  $sth = $self->prepare("INSERT INTO analysis_stats_monitor SELECT CURRENT_TIMESTAMP, analysis_stats.* from analysis_stats WHERE analysis_id = ".$stats->analysis_id);
  $sth->execute();
  $sth->finish;
  $stats->seconds_since_when_updated(0); #not exact but good enough :)
}


sub update_status {
  my ($self, $analysis_id, $status) = @_;

  my $sql = "UPDATE analysis_stats SET status='$status' WHERE analysis_id='$analysis_id' ";

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

  my $sql = $self->db->hive_pipeline->hive_use_triggers()
  ? qq{
    UPDATE analysis_stats SET
        avg_msec_per_job = ROUND(((done_job_count*avg_msec_per_job)/$weight_factor + $interval_msec) / (done_job_count/$weight_factor + $job_count)),
        avg_input_msec_per_job = ROUND(((done_job_count*avg_input_msec_per_job)/$weight_factor + $fetching_msec) / (done_job_count/$weight_factor + $job_count)),
        avg_run_msec_per_job = ROUND(((done_job_count*avg_run_msec_per_job)/$weight_factor + $running_msec) / (done_job_count/$weight_factor + $job_count)),
        avg_output_msec_per_job = ROUND(((done_job_count*avg_output_msec_per_job)/$weight_factor + $writing_msec) / (done_job_count/$weight_factor + $job_count))
    WHERE analysis_id= $analysis_id
  }
  : qq{
    UPDATE analysis_stats SET
        avg_msec_per_job = ROUND(((done_job_count*avg_msec_per_job)/$weight_factor + $interval_msec) / (done_job_count/$weight_factor + $job_count)),
        avg_input_msec_per_job = ROUND(((done_job_count*avg_input_msec_per_job)/$weight_factor + $fetching_msec) / (done_job_count/$weight_factor + $job_count)),
        avg_run_msec_per_job = ROUND(((done_job_count*avg_run_msec_per_job)/$weight_factor + $running_msec) / (done_job_count/$weight_factor + $job_count)),
        avg_output_msec_per_job = ROUND(((done_job_count*avg_output_msec_per_job)/$weight_factor + $writing_msec) / (done_job_count/$weight_factor + $job_count)),
        done_job_count = done_job_count + $job_count
    WHERE analysis_id= $analysis_id
  };

  $self->dbc->do( $sql );
}


sub increment_a_counter {
    my ($self, $counter, $increment, $analysis_id) = @_;

    unless( $self->db->hive_pipeline->hive_use_triggers() ) {
        if($increment) {    # can either be positive or negative
## ToDo: does it make sense to update the timestamp as well, to signal to the sync-allowed workers that they should wait?
#            $self->dbc->do( "UPDATE analysis_stats SET $counter = $counter + ($increment), when_updated=CURRENT_TIMESTAMP WHERE sync_lock=0 AND analysis_id='$analysis_id'" );
            $self->dbc->do( "UPDATE analysis_stats SET $counter = $counter + ($increment) WHERE sync_lock=0 AND analysis_id='$analysis_id'" );
        }
    }
}


sub get_seconds_since_locked {
    my ($self, $analysis_id) = @_;

    my $sql = 'SELECT '  . $self->dbc->_interval_seconds_sql('MAX(when_logged)') . ' FROM analysis_stats_monitor WHERE analysis_id = ? AND sync_lock = 0';
    my $sth = $self->prepare($sql);
    $sth->execute($analysis_id);
    my ($seconds_since_locked) = $sth->fetchrow_array();
    $sth->finish;
    return $seconds_since_locked;
}


1;

