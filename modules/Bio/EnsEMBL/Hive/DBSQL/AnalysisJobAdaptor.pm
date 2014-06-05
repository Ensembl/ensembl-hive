=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor

=head1 SYNOPSIS

    $analysisJobAdaptor = $db_adaptor->get_AnalysisJobAdaptor;
    $analysisJobAdaptor = $analysisJob->adaptor;

=head1 DESCRIPTION

    Module to encapsulate all db access for persistent class AnalysisJob.
    There should be just one per application and database connection.

=head1 LICENSE

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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
    Internal methods are preceded with a _

=cut


package Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::DBSQL::AnalysisDataAdaptor;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;
use Bio::EnsEMBL::Hive::Utils ('stringify');

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


sub default_table_name {
    return 'job';
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::AnalysisJob';
}


sub default_overflow_limit {
    return {
        'input_id'          => 255,
        'param_id_stack'    =>  64,
        'accu_id_stack'     =>  64,
    };
}


=head2 store_jobs_and_adjust_counters

  Arg [1]    : arrayref of Bio::EnsEMBL::Hive::AnalysisJob $jobs_to_store
  Arg [2]    : (optional) boolean $push_new_semaphore
  Example    : my @output_job_ids = @{ $job_adaptor->store_jobs_and_adjust_counters( \@jobs_to_store ) };
  Description: Attempts to store a list of jobs, returns an arrayref of successfully stored job_ids
  Returntype : Reference to list of job_dbIDs

=cut

sub store_jobs_and_adjust_counters {
    my ($self, $jobs, $push_new_semaphore) = @_;

    my $dbc                                 = $self->dbc;

        # NB: our use patterns assume all jobs from the same storing batch share the same semaphored_job_id:
    my $semaphored_job_id                   = scalar(@$jobs) && $jobs->[0]->semaphored_job_id();
    my $need_to_increase_semaphore_count    = ($semaphored_job_id && !$push_new_semaphore);

    my @output_job_ids  = ();
    my $failed_to_store = 0;

    foreach my $job (@$jobs) {
            # avoid deadlocks when dataflowing under transactional mode (used in Ortheus Runnable for example):
        $dbc->do( "SELECT 1 FROM job WHERE job_id=$semaphored_job_id FOR UPDATE" ) if($need_to_increase_semaphore_count and ($dbc->driver ne 'sqlite'));

        my ($job, $stored_this_time) = $self->store( $job );

        if($stored_this_time) {
            if($need_to_increase_semaphore_count) { # if we are not creating a new semaphore (where dependent jobs have already been counted),
                                                    # but rather propagating an existing one (same or other level), we have to up-adjust the counter
                $self->increase_semaphore_count_for_jobid( $semaphored_job_id );
            }

            unless($self->db->hive_use_triggers()) {
                $dbc->do(qq{
                        UPDATE analysis_stats
                        SET total_job_count=total_job_count+1
                    }
                    .(($job->status eq 'READY')
                        ? " ,ready_job_count=ready_job_count+1 "
                        : " ,semaphored_job_count=semaphored_job_count+1 "
                    ).(($dbc->driver eq 'pgsql')
                        ? " ,status = CAST(CASE WHEN status!='BLOCKED' THEN 'LOADING' ELSE 'BLOCKED' END AS analysis_status) "
                        : " ,status =      CASE WHEN status!='BLOCKED' THEN 'LOADING' ELSE 'BLOCKED' END "
                    )." WHERE analysis_id=".$job->analysis_id
                );
            }

            push @output_job_ids, $job->dbID();

        } else {
            $failed_to_store++;
        }
    }

        # adjust semaphore_count for jobs that failed to be stored (but have been pre-counted during funnel's creation):
    if($push_new_semaphore and $failed_to_store) {
        $self->decrease_semaphore_count_for_jobid( $semaphored_job_id, $failed_to_store );
    }

    return \@output_job_ids;
}


