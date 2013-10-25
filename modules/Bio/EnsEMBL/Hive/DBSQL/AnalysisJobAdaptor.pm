# Perl module for Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor
#
# Date of creation: 22.03.2004
# Original Creator : Jessica Severin <jessica@ebi.ac.uk>
#
# Copyright EMBL-EBI 2004
#
# You may distribute this module under the same terms as perl itself

=pod

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor

=head1 SYNOPSIS

  $analysisJobAdaptor = $db_adaptor->get_AnalysisJobAdaptor;
  $analysisJobAdaptor = $analysisJob->adaptor;

=head1 DESCRIPTION

  Module to encapsulate all db access for persistent class AnalysisJob.
  There should be just one per application and database connection.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

  The rest of the documentation details each of the object methods.
  Internal methods are preceded with a _

=cut



package Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;

use strict;

use Bio::EnsEMBL::Utils::Argument ('rearrange');
use Bio::EnsEMBL::Utils::Exception ('throw');

use Bio::EnsEMBL::Hive::DBSQL::AnalysisDataAdaptor;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::Utils ('stringify');

use base ('Bio::EnsEMBL::DBSQL::BaseAdaptor');

###############################################################################
#
#  CLASS methods
#
###############################################################################

=head2 CreateNewJob

  Args       : -input_id => string of input_id which will be passed to run the job (or a Perl hash that will be automagically stringified)
               -analysis => Bio::EnsEMBL::Hive::Analysis object stored in the database
               -prev_job_id => (optional) job_id of job that is creating this job.
                               Used purely for book keeping.
  Example    : $job_id = Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob(
                                    -input_id => 'my input data',
                                    -analysis => $myAnalysis);
  Description: uses the analysis object to get the db connection from the adaptor to store a new
               job in a hive.  This is a class level method since it does not have any state.
               Also updates corresponding analysis_stats by incrementing total_job_count,
               ready_job_count and flagging the incremental update by changing the status
               to 'LOADING' (but only if the analysis is not blocked).
               NOTE: no AnalysisJob object is created in memory as the result of this call; it is simply a "fast store".
  Returntype : int job_id on database analysis is from.
  Exceptions : thrown if either -input_id or -analysis are not properly defined
  Caller     : general

=cut

