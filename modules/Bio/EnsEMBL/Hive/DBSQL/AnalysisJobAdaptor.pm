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
    Internal methods are preceded with a _

=cut


package Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Cacheable;
use Bio::EnsEMBL::Hive::Semaphore;
use Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;
use Bio::EnsEMBL::Hive::Utils ('stringify', 'destringify');

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


# NOTE: These lists must be kept in sync with the schema !
# They are used in a number of queries.
our $ALL_STATUSES_OF_RUNNING_JOBS = q{'PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_HEALTHCHECK','POST_CLEANUP'};
our $ALL_STATUSES_OF_TAKEN_JOBS = qq{'CLAIMED',$ALL_STATUSES_OF_RUNNING_JOBS};
our $ALL_STATUSES_OF_COMPLETE_JOBS = q{'DONE','PASSED_ON'};
# Not in any list: SEMAPHORED, READY, COMPILATION (this one is actually not used), FAILED

sub default_table_name {
    return 'job';
}


sub default_insertion_method {
    return 'INSERT';
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


=head2 job_status_cast

  Example     : $job_adaptor->job_status_cast();
  Description : Returns a job-status expression that the SQL driver understands.
                This is needed for PostgreSQL
  Returntype  : String
  Exceptions  : none

=cut

sub job_status_cast {
    my ($self, $status_string) = @_;
    if ($self->dbc->driver eq 'pgsql') {
        return "CAST($status_string AS job_status)";
    } else {
        return $status_string;
    }
}


=head2 fetch_by_analysis_id_and_input_id

  Arg [1]    : Integer $analysis_id
  Arg [2]    : String $input_id
  Example    : $funnel_job = $job_adaptor->fetch_by_analysis_id_and_input_id( $funnel_job->analysis->dbID, $funnel_job->input_id);
  Description: Attempts to find the job by contents, then makes another attempt if the input_id is expected to have overflown into analysis_data
  Returntype : AnalysisJob object

=cut

sub fetch_by_analysis_id_and_input_id {     # It is a special case not covered by AUTOLOAD; note the lowercase _and_
    my ($self, $analysis_id, $input_id) = @_;

    my $job = $self->fetch_by_analysis_id_AND_input_id( $analysis_id, $input_id);

    if(!$job and length($input_id)>$self->default_overflow_limit->{input_id}) {
        if(my $ext_data_id = $self->db->get_AnalysisDataAdaptor->fetch_by_data_to_analysis_data_id( $input_id )) {
            $job = $self->fetch_by_analysis_id_AND_input_id( $analysis_id, "_extended_data_id $ext_data_id");
        }
    }
    return $job;
}


sub class_specific_execute {
    my ($self, $object, $sth, $values) = @_;

    my $return_code;

    eval {
        $return_code = $self->SUPER::class_specific_execute($object, $sth, $values);
        1;
    } or do {
        my $duplicate_regex = {
            'mysql'     => qr/Duplicate entry.+?for key/s,
            'sqlite'    => qr/columns.+?are not unique|UNIQUE constraint failed/s,  # versions around 3.8 spit the first msg, versions around 3.15 - the second
            'pgsql'     => qr/duplicate key value violates unique constraint/s,
        }->{$self->db->dbc->driver};

        if( $@ =~ $duplicate_regex ) {      # implementing 'INSERT IGNORE' of Jobs on the API side
            my $emitting_job_id = $object->prev_job_id;
            my $analysis_id     = $object->analysis_id;
            my $input_id        = $object->input_id;
            my $msg             = "Attempt to insert a duplicate job (analysis_id=$analysis_id, input_id=$input_id) intercepted and ignored";

            $self->db->get_LogMessageAdaptor->store_job_message( $emitting_job_id, $msg, 'INFO' );

            $return_code = '0E0';
        } else {
            die $@;
        }
    };

    return $return_code;
}


=head2 store_jobs_and_adjust_counters

  Arg [1]    : arrayref of Bio::EnsEMBL::Hive::AnalysisJob $jobs_to_store
  Arg [2]    : (optional) boolean $push_new_semaphore
  Arg [3]    : (optional) Int $emitting_job_id
  Example    : my @output_job_ids = @{ $job_adaptor->store_jobs_and_adjust_counters( \@jobs_to_store ) };
  Description: Attempts to store a list of jobs, returns an arrayref of successfully stored job_ids
  Returntype : Reference to list of job_dbIDs

=cut

sub store_jobs_and_adjust_counters {
    my ($self, $jobs, $push_new_semaphore, $emitting_job_id) = @_;

    my @output_job_ids                      = ();

        # NB: our use patterns assume all jobs from the same storing batch share the same controlled_semaphore:
    my $controlled_semaphore                = scalar(@$jobs) && $jobs->[0]->controlled_semaphore;
    my @jobs_that_failed_to_store           = ();

    if( $controlled_semaphore && !$push_new_semaphore ) {   # only if it has not been done yet
        $controlled_semaphore->increase_by( $jobs );  # "pre-increase" the semaphore counts before creating the controlling jobs
    }

    foreach my $job (@$jobs) {

        my $analysis    = $job->analysis;
        my $job_adaptor = $analysis ? $analysis->adaptor->db->get_AnalysisJobAdaptor : $self;   # if analysis object is undefined, consider the job local
        my $prev_adaptor= ($job->prev_job && $job->prev_job->adaptor) || '';
        my $job_is_local_to_parent  = $prev_adaptor eq $job_adaptor;

        if( $controlled_semaphore ) {
            my $job_hive_pipeline = $job->hive_pipeline;

            if( $controlled_semaphore->hive_pipeline ne $job_hive_pipeline ) {      # if $job happens to be remote to $controlled_semaphore,
                                                                                    # introduce another job-local semaphore between $job and $controlled_semaphore:
                my $job_local_semaphore = Bio::EnsEMBL::Hive::Semaphore->new(
                    'hive_pipeline'             => $job_hive_pipeline,
                    'dependent_semaphore_url'   => $controlled_semaphore->relative_url( $job_hive_pipeline ),
                    'local_jobs_counter'        => 1,
                    'remote_jobs_counter'       => 0,
                );
                $job_adaptor->db->get_SemaphoreAdaptor->store( $job_local_semaphore );

                $job->controlled_semaphore( $job_local_semaphore );
            }
        }

        if( $job_adaptor ne $prev_adaptor ) {
            $job->prev_job_id( undef );             # job_ids are local, so for remote jobs they have to be cleaned up before storing
        }

        my ($job, $stored_this_time) = $job_adaptor->store( $job );

        if($stored_this_time) {

            unless($job_adaptor->db->hive_pipeline->hive_use_triggers()) {
                $job_adaptor->dbc->do(qq{
                        UPDATE analysis_stats
                        SET total_job_count=total_job_count+1
                    }
                    .(($job->status eq 'READY')
                        ? " ,ready_job_count=ready_job_count+1 "
                        : " ,semaphored_job_count=semaphored_job_count+1 "
                    ).(($job_adaptor->dbc->driver eq 'pgsql')
                        ? " ,status = CAST(CASE WHEN status!='BLOCKED' THEN 'LOADING' ELSE 'BLOCKED' END AS analysis_status) "
                        : " ,status =      CASE WHEN status!='BLOCKED' THEN 'LOADING' ELSE 'BLOCKED' END "
                    )." WHERE analysis_id=".$job->analysis_id
                );
            }

            push @output_job_ids, $job->dbID();     # FIXME: this ID may not make much cross-db sense

        } else {
            push @jobs_that_failed_to_store, $job;

            my $msg = "JobAdaptor failed to store the "
                     . ($job_is_local_to_parent ? 'local' : 'remote')
                     . " Job( analysis_id=".$job->analysis_id.', '.$job->input_id." ), possibly due to a collision";
            if ($job_is_local_to_parent && $emitting_job_id) {
                $self->db->get_LogMessageAdaptor->store_job_message($emitting_job_id, $msg, 'PIPELINE_CAUTION');
            } else {
                $self->db->get_LogMessageAdaptor->store_hive_message($msg, 'PIPELINE_CAUTION');
            }

        }
    }

    if( $controlled_semaphore && scalar(@jobs_that_failed_to_store) ) {
        $controlled_semaphore->decrease_by( \@jobs_that_failed_to_store );
    }

    return \@output_job_ids;
}


=head2 store_a_semaphored_group_of_jobs

  Arg [1]    : Bio::EnsEMBL::Hive::AnalysisJob $funnel_job
  Arg [2]    : arrayref of Bio::EnsEMBL::Hive::AnalysisJob $fan_jobs
  Arg [3]    : (optional) Bio::EnsEMBL::Hive::AnalysisJob $emitting_job
  Arg [4]    : (optional) boolean $no_leeching
  Example    : my ($funnel_semaphore_id, $funnel_job_id, @fan_job_ids) = $job_adaptor->store_a_semaphored_group_of_jobs( $funnel_job, $fan_jobs, $emitting_job );
  Description: Attempts to store a semaphored group of jobs, returns a list of successfully stored job_ids
  Returntype : ($funnel_semaphore_id, $funnel_job_id, @fan_job_ids)

=cut

sub store_a_semaphored_group_of_jobs {
    my ($self, $funnel_job, $fan_jobs, $emitting_job, $no_leeching) = @_;

    my $emitting_job_id;

    if($emitting_job) {
        if($funnel_job) {
            $funnel_job->prev_job( $emitting_job );
            $funnel_job->controlled_semaphore( $emitting_job->controlled_semaphore );   # propagate parent's semaphore if any
        }
        $emitting_job_id = $emitting_job->dbID;
    }

    my $funnel_semaphore;
    my $funnel_semaphore_adaptor    = $self->db->get_SemaphoreAdaptor;  # assuming $self was $funnel_job_adaptor

    my ($funnel_job_id)     = $funnel_job ? @{ $self->store_jobs_and_adjust_counters( [ $funnel_job ], 0, $emitting_job_id) } : ();

    if($funnel_job && !$funnel_job_id) {    # apparently the funnel_job has been created previously, trying to leech to it:

        if($no_leeching) {
            die "The funnel job could not be stored, but leeching was not allowed, so bailing out";

        } elsif( $funnel_job = $self->fetch_by_analysis_id_and_input_id( $funnel_job->analysis->dbID, $funnel_job->input_id) ) {
            $funnel_job_id = $funnel_job->dbID;

            # If the job hasn't run yet, we can still block it
            if ($funnel_job->status eq 'READY') {
                # Mark the job as SEMAPHORED to make sure it's not taken by any worker
                $self->semaphore_job_by_id($funnel_job_id);
                $self->refresh($funnel_job);
            }

            if( $funnel_job->status eq 'SEMAPHORED' ) {

                $funnel_semaphore = $funnel_job->fetch_local_blocking_semaphore();

                # Create if it was missing
                unless ($funnel_semaphore) {
                    $funnel_semaphore = Bio::EnsEMBL::Hive::Semaphore->new(
                        'hive_pipeline'         => $funnel_job->hive_pipeline,
                        'dependent_job_id'      => $funnel_job_id,
                        'local_jobs_counter'    => 0,   # Will be updated below
                        'remote_jobs_counter'   => 0,   # Will be updated below
                    );
                    $funnel_semaphore_adaptor->store( $funnel_semaphore );
                }

                $funnel_semaphore->increase_by( $fan_jobs );  # "pre-increase" the semaphore counts before creating the controlling jobs

                $self->db->get_LogMessageAdaptor->store_job_message($emitting_job_id, "Discovered and using an existing funnel ".$funnel_job->toString, 'INFO');
            } else {
                die "The funnel job (id=$funnel_job_id) fetched from the database was not in SEMAPHORED status";
            }
        } else {
            die "The funnel job could neither be stored nor fetched";
        }
    } else {    # Either the $funnel_job was successfully stored, or there wasn't any $funnel_job to start with:

        my $whose_hive_pipeline = $funnel_job || $self->db;

        my ($local_count, $remote_count)    = Bio::EnsEMBL::Hive::Cacheable::count_local_and_remote_objects( $whose_hive_pipeline, $fan_jobs );

        $funnel_semaphore = Bio::EnsEMBL::Hive::Semaphore->new(
            'hive_pipeline'         => $whose_hive_pipeline->hive_pipeline,
            'dependent_job_id'      => $funnel_job_id,
            'local_jobs_counter'    => $local_count,
            'remote_jobs_counter'   => $remote_count,
        );
        $funnel_semaphore_adaptor->store( $funnel_semaphore );

        $funnel_semaphore->release_if_ripe();
    }

    foreach my $fan_job (@$fan_jobs) {  # set the funnel in every fan's job:
        $fan_job->controlled_semaphore( $funnel_semaphore );
    }

    my (@fan_job_ids) = @{ $self->store_jobs_and_adjust_counters( $fan_jobs, 1, $emitting_job_id) };

    return ($funnel_semaphore->dbID, $funnel_job_id, @fan_job_ids);
}



=head2 fetch_all_by_analysis_id_status

  Arg [1]    : (optional) listref $list_of_analyses
  Arg [2]    : (optional) string $status
  Arg [3]    : (optional) int $retry_at_least
  Example    : $all_failed_jobs = $adaptor->fetch_all_by_analysis_id_status(undef, 'FAILED');
               $analysis_done_jobs = $adaptor->fetch_all_by_analysis_id_status( $list_of_analyses, 'DONE');
  Description: Returns a list of all jobs filtered by given analysis_id (if specified) and given status (if specified).
  Returntype : reference to list of Bio::EnsEMBL::Hive::AnalysisJob objects

=cut

sub fetch_all_by_analysis_id_status {
    my ($self, $list_of_analyses, $status, $retry_count_at_least) = @_;

    my @constraints = ();

    if($list_of_analyses) {
        if(ref($list_of_analyses) eq 'ARRAY') {
            push @constraints, "analysis_id IN (".(join(',', map {$_->dbID} @$list_of_analyses)).")";
        } else {
            push @constraints, "analysis_id=$list_of_analyses"; # for compatibility with old interface
        }
    }

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

    my $constraint = "status IN ($ALL_STATUSES_OF_TAKEN_JOBS) AND role_id='$role_id'";
    return $self->fetch_all($constraint);
}


sub fetch_all_unfinished_jobs_with_no_roles {
    my $self = shift;

    return $self->fetch_all( "role_id IS NULL AND status IN ($ALL_STATUSES_OF_TAKEN_JOBS)" );
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

sub semaphore_job_by_id {    # used in the end of reblocking a semaphore chain
    my $self    = shift @_;
    my $job_id  = shift @_ or return;

    my $sql = "UPDATE job SET status = 'SEMAPHORED' WHERE job_id=? AND status NOT IN ('COMPILATION', $ALL_STATUSES_OF_TAKEN_JOBS)";

    $self->dbc->protected_prepare_execute( [ $sql, $job_id ],
        sub { my ($after) = @_; $self->db->get_LogMessageAdaptor->store_hive_message( 'semaphoring a job'.$after, 'INFO' ); }
    );
}

sub unsemaphore_job_by_id {    # used in semaphore annihilation or unsuccessful creation
    my $self    = shift @_;
    my $job_id  = shift @_ or return;

    my $sql = "UPDATE job SET status = 'READY' WHERE job_id=? AND status='SEMAPHORED'";

    $self->dbc->protected_prepare_execute( [ $sql, $job_id ],
        sub { my ($after) = @_; $self->db->get_LogMessageAdaptor->store_hive_message( 'unsemaphoring a job'.$after, 'INFO' ); }
    );
}


sub prelock_semaphore_for_update {  # currently defunct, but may be needed to resolve situations of heavy load on semaphore/job tables
    my $self    = shift @_;
    my $job_id  = shift @_ or return;

    if(my $dbc = $self->dbc) {
        if($dbc->driver ne 'sqlite') {
            $self->dbc->protected_prepare_execute( [ "SELECT 1 FROM job WHERE job_id=? FOR UPDATE", $job_id ],
                sub { my ($after) = @_; $self->db->get_LogMessageAdaptor->store_hive_message( "prelocking semaphore job_id=$job_id".$after, 0 ); }
            );
        }
    }
}


=head2 check_in_job

  Arg [1]    : $analysis_id
  Example    :
  Description: updates the job.status in the database
  Returntype : 
  Exceptions :
  Caller     : general

=cut

sub check_in_job {
    my ($self, $job) = @_;

    my $job_id = $job->dbID;

    my $sql = "UPDATE job SET status='".$job->status."' ";

    if($job->status eq 'DONE') {
        $sql .= ",when_completed=CURRENT_TIMESTAMP";
        $sql .= ",runtime_msec=".$job->runtime_msec;
        $sql .= ",query_count=".$job->query_count;
    } elsif($job->status eq 'PASSED_ON') {
        $sql .= ", when_completed=CURRENT_TIMESTAMP";
    } elsif($job->status eq 'READY') {
    }

    $sql .= " WHERE job_id='$job_id' ";

        # This particular query is infamous for collisions and 'deadlock' situations; let's wait and retry:
    $self->dbc->protected_prepare_execute( [ $sql ],
        sub { my ($after) = @_; $self->db->get_LogMessageAdaptor->store_job_message( $job_id, "checking the job in".$after, 'INFO' ); }
    );
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

    # FIXME: An UPSERT would be better here, but it is only promised in PostgreSQL starting from 9.5, which is not officially out yet.

    my $delete_sql  = 'DELETE from job_file WHERE job_id=' . $job->dbID . ' AND retry='.$job->retry_count;
    $self->dbc->do( $delete_sql );

    if($job->stdout_file or $job->stderr_file) {
        my $insert_sql = 'INSERT INTO job_file (job_id, retry, role_id, stdout_file, stderr_file) VALUES (?,?,?,?,?)';
        my $insert_sth = $self->dbc->prepare($insert_sql);
        $insert_sth->execute( $job->dbID, $job->retry_count, $job->role_id, $job->stdout_file, $job->stderr_file );
        $insert_sth->finish();
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

=head2 reset_or_grab_job_by_inputID

  Arg [1]    : string $analysis_id pattern
  Arg [2]    : string $input_id pattern
  Description: resets a job to to 'READY' or directly to 'CLAIMED' so it can be run again, and fetches it.
               The retry_count will be set to 1 for previously run jobs (partially or wholly) to trigger PRE_CLEANUP for them,
               but will not change retry_count if a job has never *really* started. $input_id can be a wildcard entry.
  Returntype : Bio::EnsEMBL::Hive::AnalysisJob or undef

=cut

sub reset_or_grab_job_by_analysis_id_and_input_id {
    my ($self, $analyses_pattern, $input_id_pattern) = @_;

    # Get list of job_id for given wildcard arguments
    my $sql_get_job_id = qq{
        SELECT job_id, status, analysis_id FROM job
         WHERE input_id LIKE ? AND analysis_id LIKE ?
    };
   
    my @values_get_job_id = ($input_id_pattern, $analyses_pattern);

    my $sth_get_job_id = $self->prepare( $sql_get_job_id ) or die "Unable to prepare" . $self->errstr;
    my $return_code_job_id = $sth_get_job_id->execute(@values_get_job_id)
        or die "Could not run\n\t$sql_get_job_id\nwith data:\n\t(".join(',', @values_get_job_id).')';
    if (! $sth_get_job_id){
            die "Could not find job_id and status for given input_id and analysis_pattern";
    }
    my ($job_id, $status, $analysis_id, @job_array);
    while (my (@row) = $sth_get_job_id->fetchrow_array){
       $job_id = $row[0];
       $status = $row[1];
       $analysis_id = $row[2];
       my %final_input_id = %{fetch_input_ids_for_job_ids($self, $job_id)};
       $self->reset_jobs_for_input_id($final_input_id{$job_id}, $status, $analysis_id);
       my $job = $self->fetch_by_analysis_id_and_input_id($analysis_id, $final_input_id{$job_id});
       push(@job_array, $job);
    }
    if (! $job_id){
        die "Could not find a job for given input_id and analysis_pattern";
    }
    $sth_get_job_id->finish;
    return @job_array;
}

sub reset_jobs_for_input_id {
    my ($self, $input_id, $status, $analysis_id) = @_;

    return if !scalar($status);  # No statuses to reset

    my $input_id_filter = 'j.input_id ='."'$input_id'";
    my $statuses_filter = 'AND j.status = '."'$status'";
    my $analyses_filter = 'AND j.analysis_id = '.$analysis_id;

    # Get the list of semaphores, and by how much their local_jobs_counter should be increased.
    # Only DONE and PASSED_ON jobs of the matching analyses and statuses should be counted
    #
    my $sql1 = qq{
        SELECT COUNT(*) AS local_delta, controlled_semaphore_id
        FROM job j
        WHERE controlled_semaphore_id IS NOT NULL
              AND $input_id_filter $statuses_filter $analyses_filter AND status IN ($ALL_STATUSES_OF_COMPLETE_JOBS)
        GROUP BY controlled_semaphore_id
    };

    # Run in a transaction to ensure we see a consistent state of the job
    # statuses and semaphore counts.
    $self->dbc->run_in_transaction( sub {

        my $semaphore_adaptor = $self->db->get_SemaphoreAdaptor;

        # Update all the semaphored jobs one by one
        my $sth1 = $self->prepare($sql1);
        $sth1->execute();
        while (my ($local_delta, $semaphore_id) = $sth1->fetchrow_array()) {

            my $semaphore = $semaphore_adaptor->fetch_by_dbID( $semaphore_id );
            $semaphore->reblock_by( $local_delta );                                 # increase the local_jobs_counter, reblock recursively if needed
        }
        $sth1->finish;

        # change fan jobs' statuses to 'READY', if they are themselves not SEMAPHORED
        my $sql3 = ($self->dbc->driver eq 'mysql') ? qq{
                UPDATE job j
             LEFT JOIN semaphore s
                    ON (j.job_id=s.dependent_job_id)
                   SET j.retry_count = CASE WHEN j.status='READY' THEN 0 ELSE 1 END,
                       j.status = }.$self->job_status_cast("CASE WHEN s.local_jobs_counter+s.remote_jobs_counter>0 THEN 'SEMAPHORED' ELSE 'READY' END").qq{
                 WHERE $input_id_filter $statuses_filter $analyses_filter
        } : ($self->dbc->driver eq 'pgsql') ? qq{
                UPDATE job
                   SET retry_count = CASE WHEN j.status='READY' THEN 0 ELSE 1 END,
                       status = }.$self->job_status_cast("CASE WHEN s.local_jobs_counter+s.remote_jobs_counter>0 THEN 'SEMAPHORED' ELSE 'READY' END").qq{
                  FROM job j
             LEFT JOIN semaphore s
                    ON (j.job_id=s.dependent_job_id)
                 WHERE job.job_id=j.job_id AND $input_id_filter $statuses_filter $analyses_filter
        } : qq{

            REPLACE INTO job (job_id, prev_job_id, analysis_id, input_id, param_id_stack, accu_id_stack, role_id, status, retry_count, when_completed, runtime_msec, query_count, controlled_semaphore_id)
                  SELECT j.job_id,
                         j.prev_job_id,
                         j.analysis_id,
                         j.input_id,
                         j.param_id_stack,
                         j.accu_id_stack,
                         j.role_id,
                         CASE WHEN s.local_jobs_counter+s.remote_jobs_counter>0 THEN 'SEMAPHORED' ELSE 'READY' END,
                         CASE WHEN j.status='READY' THEN 0 ELSE 1 END,
                         j.when_completed,
                         j.runtime_msec,
                         j.query_count,
                         j.controlled_semaphore_id
                    FROM job j
               LEFT JOIN semaphore s
                      ON (j.job_id=s.dependent_job_id)
                   WHERE $input_id_filter $statuses_filter $analyses_filter
        };

        $self->dbc->do($sql3);
        $self->db->get_AnalysisStatsAdaptor->update_status($analysis_id, 'LOADING');

    } ); # end of transaction
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

    return [] unless( $how_many_this_batch );
  
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

    my $claim_count;

        # we have to be explicitly numeric here because of '0E0' value returned by DBI if "no rows have been affected":
    if(  0 == ($claim_count = $self->dbc->protected_prepare_execute( [ $prefix_sql . $virgin_sql . $limit_sql . $offset_sql . $suffix_sql ],
                    sub { my ($after) = @_; $self->db->get_LogMessageAdaptor->store_worker_message( $role->worker, "grabbing a virgin batch of offset jobs".$after, 'INFO' ); }
    ))) {
        if( 0 == ($claim_count = $self->dbc->protected_prepare_execute( [ $prefix_sql .               $limit_sql . $offset_sql . $suffix_sql ],
                        sub { my ($after) = @_; $self->db->get_LogMessageAdaptor->store_worker_message( $role->worker, "grabbing a non-virgin batch of offset jobs".$after, 'INFO' ); }
        ))) {
             $claim_count = $self->dbc->protected_prepare_execute( [ $prefix_sql .               $limit_sql .               $suffix_sql ],
                            sub { my ($after) = @_; $self->db->get_LogMessageAdaptor->store_worker_message( $role->worker, "grabbing a non-virgin batch of non-offset jobs".$after, 'INFO' ); }
             );
        }
    }

    $self->db->get_AnalysisStatsAdaptor->increment_a_counter( 'ready_job_count', -$claim_count, $analysis_id );

    return $claim_count ? $self->fetch_all_by_role_id_AND_status($role_id, 'CLAIMED') : [];
}


sub release_claimed_jobs_from_role {
    my ($self, $role) = @_;

        # previous value of role_id is not important, because that Role never had a chance to run the jobs
    my $num_released_jobs = $self->dbc->protected_prepare_execute( [ "UPDATE job SET status='READY', role_id=NULL WHERE role_id=? AND status='CLAIMED'", $role->dbID ],
        sub { my ($after) = @_; $self->db->get_LogMessageAdaptor->store_worker_message( $role->worker, "releasing claimed jobs from role".$after, 'INFO' ); }
    );

    my $analysis_stats_adaptor  = $self->db->get_AnalysisStatsAdaptor;
    my $analysis_id             = $role->analysis_id;

    $analysis_stats_adaptor->increment_a_counter( 'ready_job_count', $num_released_jobs, $analysis_id );

#    $analysis_stats_adaptor->update_status( $analysis_id, 'LOADING' );
}


=head2 release_undone_jobs_from_role

  Arg [1]    : Bio::EnsEMBL::Hive::Role object
  Arg [2]    : optional message to be recorded in 'job_message' table
  Example    :
  Description: If a Worker has died some of its jobs need to be reset back to 'READY'
               so they can be rerun.
               Jobs in state CLAIMED as simply reset back to READY.
               If jobs was 'in progress' (see the $ALL_STATUSES_OF_RUNNING_JOBS variable)
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
    $self->release_claimed_jobs_from_role( $role );

    my $sth = $self->prepare( qq{
        SELECT job_id
          FROM job
         WHERE role_id='$role_id'
           AND status in ($ALL_STATUSES_OF_RUNNING_JOBS)
    } );
    $sth->execute();

    my $cod = $worker->cause_of_death() || 'UNKNOWN';
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

        $self->db()->get_LogMessageAdaptor()->store_job_message($job_id, $msg, $passed_on ? 'INFO' : 'WORKER_ERROR');

        unless($passed_on) {
            $self->release_and_age_job( $job_id, $max_retry_count, not $resource_overusage );
        }

        $role->register_attempt( 0 );
    }
    $sth->finish();
}


sub release_and_age_job {
    my ($self, $job_id, $max_retry_count, $may_retry, $runtime_msec) = @_;

    # Default values
    $max_retry_count //= $self->db->hive_pipeline->hive_default_max_retry_count;
    $may_retry ||= 0;
    $runtime_msec = "NULL" unless(defined $runtime_msec);

        # NB: The order of updated fields IS important. Here we first find out the new status and then increment the retry_count:
        #
        # FIXME: would it be possible to retain role_id for READY jobs in order to temporarily keep track of the previous (failed) worker?
        #
    $self->dbc->do( 
        "UPDATE job "
        .( ($self->dbc->driver eq 'pgsql')
            ? "SET status = CAST(CASE WHEN ($may_retry != 0) AND (retry_count<$max_retry_count) THEN 'READY' ELSE 'FAILED' END AS job_status), "
            : "SET status =      CASE WHEN $may_retry AND (retry_count<$max_retry_count) THEN 'READY' ELSE 'FAILED' END, "
         ).qq{
               retry_count=retry_count+1,
               runtime_msec=$runtime_msec
         WHERE job_id=$job_id
           AND status in ($ALL_STATUSES_OF_TAKEN_JOBS)
    } );

        # FIXME: move the decision making completely to the API side and so avoid the potential race condition.
    my $job         = $self->fetch_by_dbID( $job_id );

    $self->db->get_AnalysisStatsAdaptor->increment_a_counter( ($job->status eq 'FAILED') ? 'failed_job_count' : 'ready_job_count', 1, $job->analysis_id );
}


=head2 gc_dataflow

    Description:    perform automatic dataflow from a dead job that overused resources if a corresponding dataflow rule was provided
                    Should only be called once during garbage collection phase, when the job is definitely 'abandoned' and not being worked on.

=cut

sub gc_dataflow {
    my ($self, $analysis, $job_id, $branch_name) = @_;

    my $branch_code = Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor::branch_name_2_code($branch_name);

    unless( $analysis->dataflow_rules_by_branch->{$branch_code} ) {
        return 0;   # just return if no corresponding gc_dataflow rule has been defined
    }

    my $job = $self->fetch_by_dbID($job_id);
    $job->analysis( $analysis );

    $job->load_parameters();    # input_id_templates still supported, however to a limited extent

    $job->dataflow_output_id( undef, $branch_name );

    $job->set_and_update_status('PASSED_ON');

        # PASSED_ON jobs are included in done_job_count
    $self->db->get_AnalysisStatsAdaptor->increment_a_counter( 'done_job_count', 1, $analysis->dbID );

    if( my $controlled_semaphore = $job->controlled_semaphore ) {
        $controlled_semaphore->decrease_by( [ $job ] );
    }
    
    return 1;
}


=head2 reset_jobs_for_analysis_id

  Arg [1]    : arrayref of Analyses
  Arg [2]    : arrayref of job statuses $input_statuses
  Description: Resets all the jobs of the selected analyses that have one of the
               required statuses to 'READY' and their retry_count to 0.
               Semaphores are updated accordingly.
  Caller     : beekeeper.pl and guiHive

=cut

sub reset_jobs_for_analysis_id {
    my ($self, $list_of_analyses, $input_statuses) = @_;

    return if !scalar(@$input_statuses);  # No statuses to reset

    my $analyses_filter = 'j.analysis_id IN ('.join(',', map { $_->dbID } @$list_of_analyses).')';
    my $statuses_filter = 'AND j.status IN ('.join(', ', map { "'$_'" } @$input_statuses).')';

    # Get the list of semaphores, and by how much their local_jobs_counter should be increased.
    # Only DONE and PASSED_ON jobs of the matching analyses and statuses should be counted
    #
    my $sql1 = qq{
        SELECT COUNT(*) AS local_delta, controlled_semaphore_id
        FROM job j
        WHERE controlled_semaphore_id IS NOT NULL
              AND $analyses_filter $statuses_filter AND status IN ($ALL_STATUSES_OF_COMPLETE_JOBS)
        GROUP BY controlled_semaphore_id
    };

    # Run in a transaction to ensure we see a consistent state of the job
    # statuses and semaphore counts.
    $self->dbc->run_in_transaction( sub {

        my $semaphore_adaptor = $self->db->get_SemaphoreAdaptor;

        # Update all the semaphored jobs one by one
        my $sth1 = $self->prepare($sql1);
        $sth1->execute();
        while (my ($local_delta, $semaphore_id) = $sth1->fetchrow_array()) {

            my $semaphore = $semaphore_adaptor->fetch_by_dbID( $semaphore_id );
            $semaphore->reblock_by( $local_delta );                                 # increase the local_jobs_counter, reblock recursively if needed
        }
        $sth1->finish;

            # change fan jobs' statuses to 'READY', if they are themselves not SEMAPHORED
        my $sql3 = ($self->dbc->driver eq 'mysql') ? qq{
                UPDATE job j
             LEFT JOIN semaphore s
                    ON (j.job_id=s.dependent_job_id)
                   SET j.retry_count = CASE WHEN j.status='READY' THEN 0 ELSE 1 END,
                       j.status = }.$self->job_status_cast("CASE WHEN s.local_jobs_counter+s.remote_jobs_counter>0 THEN 'SEMAPHORED' ELSE 'READY' END").qq{
                 WHERE $analyses_filter $statuses_filter
        } : ($self->dbc->driver eq 'pgsql') ? qq{
                UPDATE job
                   SET retry_count = CASE WHEN j.status='READY' THEN 0 ELSE 1 END,
                       status = }.$self->job_status_cast("CASE WHEN s.local_jobs_counter+s.remote_jobs_counter>0 THEN 'SEMAPHORED' ELSE 'READY' END").qq{
                  FROM job j
             LEFT JOIN semaphore s
                    ON (j.job_id=s.dependent_job_id)
                 WHERE job.job_id=j.job_id AND $analyses_filter $statuses_filter
        } : qq{

            REPLACE INTO job (job_id, prev_job_id, analysis_id, input_id, param_id_stack, accu_id_stack, role_id, status, retry_count, when_completed, runtime_msec, query_count, controlled_semaphore_id)
                  SELECT j.job_id,
                         j.prev_job_id,
                         j.analysis_id,
                         j.input_id,
                         j.param_id_stack,
                         j.accu_id_stack,
                         j.role_id,
                         CASE WHEN s.local_jobs_counter+s.remote_jobs_counter>0 THEN 'SEMAPHORED' ELSE 'READY' END,
                         CASE WHEN j.status='READY' THEN 0 ELSE 1 END,
                         j.when_completed,
                         j.runtime_msec,
                         j.query_count,
                         j.controlled_semaphore_id
                    FROM job j
               LEFT JOIN semaphore s
                      ON (j.job_id=s.dependent_job_id)
                   WHERE $analyses_filter $statuses_filter
        };

        $self->dbc->do($sql3);

        foreach my $analysis ( @$list_of_analyses ) {
            $self->db->get_AnalysisStatsAdaptor->update_status($analysis->dbID, 'LOADING');
        }

    } ); # end of transaction
}


=head2 unblock_jobs_for_analysis_id

  Arg [1]    : list-ref of int $analysis_id
  Description: Sets all the SEMAPHORED jobs of the given analyses to READY and also unblocks their upstream semaphores
  Caller     : beekeeper.pl and guiHive

=cut

sub unblock_jobs_for_analysis_id {
    my ($self, $list_of_analyses) = @_;

    my $analyses_filter = 'analysis_id IN ('.join(',', map { $_->dbID } @$list_of_analyses).')';

    # Get the list of semaphored jobs together with their semaphores, and unblock both (previously semaphored jobs become 'READY')

    if($self->dbc->driver eq 'mysql') {     # MySQL supports updating multiple tables at once

        my $sql = qq{
          UPDATE job j
            JOIN semaphore s
              ON (j.job_id=s.dependent_job_id)
             SET s.local_jobs_counter=0, s.remote_jobs_counter=0, j.status = 'READY'
           WHERE $analyses_filter AND j.status = 'SEMAPHORED'
        };
        $self->dbc->do($sql);

    } elsif ($self->dbc->driver eq 'pgsql') {

        my $sql1 = qq{
          UPDATE semaphore s
             SET local_jobs_counter=0, remote_jobs_counter=0
            FROM job j
           WHERE $analyses_filter AND j.job_id = s.dependent_job_id AND j.status = 'SEMAPHORED'
        };
        $self->dbc->do($sql1);

        my $sql2 = qq{
          UPDATE job j
             SET status=}.$self->job_status_cast("'READY'").qq{
           WHERE $analyses_filter AND j.status = 'SEMAPHORED'
        };
        $self->dbc->do($sql2);

    } else {

        my $sql1 = qq{
    REPLACE INTO semaphore (semaphore_id, local_jobs_counter, remote_jobs_counter, dependent_job_id, dependent_semaphore_url)
          SELECT s.semaphore_id,
                 0,
                 0,
                 s.dependent_job_id,
                 s.dependent_semaphore_url
            FROM semaphore s
            JOIN job j
              ON (j.job_id = s.dependent_job_id)
           WHERE $analyses_filter AND j.status = 'SEMAPHORED'
        };
        $self->dbc->do($sql1);

        my $sql2 = qq{
          UPDATE job
             SET status=}.$self->job_status_cast("'READY'").qq{
           WHERE $analyses_filter AND status = 'SEMAPHORED'
        };
        $self->dbc->do($sql2);
    };

    foreach my $analysis ( @$list_of_analyses ) {
        $self->db->get_AnalysisStatsAdaptor->update_status($analysis->dbID, 'LOADING');
    }
}


=head2 discard_jobs_for_analysis_id

  Arg [1]    : list-ref of int $analysis_id
  Arg [2]    : filter status
  Description: Resets all $input_status jobs of the matching analyses to DONE.
               Semaphores are updated accordingly.
  Caller     : beekeeper.pl and guiHive

=cut

sub discard_jobs_for_analysis_id {
    my ($self, $list_of_analyses, $input_status) = @_;

    $self->balance_semaphores( $list_of_analyses );

    my $analyses_filter = 'analysis_id IN ('.join(',', map { $_->dbID } @$list_of_analyses).')';
    my $status_filter = $input_status ? " AND status = '$input_status'" : "";

    # Get the list of semaphores, and by how much their local_jobs_counter should be decreased.
    my $sql1 = qq{
        SELECT controlled_semaphore_id, COUNT(*) AS local_delta
        FROM job
        WHERE controlled_semaphore_id IS NOT NULL
              AND $analyses_filter $status_filter
        GROUP BY controlled_semaphore_id
    };

    my $sql2 = qq{
        UPDATE job
        SET status = }.$self->job_status_cast("'DONE'").qq{
        WHERE controlled_semaphore_id = ?
              AND $analyses_filter $status_filter
    };

    my $sql3 = qq{
        UPDATE job
        SET status = }.$self->job_status_cast("'DONE'").qq{
        WHERE controlled_semaphore_id IS NULL
              AND $analyses_filter $status_filter
    };

    # Run in a transaction to ensure we see a consistent state of the job
    # statuses and semaphore counts.
    $self->dbc->run_in_transaction( sub {

            # let's reset work on the jobs that don't have a controlled_semaphore_id
        $self->dbc->do($sql3);

        my $semaphore_adaptor = $self->db->get_SemaphoreAdaptor;

        # Update all the semaphored jobs one-by-one
        my $sth1 = $self->prepare($sql1);
        my $sth2 = $self->prepare($sql2);
        $sth1->execute();
        while (my ($semaphore_id, $local_delta) = $sth1->fetchrow_array()) {

            $sth2->execute( $semaphore_id );                                        # First mark the jobs as DONE

            my $semaphore = $semaphore_adaptor->fetch_by_dbID( $semaphore_id );
            $semaphore->decrease_by( $local_delta );                                # then decrease the local_jobs_counters, recursively releasing if ripe
        }
        $sth1->finish;
        $sth2->finish;

        my $analysis_stats_adaptor = $self->db->get_AnalysisStatsAdaptor;

        foreach my $analysis ( @$list_of_analyses ) {
            $analysis_stats_adaptor->update_status($analysis->dbID, 'LOADING');
        }

    } ); # end of transaction
}


=head2 balance_semaphores

  Description: Reset all semaphore_counts to the numbers of unDONE semaphoring jobs.

=cut

sub balance_semaphores {
    my ($self, $list_of_analyses) = @_;

    my $analysis_filter = $list_of_analyses
        ? "funnel.analysis_id IN (".join(',', map { $_->dbID } @$list_of_analyses).") AND"
        : '';

    my $find_sql    = qq{
                        SELECT * FROM (
                            SELECT s.semaphore_id, s.local_jobs_counter AS was, COALESCE(COUNT(CASE WHEN fan.status NOT IN ($ALL_STATUSES_OF_COMPLETE_JOBS) THEN 1 ELSE NULL END),0) AS should
                            FROM semaphore s
                            LEFT JOIN job fan ON (s.semaphore_id=fan.controlled_semaphore_id)
                            LEFT JOIN job funnel ON (s.dependent_job_id=funnel.job_id)
                            WHERE $analysis_filter
                            funnel.status in ('SEMAPHORED', 'READY')
                            GROUP BY s.semaphore_id
                         ) AS internal WHERE was<>should OR should=0
                     };

    my $rebalanced_jobs_counter = 0;

    # Run in a transaction to ensure we see a consistent state of the job
    # statuses and semaphore counts.
    $self->dbc->run_in_transaction( sub {

    my $find_sth            = $self->prepare($find_sql);
    my $semaphore_adaptor   = $self->db->get_SemaphoreAdaptor;

    $find_sth->execute();
    while(my ($semaphore_id, $was, $should) = $find_sth->fetchrow_array()) {
        my $msg;
        if($should<$was) {

            $msg = "Semaphore $semaphore_id local_jobs_counter has to be decreased $was -> $should, performing it now with a potential release";
            $self->db->get_LogMessageAdaptor->store_hive_message( $msg, 'PIPELINE_CAUTION' );

            my $semaphore = $semaphore_adaptor->fetch_by_dbID( $semaphore_id );
            $semaphore->decrease_by( $was-$should );                                # decrease the local_jobs_counter, recursively releasing if ripe

            $rebalanced_jobs_counter++;
        } elsif($was<$should) {

            $msg = "Semaphore $semaphore_id local_jobs_counter has to be increased $was -> $should, performing it now with a potential reblock";
            $self->db->get_LogMessageAdaptor->store_hive_message( $msg, 'PIPELINE_CAUTION' );

            my $semaphore = $semaphore_adaptor->fetch_by_dbID( $semaphore_id );
            $semaphore->reblock_by( $should-$was );                                 # increase the local_jobs_counter, reblock recursively if needed

            $rebalanced_jobs_counter++;
        } else {
            my $semaphore = $semaphore_adaptor->fetch_by_dbID( $semaphore_id );
            # check_if_ripe does the same but with an extra call to the database
            if( $semaphore->local_jobs_counter + $semaphore->remote_jobs_counter <= 0) {
                $msg = "Semaphore $semaphore_id is marked as blocked despite nothing blocking it, releasing it now";
                $self->db->get_LogMessageAdaptor->store_hive_message( $msg, 'PIPELINE_CAUTION' );

                $semaphore->release_if_ripe();
            }
        }
        warn "[Semaphore $semaphore_id] $msg\n" if $msg;    # TODO: integrate the STDERR diagnostic output with LogMessageAdaptor calls in general
    }
    $find_sth->finish;

    } ); # end of transaction

    return $rebalanced_jobs_counter;
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