=head2 fetch_all_by_analysis_id_status

  Arg [1]    : (optional) int $analysis_id
  Arg [2]    : (optional) string $status
  Arg [3]    : (optional) int $retry_at_least
  Example    : $all_failed_jobs = $adaptor->fetch_all_by_analysis_id_status(undef, 'FAILED');
               $analysis_done_jobs = $adaptor->fetch_all_by_analysis_id_status($analysis->dbID, 'DONE');
  Description: Returns a list of all jobs filtered by given analysis_id (if specified) and given status (if specified).
  Returntype : reference to list of Bio::EnsEMBL::Hive::AnalysisJob objects

=cut

sub fetch_all_by_analysis_id_status {
    my ($self, $analysis_id, $status, $retry_count_at_least) = @_;

    my @constraints = ();
    push @constraints, "analysis_id=$analysis_id"             if ($analysis_id);
    push @constraints, "status='$status'"                     if ($status);
    push @constraints, "retry_count >= $retry_count_at_least" if ($retry_count_at_least);

    return $self->fetch_all( join(" AND ", @constraints) );
}


sub fetch_some_by_analysis_id_limit {
    my ($self, $analysis_id, $limit) = @_;

    return $self->fetch_all( "analysis_id = '$analysis_id' LIMIT $limit" );
}


sub fetch_all_incomplete_jobs_by_role_id {
    my ($self, $role_id) = @_;

    my $constraint = "status IN ('CLAIMED','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP') AND role_id='$role_id'";
    return $self->fetch_all($constraint);
}


sub fetch_by_url_query {
    my ($self, $field_name, $field_value) = @_;

    if($field_name eq 'dbID' and $field_value) {

        return $self->fetch_by_dbID($field_value);

    } else {

        return;

    }
}


sub fetch_job_counts_hashed_by_status {
    my ($self, $requested_analysis_id) = @_;

    my %job_counts = ();

        # Note: this seemingly useless dummy_analysis_id is here to force MySQL use existing index on (analysis_id, status)
    my $sql = "SELECT analysis_id, status, count(*) FROM job WHERE analysis_id=? GROUP BY analysis_id, status";
    my $sth = $self->prepare($sql);
    $sth->execute( $requested_analysis_id );

    while (my ($dummy_analysis_id, $status, $job_count)=$sth->fetchrow_array()) {
        $job_counts{ $status } = $job_count;
    }

    $sth->finish;

    return \%job_counts;
}


########################
#
# STORE / UPDATE METHODS
#
########################


sub decrease_semaphore_count_for_jobid {    # used in semaphore annihilation or unsuccessful creation
    my $self  = shift @_;
    my $jobid = shift @_ or return;
    my $dec   = shift @_ || 1;

        # NB: BOTH THE ORDER OF UPDATES AND EXACT WORDING IS ESSENTIAL FOR SYNCHRONOUS ATOMIC OPERATION,
        #       otherwise the same command tends to behave differently on MySQL and SQLite (at least)
        #
    my $sql = "UPDATE job "
        .( ($self->dbc->driver eq 'pgsql')
        ? "SET status = CAST(CASE WHEN semaphore_count>$dec THEN 'SEMAPHORED' ELSE 'READY' END AS jw_status), "
        : "SET status =      CASE WHEN semaphore_count>$dec THEN 'SEMAPHORED' ELSE 'READY' END, "
        ).qq{
            semaphore_count=semaphore_count-?
        WHERE job_id=? AND status='SEMAPHORED'
    };
    
    $self->dbc->protected_prepare_execute( $sql, $dec, $jobid );
}

sub increase_semaphore_count_for_jobid {    # used in semaphore propagation
    my $self  = shift @_;
    my $jobid = shift @_ or return;
    my $inc   = shift @_ || 1;

    my $sql = qq{
        UPDATE job
        SET semaphore_count=semaphore_count+?
        WHERE job_id=?
    };
    
    $self->dbc->protected_prepare_execute( $sql, $inc, $jobid );
}