sub CreateNewJob {
  my ($class, @args) = @_;

  my ($input_id, $param_id_stack, $accu_id_stack, $analysis, $prev_job, $prev_job_id, $semaphore_count, $semaphored_job_id, $push_new_semaphore) =
     rearrange([qw(input_id param_id_stack accu_id_stack analysis prev_job prev_job_id semaphore_count semaphored_job_id push_new_semaphore)], @args);

  throw("must define input_id") unless($input_id);
  throw("must define analysis") unless($analysis);
  throw("analysis must be [Bio::EnsEMBL::Hive::Analysis] not a [$analysis]")
    unless($analysis->isa('Bio::EnsEMBL::Hive::Analysis'));
  throw("analysis must have adaptor connected to database")
    unless($analysis->adaptor and $analysis->adaptor->db);
  throw("Please specify prev_job object instead of prev_job_id if available") if ($prev_job_id);   # 'obsolete' message

    $prev_job_id = $prev_job && $prev_job->dbID();

    if(ref($input_id)) {  # let's do the Perl hash stringification centrally rather than in many places:
        $input_id = stringify($input_id);
    }

    if(length($input_id) >= 255) {
        print "input_id is '$input_id', length = ".length($input_id)."\n";
        my $extended_data_id = $analysis->adaptor->db->get_AnalysisDataAdaptor->store_if_needed($input_id);
        $input_id = "_extended_data_id $extended_data_id";
    }

    if(length($param_id_stack) >= 64) {
        print "param_id_stack is '$param_id_stack', length = ".length($param_id_stack)."\n";
        my $extended_data_id = $analysis->adaptor->db->get_AnalysisDataAdaptor->store_if_needed($param_id_stack);
        $param_id_stack = "_extended_data_id $extended_data_id";
    }

    if(length($accu_id_stack) >= 64) {
        print "accu_id_stack is '$accu_id_stack', length = ".length($accu_id_stack)."\n";
        my $extended_data_id = $analysis->adaptor->db->get_AnalysisDataAdaptor->store_if_needed($accu_id_stack);
        $accu_id_stack = "_extended_data_id $extended_data_id";
    }


  $semaphore_count ||= 0;

  my $dba = $analysis->adaptor->db;
  my $dbc = $dba->dbc;
  my $insertion_method  = { 'mysql' => 'INSERT IGNORE', 'sqlite' => 'INSERT OR IGNORE', 'pgsql' => 'INSERT' }->{ $dbc->driver };
  my $job_status        = ($semaphore_count>0) ? 'SEMAPHORED' : 'READY';
  my $analysis_id       = $analysis->dbID();

    $dbc->do( "SELECT 1 FROM job WHERE job_id=$semaphored_job_id FOR UPDATE" ) if($semaphored_job_id and ($dbc->driver ne 'sqlite'));

  my $sql = qq{$insertion_method INTO job 
              (input_id, param_id_stack, accu_id_stack, prev_job_id,analysis_id,status,semaphore_count,semaphored_job_id)
              VALUES (?,?,?,?,?,?,?,?)};
 
  my $sth       = $dbc->prepare($sql);
  my @values    = ($input_id, $param_id_stack || '', $accu_id_stack || '', $prev_job_id, $analysis_id, $job_status, $semaphore_count, $semaphored_job_id);

  my $return_code = $sth->execute(@values)
            # using $return_code in boolean context allows to skip the value '0E0' ('no rows affected') that Perl treats as zero but regards as true:
        or die "Could not run\n\t$sql\nwith data:\n\t(".join(',', @values).')';

  my $job_id;
  if($return_code > 0) {    # <--- for the same reason we have to be explicitly numeric here:
      $job_id = $dbc->db_handle->last_insert_id(undef, undef, 'job', 'job_id');
      $sth->finish;

      if($semaphored_job_id and !$push_new_semaphore) {     # if we are not creating a new semaphore (where dependent jobs have already been counted),
                                                            # but rather propagating an existing one (same or other level), we have to up-adjust the counter
            $prev_job->adaptor->increase_semaphore_count_for_jobid( $semaphored_job_id );
      }

      unless($dba->hive_use_triggers()) {
          $dbc->do(qq{
            UPDATE analysis_stats
               SET total_job_count=total_job_count+1
          }
          .(($job_status eq 'READY')
                  ? " ,ready_job_count=ready_job_count+1 "
                  : " ,semaphored_job_count=semaphored_job_count+1 "
          ).(($dbc->driver eq 'pgsql')
          ? " ,status = CAST(CASE WHEN status!='BLOCKED' THEN 'LOADING' ELSE 'BLOCKED' END AS analysis_status) "
          : " ,status =      CASE WHEN status!='BLOCKED' THEN 'LOADING' ELSE 'BLOCKED' END "
          )." WHERE analysis_id=$analysis_id ");
      }
  } else {  #   if we got 0E0, it means "ignored insert collision" (job created previously), so we simply return an undef and deal with it outside
  }

  return $job_id;
}

###############################################################################
#
#  INSTANCE methods
#
###############################################################################

=head2 fetch_by_dbID

  Arg [1]    : int $id
               the unique database identifier for the feature to be obtained
  Example    : $feat = $adaptor->fetch_by_dbID(1234);
  Description: Returns the AnalysisJob defined by the job_id $id.
  Returntype : Bio::EnsEMBL::Hive::AnalysisJob
  Exceptions : thrown if $id is not defined
  Caller     : general

=cut

sub fetch_by_dbID {
  my ($self,$id) = @_;

  unless(defined $id) {
    throw("fetch_by_dbID must have an id");
  }

  my @tabs = $self->_tables;

  my ($name, $syn) = @{$tabs[0]};

  #construct a constraint like 't1.table1_id = 1'
  my $constraint = "${syn}.${name}_id = $id";

  #return first element of _generic_fetch list
  my ($obj) = @{$self->_generic_fetch($constraint)};
  return $obj;
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
    push @constraints, "j.analysis_id=$analysis_id"             if ($analysis_id);
    push @constraints, "j.status='$status'"                     if ($status);
    push @constraints, "j.retry_count >= $retry_count_at_least" if ($retry_count_at_least);
    return $self->_generic_fetch( join(" AND ", @constraints) );
}


sub fetch_some_by_analysis_id_limit {
    my ($self, $analysis_id, $limit) = @_;

    return $self->_generic_fetch( "j.analysis_id = '$analysis_id'", undef, "LIMIT $limit" );
}


sub fetch_all_incomplete_jobs_by_worker_id {
    my ($self, $worker_id) = @_;

    my $constraint = "j.status IN ('COMPILATION','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP') AND j.worker_id='$worker_id'";
    return $self->_generic_fetch($constraint);
}


sub fetch_by_url_query {
    my ($self, $field_name, $field_value) = @_;

    if($field_name eq 'dbID' and $field_value) {

        return $self->fetch_by_dbID($field_value);

    } else {

        return;

    }
}

#
# INTERNAL METHODS
#
###################

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

  my $sth = $self->prepare($sql);
  $sth->execute;  

  #print STDOUT $sql,"\n";

  return $self->_objs_from_sth($sth);
}


sub _tables {
  my $self = shift;

  return (['job', 'j']);
}


sub _columns {
  my $self = shift;

  return qw (j.job_id  
             j.prev_job_id
             j.analysis_id	      
             j.input_id 
             j.param_id_stack 
             j.accu_id_stack 
             j.worker_id	      
             j.status 
             j.retry_count          
             j.completed
             j.runtime_msec
             j.query_count
             j.semaphore_count
             j.semaphored_job_id
            );
}


sub _objs_from_sth {
  my ($self, $sth) = @_;
  
  my %column;
  $sth->bind_columns( \( @column{ @{$sth->{NAME_lc} } } ));

  my @jobs = ();
    
  while ($sth->fetch()) {

    my $input_id = ($column{'input_id'} =~ /^_ext(?:\w+)_data_id (\d+)$/)
            ? $self->db->get_AnalysisDataAdaptor->fetch_by_dbID($1)
            : $column{'input_id'};

    my $param_id_stack = ($column{'param_id_stack'} =~ /^_ext(?:\w+)_data_id (\d+)$/)
            ? $self->db->get_AnalysisDataAdaptor->fetch_by_dbID($1)
            : $column{'param_id_stack'};

    my $accu_id_stack = ($column{'accu_id_stack'} =~ /^_ext(?:\w+)_data_id (\d+)$/)
            ? $self->db->get_AnalysisDataAdaptor->fetch_by_dbID($1)
            : $column{'accu_id_stack'};


    my $job = Bio::EnsEMBL::Hive::AnalysisJob->new(
        -dbID               => $column{'job_id'},
        -analysis_id        => $column{'analysis_id'},
        -input_id           => $input_id,
        -param_id_stack     => $param_id_stack,
        -accu_id_stack      => $accu_id_stack,
        -worker_id          => $column{'worker_id'},
        -status             => $column{'status'},
        -retry_count        => $column{'retry_count'},
        -completed          => $column{'completed'},
        -runtime_msec       => $column{'runtime_msec'},
        -query_count        => $column{'query_count'},
        -semaphore_count    => $column{'semaphore_count'},
        -semaphored_job_id  => $column{'semaphored_job_id'},
        -adaptor            => $self,
    );

    push @jobs, $job;    
  }
  $sth->finish;
  
  return \@jobs
}