=head2 update_status

  Arg [1]    : $analysis_id
  Example    :
  Description: updates the job.status in the database
  Returntype : 
  Exceptions :
  Caller     : general

=cut

sub update_status {
    my ($self, $job) = @_;

    my $sql = "UPDATE job SET status='".$job->status."' ";

    if($job->status eq 'DONE') {
        $sql .= ",completed=CURRENT_TIMESTAMP";
        $sql .= ",runtime_msec=".$job->runtime_msec;
        $sql .= ",query_count=".$job->query_count;
    } elsif($job->status eq 'PASSED_ON') {
        $sql .= ", completed=CURRENT_TIMESTAMP";
    } elsif($job->status eq 'READY') {
    }

    $sql .= " WHERE job_id='".$job->dbID."' ";

        # This particular query is infamous for collisions and 'deadlock' situations; let's wait and retry:
    $self->dbc->protected_prepare_execute( $sql );
}


=head2 store_out_files

  Arg [1]    : Bio::EnsEMBL::Hive::AnalysisJob $job
  Example    :
  Description: update locations of log files, if present
  Returntype : 
  Exceptions :
  Caller     : Bio::EnsEMBL::Hive::Worker

=cut

sub store_out_files {
    my ($self, $job) = @_;

    if($job->stdout_file or $job->stderr_file) {
        my $insert_sql = 'REPLACE INTO job_file (job_id, retry, role_id, stdout_file, stderr_file) VALUES (?,?,?,?,?)';
        my $sth = $self->dbc()->prepare($insert_sql);
        $sth->execute($job->dbID(), $job->retry_count(), $job->role_id(), $job->stdout_file(), $job->stderr_file());
        $sth->finish();
    } else {
        my $sql = 'DELETE from job_file WHERE role_id='.$job->role_id.' AND job_id='.$job->dbID;
        $self->dbc->do($sql);
    }
}


=head2 reset_or_grab_job_by_dbID

  Arg [1]    : int $job_id
  Arg [2]    : int $role_id (optional)
  Description: resets a job to to 'READY' (if no $role_id given) or directly to 'CLAIMED' so it can be run again, and fetches it.
               NB: Will also reset a previously 'SEMAPHORED' job to READY.
               The retry_count will be set to 1 for previously run jobs (partially or wholly) to trigger PRE_CLEANUP for them,
               but will not change retry_count if a job has never *really* started.
  Returntype : Bio::EnsEMBL::Hive::AnalysisJob or undef

=cut

sub reset_or_grab_job_by_dbID {
    my ($self, $job_id, $role_id) = @_;

    my $new_status  = $role_id ? 'CLAIMED' : 'READY';

        # Note: the order of the fields being updated is critical!
    my $sql = qq{
        UPDATE job
           SET retry_count = CASE WHEN (status='READY' OR status='CLAIMED') THEN retry_count ELSE 1 END
             , status=?
             , role_id=?
         WHERE job_id=?
    };
    my @values = ($new_status, $role_id, $job_id);

    my $sth = $self->prepare( $sql );
    my $return_code = $sth->execute( @values )
        or die "Could not run\n\t$sql\nwith data:\n\t(".join(',', @values).')';
    $sth->finish;

    my $job = $self->fetch_by_job_id_AND_status($job_id, $new_status) ;

    return $job;
}


=head2 grab_jobs_for_role

  Arg [1]           : Bio::EnsEMBL::Hive::Role object $role
  Arg [2]           : int $how_many_this_role
  Example: 
    my $jobs  = $job_adaptor->grab_jobs_for_role( $role, $how_many );
  Description: 
    For the specified Role, it will search available jobs, 
    and using the how_many_this_batch parameter, claim/fetch that
    number of jobs, and then return them.
  Returntype : 
    reference to array of Bio::EnsEMBL::Hive::AnalysisJob objects
  Caller     : Bio::EnsEMBL::Hive::Worker::run

=cut

sub grab_jobs_for_role {
    my ($self, $role, $how_many_this_batch) = @_;
  
    my $analysis_id     = $role->analysis_id;
    my $role_id         = $role->dbID;
    my $role_rank       = $self->db->get_RoleAdaptor->get_role_rank( $role );
    my $offset          = $how_many_this_batch * $role_rank;

    my $prefix_sql = ($self->dbc->driver eq 'mysql') ? qq{
         UPDATE job j
           JOIN (
                            SELECT job_id
                              FROM job
                             WHERE analysis_id='$analysis_id'
                               AND status='READY'
    } : qq{
         UPDATE job
           SET role_id='$role_id', status='CLAIMED'
         WHERE job_id in (
                            SELECT job_id
                              FROM job
                             WHERE analysis_id='$analysis_id'
                               AND status='READY'
    };
    my $virgin_sql = qq{       AND retry_count=0 };
    my $limit_sql  = qq{     LIMIT $how_many_this_batch };
    my $offset_sql = qq{    OFFSET $offset };
    my $suffix_sql = ($self->dbc->driver eq 'mysql') ? qq{
                 ) as x
         USING (job_id)
           SET j.role_id='$role_id', j.status='CLAIMED'
         WHERE j.status='READY'
    } : qq{
                 )
           AND status='READY'
    };

        # we have to be explicitly numeric here because of '0E0' value returned by DBI if "no rows have been affected":
    if(  (my $claim_count = $self->dbc->do( $prefix_sql . $virgin_sql . $limit_sql . $offset_sql . $suffix_sql)) == 0 ) {
        if( ($claim_count = $self->dbc->do( $prefix_sql .               $limit_sql . $offset_sql . $suffix_sql)) == 0 ) {
             $claim_count = $self->dbc->do( $prefix_sql .               $limit_sql .               $suffix_sql);
        }
    }

    return $self->fetch_all_by_role_id_AND_status($role_id, 'CLAIMED') ;
}


=head2 release_undone_jobs_from_role

  Arg [1]    : Bio::EnsEMBL::Hive::Role object
  Arg [2]    : optional message to be recorded in 'job_message' table
  Example    :
  Description: If a Worker has died some of its jobs need to be reset back to 'READY'
               so they can be rerun.
               Jobs in state CLAIMED as simply reset back to READY.
               If jobs was 'in progress' (PRE_CLEANUP, FETCH_INPUT, RUN, WRITE_OUTPUT, POST_CLEANUP) 
               the retry_count is increased and the status set back to READY.
               If the retry_count >= $max_retry_count (3 by default) the job is set
               to 'FAILED' and not rerun again.
  Exceptions : $role must be defined
  Caller     : Bio::EnsEMBL::Hive::Queen

=cut

sub release_undone_jobs_from_role {
    my ($self, $role, $msg) = @_;

    my $role_id         = $role->dbID;
    my $analysis        = $role->analysis;
    my $max_retry_count = $analysis->max_retry_count;
    my $worker          = $role->worker;

        #first just reset the claimed jobs, these don't need a retry_count index increment:
        # (previous role_id does not matter, because that Role has never had a chance to run the job)
    $self->dbc->do( qq{
        UPDATE job
           SET status='READY', role_id=NULL
         WHERE role_id='$role_id'
           AND status='CLAIMED'
    } );

    my $sth = $self->prepare( qq{
        SELECT job_id
          FROM job
         WHERE role_id='$role_id'
           AND status in ('PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP')
    } );
    $sth->execute();

    my $cod = $worker->cause_of_death();
    $msg ||= "GarbageCollector: The worker died because of $cod";

    my $resource_overusage = ($cod eq 'MEMLIMIT') || ($cod eq 'RUNLIMIT' and $worker->work_done()==0);

    while(my ($job_id) = $sth->fetchrow_array()) {

        my $passed_on = 0;  # the flag indicating that the garbage_collection was attempted and was successful

        if( $resource_overusage ) {
            if($passed_on = $self->gc_dataflow( $analysis, $job_id, $cod )) {
                $msg .= ', performing gc_dataflow';
            }
        }
        unless($passed_on) {
            if($passed_on = $self->gc_dataflow( $analysis, $job_id, 'ANYFAILURE' )) {
                $msg .= ", performing 'ANYFAILURE' gc_dataflow";
            }
        }

        $self->db()->get_LogMessageAdaptor()->store_job_message($job_id, $msg, not $passed_on );

        unless($passed_on) {
            $self->release_and_age_job( $job_id, $max_retry_count, not $resource_overusage );
        }
    }
    $sth->finish();
}