#
# STORE / UPDATE METHODS
#
################


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
        my $insert_sql = 'REPLACE INTO job_file (job_id, retry, worker_id, stdout_file, stderr_file) VALUES (?,?,?,?,?)';
        my $sth = $self->dbc()->prepare($insert_sql);
        $sth->execute($job->dbID(), $job->retry_count(), $job->worker_id(), $job->stdout_file(), $job->stderr_file());
        $sth->finish();
    } else {
        my $sql = 'DELETE from job_file WHERE worker_id='.$job->worker_id.' AND job_id='.$job->dbID;
        $self->dbc->do($sql);
    }
}


=head2 reset_or_grab_job_by_dbID

  Arg [1]    : int $job_id
  Arg [2]    : int $worker_id (optional)
  Description: resets a job to to 'READY' (if no $worker_id given) or directly to 'CLAIMED' so it can be run again, and fetches it..
               NB: Will also reset a previously 'SEMAPHORED' job to READY.
               The retry_count will be set to 1 for previously run jobs (partially or wholly) to trigger PRE_CLEANUP for them,
               but will not change retry_count if a job has never *really* started.
  Returntype : Bio::EnsEMBL::Hive::AnalysisJob or undef

=cut

sub reset_or_grab_job_by_dbID {
    my $self        = shift;
    my $job_id      = shift;
    my $worker_id   = shift;

    my $new_status  = ($worker_id?'CLAIMED':'READY');

        # Note: the order of the fields being updated is critical!
    my $sql = qq{
        UPDATE job
           SET retry_count = CASE WHEN (status='COMPILATION' OR status='READY' OR status='CLAIMED') THEN retry_count ELSE 1 END
             , status=?
             , worker_id=?
         WHERE job_id=?
    };
    my @values = ($new_status, $worker_id, $job_id);

    my $sth = $self->prepare( $sql );
    my $return_code = $sth->execute( @values )
        or die "Could not run\n\t$sql\nwith data:\n\t(".join(',', @values).')';
    $sth->finish;

    my $constraint = "j.job_id='$job_id' AND j.status='$new_status'";
    my ($job) = @{ $self->_generic_fetch($constraint) };

    return $job;
}


=head2 grab_jobs_for_worker

  Arg [1]           : Bio::EnsEMBL::Hive::Worker object $worker
  Example: 
    my $jobs  = $job_adaptor->grab_jobs_for_worker( $worker );
  Description: 
    For the specified worker, it will search available jobs, 
    and using the how_many_this_batch parameter, claim/fetch that
    number of jobs, and then return them.
  Returntype : 
    reference to array of Bio::EnsEMBL::Hive::AnalysisJob objects
  Caller     : Bio::EnsEMBL::Hive::Worker::run

=cut

sub grab_jobs_for_worker {
    my ($self, $worker, $how_many_this_batch) = @_;
  
  my $analysis_id = $worker->analysis_id();
  my $worker_id   = $worker->dbID();

  my $update_sql            = "UPDATE job SET worker_id='$worker_id', status='CLAIMED'";
  my $selection_start_sql   = " WHERE analysis_id='$analysis_id' AND status='READY'";

  my $virgin_selection_sql  = $selection_start_sql . " AND retry_count=0 LIMIT $how_many_this_batch";
  my $any_selection_sql     = $selection_start_sql . " LIMIT $how_many_this_batch";

  if($self->dbc->driver eq 'mysql') {
            # we have to be explicitly numeric here because of '0E0' value returned by DBI if "no rows have been affected":
      if( (my $claim_count = $self->dbc->do( $update_sql . $virgin_selection_sql )) == 0 ) {
            $claim_count = $self->dbc->do( $update_sql . $any_selection_sql );
      }
  } else {
            # we have to be explicitly numeric here because of '0E0' value returned by DBI if "no rows have been affected":
      if( (my $claim_count = $self->dbc->do( $update_sql . " WHERE job_id IN (SELECT job_id FROM job $virgin_selection_sql) AND status='READY'" )) == 0 ) {
            $claim_count = $self->dbc->do( $update_sql . " WHERE job_id IN (SELECT job_id FROM job $any_selection_sql) AND status='READY'" );
      }
  }

#  my $constraint = "j.analysis_id='$analysis_id' AND j.worker_id='$worker_id' AND j.status='CLAIMED'";
    my $constraint = "j.worker_id='$worker_id' AND j.status='CLAIMED'";
    return $self->_generic_fetch($constraint);
}