sub release_and_age_job {
    my ($self, $job_id, $max_retry_count, $may_retry, $runtime_msec) = @_;
    $may_retry ||= 0;
    $runtime_msec = "NULL" unless(defined $runtime_msec);
        # NB: The order of updated fields IS important. Here we first find out the new status and then increment the retry_count:
        #
        # FIXME: would it be possible to retain role_id for READY jobs in order to temporarily keep track of the previous (failed) worker?
        #
    $self->dbc->do( 
        "UPDATE job "
        .( ($self->dbc->driver eq 'pgsql')
            ? "SET status = CAST(CASE WHEN $may_retry AND (retry_count<$max_retry_count) THEN 'READY' ELSE 'FAILED' END AS jw_status), "
            : "SET status =      CASE WHEN $may_retry AND (retry_count<$max_retry_count) THEN 'READY' ELSE 'FAILED' END, "
         ).qq{
               retry_count=retry_count+1,
               runtime_msec=$runtime_msec
         WHERE job_id=$job_id
           AND status in ('CLAIMED','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP')
    } );
}

=head2 gc_dataflow

    Description:    perform automatic dataflow from a dead job that overused resources if a corresponding dataflow rule was provided
                    Should only be called once during garbage collection phase, when the job is definitely 'abandoned' and not being worked on.

=cut

sub gc_dataflow {
    my ($self, $analysis, $job_id, $branch_name) = @_;

    my $branch_code = Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor::branch_name_2_code($branch_name);

    unless( $self->db->get_DataflowRuleAdaptor->count_all_by_from_analysis_id_AND_branch_code($analysis->dbID, $branch_code) ) {
        return 0;   # just return if no corresponding gc_dataflow rule has been defined
    }

    my $job = $self->fetch_by_dbID($job_id);

    $job->param_init( 0, $analysis->parameters(), $job->input_id() );    # input_id_templates still supported, however to a limited extent

    $job->dataflow_output_id( $job->input_id() , $branch_name );

    $job->update_status('PASSED_ON');

    if(my $semaphored_job_id = $job->semaphored_job_id) {
        $self->decrease_semaphore_count_for_jobid( $semaphored_job_id );    # step-unblock the semaphore
    }
    
    return 1;
}


=head2 reset_jobs_for_analysis_id

  Arg [1]    : int $analysis_id
  Arg [2]    : bool $all (false by default)
  Description: Resets either all FAILED jobs of an analysis (default)
                or ALL jobs of an analysis to 'READY' and their retry_count to 0.
  Caller     : beekeeper.pl

=cut