=head2 release_undone_jobs_from_worker

  Arg [1]    : Bio::EnsEMBL::Hive::Worker object
  Arg [2]    : optional message to be recorded in 'job_message' table
  Example    :
  Description: If a worker has died some of its jobs need to be reset back to 'READY'
               so they can be rerun.
               Jobs in state CLAIMED as simply reset back to READY.
               If jobs was 'in progress' (COMPILATION, PRE_CLEANUP, FETCH_INPUT, RUN, WRITE_OUTPUT, POST_CLEANUP) 
               the retry_count is increased and the status set back to READY.
               If the retry_count >= $max_retry_count (3 by default) the job is set
               to 'FAILED' and not rerun again.
  Exceptions : $worker must be defined
  Caller     : Bio::EnsEMBL::Hive::Queen

=cut

sub release_undone_jobs_from_worker {
    my ($self, $worker, $msg) = @_;

    my $max_retry_count = $worker->analysis->max_retry_count();
    my $worker_id       = $worker->dbID();
    my $analysis        = $worker->analysis();

        #first just reset the claimed jobs, these don't need a retry_count index increment:
        # (previous worker_id does not matter, because that worker has never had a chance to run the job)
    $self->dbc->do( qq{
        UPDATE job
           SET status='READY', worker_id=NULL
         WHERE worker_id='$worker_id'
           AND status='CLAIMED'
    } );

    my $sth = $self->prepare( qq{
        SELECT job_id
          FROM job
         WHERE worker_id='$worker_id'
           AND status in ('COMPILATION','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP')
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
        # FIXME: would it be possible to retain worker_id for READY jobs in order to temporarily keep track of the previous (failed) worker?
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
           AND status in ('COMPILATION','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP')
    } );
}

=head2 gc_dataflow

    Description:    perform automatic dataflow from a dead job that overused resources if a corresponding dataflow rule was provided
                    Should only be called once during garbage collection phase, when the job is definitely 'abandoned' and not being worked on.

=cut

sub gc_dataflow {
    my ($self, $analysis, $job_id, $branch_name) = @_;

    unless(@{ $self->db->get_DataflowRuleAdaptor->fetch_all_by_from_analysis_id_and_branch_code($analysis->dbID, $branch_name) }) {
        return 0;   # no corresponding gc_dataflow rule has been defined
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
           SET retry_count = CASE WHEN (status='COMPILATION' OR status='READY' OR status='CLAIMED') THEN 0 ELSE 1 END,
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
        ." semaphore_count=? , "
        .( ($self->dbc->driver eq 'pgsql')
        ? "status = CAST(CASE WHEN semaphore_count>0 THEN 'SEMAPHORED' ELSE 'READY' END AS jw_status) "
        : "status =      CASE WHEN semaphore_count>0 THEN 'SEMAPHORED' ELSE 'READY' END "
        )." WHERE job_id=? AND status='SEMAPHORED'";

    my $find_sth    = $self->prepare($find_sql);
    my $update_sth  = $self->prepare($update_sql);

    $find_sth->execute();
    while(my ($job_id, $was, $should) = $find_sth->fetchrow_array()) {
        warn "Balancing semaphore: job_id=$job_id ($was -> $should)\n";
        $update_sth->execute($should, $job_id);
        $self->db->get_LogMessageAdaptor->store_job_message( $job_id, "Re-balancing the semaphore_count: $was -> $should", 1 );
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
                $input_id = $self->db->get_AnalysisDataAdaptor->fetch_by_dbID($1);
            }
            $input_ids{$job_id * $id_scale + $id_offset} = $input_id;
        }
    }
    return \%input_ids;
}


1;