sub reset_jobs_for_analysis_id {
    my ($self, $analysis_id, $input_statuses) = @_;

    my $status_filter = '';

    if(ref($input_statuses) eq 'ARRAY') {
        $status_filter = 'AND status IN ('.join(', ', map { "'$_'" } @$input_statuses).')';
    } elsif(!$input_statuses) {
        $status_filter = "AND status='FAILED'"; # temporarily keep it here for compatibility
    }

    my $sql = qq{
            UPDATE job
           SET retry_count = CASE WHEN (status='READY' OR status='CLAIMED') THEN 0 ELSE 1 END,
        }. ( ($self->dbc->driver eq 'pgsql')
        ? "status = CAST(CASE WHEN semaphore_count>0 THEN 'SEMAPHORED' ELSE 'READY' END AS jw_status) "
        : "status =      CASE WHEN semaphore_count>0 THEN 'SEMAPHORED' ELSE 'READY' END "
        ).qq{
            WHERE analysis_id=?
        } . $status_filter;

    my $sth = $self->prepare($sql);
    $sth->execute($analysis_id);
    $sth->finish;

    $self->db->get_AnalysisStatsAdaptor->update_status($analysis_id, 'LOADING');
}


=head2 balance_semaphores

  Description: Reset all semaphore_counts to the numbers of unDONE semaphoring jobs.

=cut

sub balance_semaphores {
    my ($self, $filter_analysis_id) = @_;

    my $find_sql    = qq{
                        SELECT * FROM (
                            SELECT funnel.job_id, funnel.semaphore_count AS was, COALESCE(COUNT(CASE WHEN fan.status!='DONE' AND fan.status!='PASSED_ON' THEN 1 ELSE NULL END),0) AS should
                            FROM job funnel
                            LEFT JOIN job fan ON (funnel.job_id=fan.semaphored_job_id)
                            WHERE }
                        .($filter_analysis_id ? "funnel.analysis_id=$filter_analysis_id AND " : '')
                        .qq{
                            funnel.status='SEMAPHORED'
                            GROUP BY funnel.job_id
                         ) AS internal WHERE was<>should OR should=0
                     };

    my $update_sql  = "UPDATE job SET "
        ." semaphore_count=semaphore_count+? , "
        .( ($self->dbc->driver eq 'pgsql')
        ? "status = CAST(CASE WHEN semaphore_count>0 THEN 'SEMAPHORED' ELSE 'READY' END AS jw_status) "
        : "status =      CASE WHEN semaphore_count>0 THEN 'SEMAPHORED' ELSE 'READY' END "
        )." WHERE job_id=? AND status='SEMAPHORED'";

    my $find_sth    = $self->prepare($find_sql);
    my $update_sth  = $self->prepare($update_sql);

    $find_sth->execute();
    while(my ($job_id, $was, $should) = $find_sth->fetchrow_array()) {
        my $msg;
        if(0<$should and $should<$was) {    # we choose not to lower the counter if it's not time to unblock yet
            $msg = "Semaphore count may need rebalancing, but it is not critical now, so leaving it on automatic: $was -> $should";
            $self->db->get_LogMessageAdaptor->store_job_message( $job_id, $msg, 0 );
        } else {
            $update_sth->execute($should-$was, $job_id);
            $msg = "Semaphore count needed rebalancing now, so performing: $was -> $should";
            $self->db->get_LogMessageAdaptor->store_job_message( $job_id, $msg, 1 );
        }
        warn "[Job $job_id] $msg\n";    # TODO: integrate the STDERR diagnostic output with LogMessageAdaptor calls in general
    }
    $find_sth->finish;
    $update_sth->finish;
}


sub fetch_input_ids_for_job_ids {
    my ($self, $job_ids_csv, $id_scale, $id_offset) = @_;
    $id_scale   ||= 1;
    $id_offset  ||= 0;

    my %input_ids = ();

    if( $job_ids_csv ) {

        my $sql = "SELECT job_id, input_id FROM job WHERE job_id in ($job_ids_csv)";
        my $sth = $self->prepare( $sql );
        $sth->execute();

        while(my ($job_id, $input_id) = $sth->fetchrow_array() ) {
            if($input_id =~ /^_ext(?:\w+)_data_id (\d+)$/) {
                $input_id = $self->db->get_AnalysisDataAdaptor->fetch_by_analysis_data_id_TO_data($1);
            }
            $input_ids{$job_id * $id_scale + $id_offset} = $input_id;
        }
    }
    return \%input_ids;
}


1;

