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
use Data::UUID;
use Sys::Hostname;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;
use Bio::EnsEMBL::Hive::Worker;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::Utils 'stringify';  # import 'stringify()'

use base ('Bio::EnsEMBL::DBSQL::BaseAdaptor');

# our $max_retry_count = 7;

###############################################################################
#
#  CLASS methods
#
###############################################################################

=head2 CreateNewJob

  Args       : -input_id => string of input_id which will be passed to run the job (or a Perl hash that will be automagically stringified)
               -analysis => Bio::EnsEMBL::Analysis object from a database
               -block        => int(0,1) set blocking state of job (default = 0)
               -input_job_id => (optional) analysis_job_id of job that is creating this
                                job.  Used purely for book keeping.
  Example    : $analysis_job_id = Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob(
                                    -input_id => 'my input data',
                                    -analysis => $myAnalysis);
  Description: uses the analysis object to get the db connection from the adaptor to store a new
               job in a hive.  This is a class level method since it does not have any state.
               Also updates corresponding analysis_stats by incrementing total_job_count,
               unclaimed_job_count and flagging the incremental update by changing the status
               to 'LOADING' (but only if the analysis is not blocked).
  Returntype : int analysis_job_id on database analysis is from.
  Exceptions : thrown if either -input_id or -analysis are not properly defined
  Caller     : general

=cut

sub CreateNewJob {
  my ($class, @args) = @_;

  return undef unless(scalar @args);

  my ($input_id, $analysis, $prev_analysis_job_id, $blocked, $semaphore_count, $semaphored_job_id) =
     rearrange([qw(INPUT_ID ANALYSIS INPUT_JOB_ID BLOCK SEMAPHORE_COUNT SEMAPHORED_JOB_ID)], @args);

  $prev_analysis_job_id ||=0;

  throw("must define input_id") unless($input_id);
  throw("must define analysis") unless($analysis);
  throw("analysis must be [Bio::EnsEMBL::Analysis] not a [$analysis]")
    unless($analysis->isa('Bio::EnsEMBL::Analysis'));
  throw("analysis must have adaptor connected to database")
    unless($analysis->adaptor and $analysis->adaptor->db);

  if(ref($input_id)) {  # let's do the Perl hash stringification centrally rather than in many places:
    $input_id = stringify($input_id);
  }

  if(length($input_id) >= 255) {
    my $input_data_id = $analysis->adaptor->db->get_AnalysisDataAdaptor->store_if_needed($input_id);
    $input_id = "_ext_input_analysis_data_id $input_data_id";
  }

  my $sql = q{INSERT ignore into analysis_job 
              (input_id, prev_analysis_job_id,analysis_id,status,semaphore_count,semaphored_job_id)
              VALUES (?,?,?,?,?,?)};
 
  my $status = $blocked ? 'BLOCKED' : 'READY';

  my $dbc = $analysis->adaptor->db->dbc;
  my $sth = $dbc->prepare($sql);
  $sth->execute($input_id, $prev_analysis_job_id, $analysis->dbID, $status, $semaphore_count, $semaphored_job_id);
  my $job_id = $sth->{'mysql_insertid'};
  $sth->finish;

  $dbc->do("UPDATE analysis_stats SET ".
           "total_job_count=total_job_count+1 ".
           ",unclaimed_job_count=unclaimed_job_count+1 ".
           ",status='LOADING' ".
           "WHERE status!='BLOCKED' and analysis_id='".$analysis->dbID ."'");

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
  Description: Returns the AnalysisJob defined by the analysis_job_id $id.
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


=head2 fetch_by_claim_analysis

  Arg [1]    : string job_claim (the UUID used to claim jobs)
  Arg [2]    : int analysis_id  
  Example    : $jobs = $adaptor->fetch_by_claim_analysis('c6658fde-64ab-4088-8526-2e960bd5dd60',208);
  Description: Returns a list of jobs for a claim id
  Returntype : Bio::EnsEMBL::Hive::AnalysisJob
  Exceptions : thrown if claim_id or analysis_id is not defined
  Caller     : general

=cut

sub fetch_by_claim_analysis {
  my ($self,$claim,$analysis_id) = @_;

  throw("fetch_by_claim_analysis must have claim ID") unless($claim);
  throw("fetch_by_claim_analysis must have analysis_id") unless($analysis_id);
  my $constraint = "a.status='CLAIMED' AND a.job_claim='$claim' AND a.analysis_id='$analysis_id'";
  return $self->_generic_fetch($constraint);
}

sub fetch_by_run_analysis {
  my ($self,$worker_id,$analysis_id) = @_;

  throw("fetch_by_run_analysis must have worker_id") unless($worker_id);
  throw("fetch_by_run_analysis must have analysis_id") unless($analysis_id);
  my $constraint = "a.status='RUN' AND a.worker_id=$worker_id AND a.analysis_id='$analysis_id'";
  return $self->_generic_fetch($constraint);
}


=head2 fetch_all

  Arg        : None
  Example    : 
  Description: fetches all jobs from database
  Returntype : 
  Exceptions : 
  Caller     : 

=cut

sub fetch_all {
  my $self = shift;

  return $self->_generic_fetch();
}

=head2 fetch_all_failed_jobs

  Arg [1]    : (optional) int $analysis_id
  Example    : $failed_jobs = $adaptor->fetch_all_failed_jobs;
               $failed_jobs = $adaptor->fetch_all_failed_jobs($analysis->dbID);
  Description: Returns a list of all jobs with status 'FAILED'.  If an $analysis_id 
               is specified it will limit the search accordingly.
  Returntype : reference to list of Bio::EnsEMBL::Hive::AnalysisJob objects
  Exceptions : none
  Caller     : user processes

=cut

sub fetch_all_failed_jobs {
  my ($self,$analysis_id) = @_;

  my $constraint = "a.status='FAILED'";
  $constraint .= " AND a.analysis_id=$analysis_id" if($analysis_id);
  return $self->_generic_fetch($constraint);
}


sub fetch_by_url_query
{
  my $self = shift;
  my $query = shift;

  return undef unless($query);
  #print("Bio::EnsEMBL::DBSQL::AnalysisAdaptor::fetch_by_url_query : $query\n");

  if((my $p=index($query, "=")) != -1) {
    my $type = substr($query,0, $p);
    my $value = substr($query,$p+1,length($query));

    if($type eq 'dbID') {
      return $self->fetch_by_dbID($value);
    }
  }
  return undef;
}

#
# INTERNAL METHODS
#
###################

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

  my $sth = $self->prepare($sql);
  $sth->execute;  

  #print STDOUT $sql,"\n";

  return $self->_objs_from_sth($sth);
}


sub _tables {
  my $self = shift;

  return (['analysis_job', 'a']);
}


sub _columns {
  my $self = shift;

  return qw (a.analysis_job_id  
             a.prev_analysis_job_id
             a.analysis_id	      
             a.input_id 
             a.job_claim  
             a.worker_id	      
             a.status 
             a.retry_count          
             a.completed
             a.runtime_msec
             a.query_count
             a.semaphore_count
             a.semaphored_job_id
            );
}

sub _default_where_clause {
  my $self = shift;
  return '';
}


sub _final_clause {
  my $self = shift;
  return 'ORDER BY retry_count';
}


sub _objs_from_sth {
  my ($self, $sth) = @_;
  
  my %column;
  $sth->bind_columns( \( @column{ @{$sth->{NAME_lc} } } ));

  my @jobs = ();
    
  while ($sth->fetch()) {
    my $job = new Bio::EnsEMBL::Hive::AnalysisJob;

    $job->dbID($column{'analysis_job_id'});
    $job->analysis_id($column{'analysis_id'});
    $job->input_id($column{'input_id'});
    $job->job_claim($column{'job_claim'});
    $job->worker_id($column{'worker_id'});
    $job->status($column{'status'});
    $job->retry_count($column{'retry_count'});
    $job->completed($column{'completed'});
    $job->runtime_msec($column{'runtime_msec'});
    $job->query_count($column{'query_count'});
    $job->semaphore_count($column{'semaphore_count'});
    $job->semaphored_job_id($column{'semaphored_job_id'});
    $job->adaptor($self);
    
    if($column{'input_id'} =~ /_ext_input_analysis_data_id (\d+)/) {
      #print("input_id was too big so stored in analysis_data table as dbID $1 -- fetching now\n");
      $job->input_id($self->db->get_AnalysisDataAdaptor->fetch_by_dbID($1));
    }

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
    my $jobid = shift @_;
    my $dec   = shift @_ || 1;

    my $sql = "UPDATE analysis_job SET semaphore_count=semaphore_count-? WHERE analysis_job_id=?";
    
    my $sth = $self->prepare($sql);
    $sth->execute($dec, $jobid);
    $sth->finish;
}

sub increase_semaphore_count_for_jobid {    # used in semaphore propagation
    my $self  = shift @_;
    my $jobid = shift @_;
    my $inc   = shift @_ || 1;

    my $sql = "UPDATE analysis_job SET semaphore_count=semaphore_count+? WHERE analysis_job_id=?";
    
    my $sth = $self->prepare($sql);
    $sth->execute($inc, $jobid);
    $sth->finish;
}


=head2 update_status

  Arg [1]    : $analysis_id
  Example    :
  Description: updates the analysis_job.status in the database
  Returntype : 
  Exceptions :
  Caller     : general

=cut

sub update_status {
  my ($self,$job) = @_;

  my $sql = "UPDATE analysis_job SET status='".$job->status."' ";
  if($job->status eq 'DONE') {
    $sql .= ",completed=now()";
    $sql .= ",runtime_msec=".$job->runtime_msec;
    $sql .= ",query_count=".$job->query_count;
  }
  if($job->status eq 'READY') {
    $sql .= ",job_claim=''";
  }
  $sql .= " WHERE analysis_job_id='".$job->dbID."' ";
  
  my $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;
}

sub reclaim_job {
  my $self   = shift;
  my $job    = shift;

  my $ug    = new Data::UUID;
  my $uuid  = $ug->create();
  $job->job_claim($ug->to_string( $uuid ));

  my $sql = "UPDATE analysis_job SET status='CLAIMED', job_claim=?, worker_id=? WHERE analysis_job_id=?";

  #print("$sql\n");            
  my $sth = $self->prepare($sql);
  $sth->execute($job->job_claim, $job->worker_id, $job->dbID);
  $sth->finish;
}


=head2 store_out_files

  Arg [1]    : Bio::EnsEMBL::Hive::AnalysisJob $job
  Example    :
  Description: if files are non-zero size, will update DB with location
  Returntype : 
  Exceptions :
  Caller     : Bio::EnsEMBL::Hive::Worker

=cut

sub store_out_files {
  my ($self,$job) = @_;

  return unless($job);

  my $sql = sprintf("DELETE from analysis_job_file WHERE worker_id=%d and analysis_job_id=%d",
                   $job->worker_id, $job->dbID);
  $self->dbc->do($sql);
  return unless($job->stdout_file or $job->stderr_file);

  $sql = "INSERT ignore INTO analysis_job_file (analysis_job_id, worker_id, retry, type, path) VALUES ";
  if($job->stdout_file) {
    $sql .= sprintf("(%d,%d,%d,'STDOUT','%s')", $job->dbID, $job->worker_id, 
		    $job->retry_count, $job->stdout_file); 
  }
  $sql .= "," if($job->stdout_file and $job->stderr_file);
  if($job->stderr_file) {
    $sql .= sprintf("(%d,%d,%d,'STDERR','%s')", $job->dbID, $job->worker_id, 
		    $job->retry_count, $job->stderr_file); 
  }
 
  $self->dbc->do($sql);
}


sub claim_jobs_for_worker {
  my $self     = shift;
  my $worker   = shift;

  throw("must define worker") unless($worker);

  my $ug    = new Data::UUID;
  my $uuid  = $ug->create();
  my $claim = $ug->to_string( $uuid );
  #print("claiming jobs for worker_id=", $worker->worker_id, " with uuid $claim\n");

  my $sql_base = "UPDATE analysis_job SET job_claim='$claim'".
                 " , worker_id='". $worker->worker_id ."'".
                 " , status='CLAIMED'".
                 " WHERE job_claim='' AND status='READY' AND semaphore_count<=0 ". 
                 " AND analysis_id='" .$worker->analysis->dbID. "'"; 

  my $sql_virgin = $sql_base .  
                   " AND retry_count=0".
                   " LIMIT " . $worker->batch_size;

  my $sql_any = $sql_base .  
                " LIMIT " . $worker->batch_size;
  
  my $claim_count = $self->dbc->do($sql_virgin);
  if($claim_count == 0) {
    $claim_count = $self->dbc->do($sql_any);
  }
  return $claim;
}


=head2 reset_dead_jobs_for_worker

  Arg [1]    : Bio::EnsEMBL::Hive::Worker object
  Example    :
  Description: If a worker has died some of its jobs need to be reset back to 'READY'
               so they can be rerun.
               Jobs in state CLAIMED as simply reset back to READY.
               If jobs was in a 'working' state (GET_INPUT, RUN, WRITE_OUTPUT)) 
               the retry_count is increased and the status set back to READY.
               If the retry_count >= $max_retry_count (3 by default) the job is set
               to 'FAILED' and not rerun again.
  Exceptions : $worker must be defined
  Caller     : Bio::EnsEMBL::Hive::Queen

=cut

sub reset_dead_jobs_for_worker {
  my $self = shift;
  my $worker = shift;
  throw("must define worker") unless($worker);

  #added worker_id index to analysis_job table which made this operation much faster

  my ($sql, $sth);
  my $max_retry_count = $worker->analysis->stats->max_retry_count();
  #first just reset the claimed jobs, these don't need a retry_count index increment
  $sql = "UPDATE analysis_job SET job_claim='', status='READY'".
         " WHERE status='CLAIMED'".
         " AND worker_id='" . $worker->worker_id ."'";
  $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;
  #print("  done update CLAIMED\n");

  # an update with select on status and worker_id took 4seconds per worker to complete,
  # while doing a select followed by update on analysis_job_id returned almost instantly
  
  $sql = "UPDATE analysis_job SET job_claim='', status='READY'".
         " ,retry_count=retry_count+1".
         " WHERE status in ('GET_INPUT','RUN','WRITE_OUTPUT')".
	 " AND retry_count<$max_retry_count".
         " AND worker_id='" . $worker->worker_id ."'";
  #print("$sql\n");
  $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;

  $sql = "UPDATE analysis_job SET status='FAILED'".
         " ,retry_count=retry_count+1".
         " WHERE status in ('GET_INPUT','RUN','WRITE_OUTPUT')".
	 " AND retry_count>=$max_retry_count".
         " AND worker_id='" . $worker->worker_id ."'";
  #print("$sql\n");
  $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;

  #print(" done update BROKEN jobs\n");
}


sub reset_dead_job_by_dbID {
  my $self = shift;
  my $job_id = shift;

  #added worker_id index to analysis_job table which made this operation much faster

  my $sql;
  #first just reset the claimed jobs, these don't need a retry_count index increment
  $sql = "UPDATE analysis_job SET job_claim='', status='READY'".
         " WHERE status='CLAIMED'".
         " AND analysis_job_id=$job_id";
  $self->dbc->do($sql);
  #print("  done update CLAIMED\n");

  # an update with select on status and worker_id took 4seconds per worker to complete,
  # while doing a select followed by update on analysis_job_id returned almost instantly
  
  $sql = "
    UPDATE analysis_job, analysis_stats
    SET job_claim='', analysis_job.status='READY', retry_count=retry_count+1
    WHERE
      analysis_job.status in ('GET_INPUT','RUN','WRITE_OUTPUT')
      AND analysis_job.analysis_id = analysis_stats.analysis_id
      AND retry_count < max_retry_count
      AND analysis_job_id=$job_id";
  #print("$sql\n");
  $self->dbc->do($sql);

  $sql = "
    UPDATE analysis_job, analysis_stats
    SET job_claim='', analysis_job.status='FAILED', retry_count=retry_count+1
    WHERE
      analysis_job.status in ('GET_INPUT','RUN','WRITE_OUTPUT')
      AND analysis_job.analysis_id = analysis_stats.analysis_id
      AND retry_count >= max_retry_count
      AND analysis_job_id=$job_id";
  #print("$sql\n");
  $self->dbc->do($sql);

  #print(" done update BROKEN jobs\n");
}


=head2 reset_job_by_dbID

  Arg [1]    : int $analysis_job_id
  Example    :
  Description: Forces a job to be reset to 'READY' so it can be run again.
               Will also reset a previously 'BLOCKED' jobs to READY.
  Exceptions : $job must be defined
  Caller     : user process

=cut

sub reset_job_by_dbID {
  my $self = shift;
  my $analysis_job_id   = shift;
  throw("must define job") unless($analysis_job_id);

  my ($sql, $sth);
  #first just reset the claimed jobs, these don't need a retry_count index increment
  $sql = "UPDATE analysis_job SET worker_id=0, job_claim='', status='READY', retry_count=0 WHERE analysis_job_id=?";
  $sth = $self->prepare($sql);
  $sth->execute($analysis_job_id);
  $sth->finish;
  #print("  done update CLAIMED\n");
}


=head2 reset_all_jobs_for_analysis_id

  Arg [1]    : int $analysis_id
  Example    :
  Description: Resets all not BLOCKED jobs back to READY so they can be rerun.
               Needed if an analysis/process modifies the dataflow rules as the
              system runs.  The jobs that are flowed 'from'  will need to be reset so
              that the output data can be flowed through the new rule.  
              If one is designing a system based on a need to change rules mid-process
              it is best to make sure such 'from' analyses that need to be reset are 'Dummy'
              types so that they can 'hold' the output from the previous step and not require
              the system to actually redo processing.
  Exceptions : $analysis_id must be defined
  Caller     : user RunnableDB subclasses which build dataflow rules on the fly

=cut

sub reset_all_jobs_for_analysis_id {
  my $self        = shift;
  my $analysis_id = shift;

  throw("must define analysis_id") unless($analysis_id);

  my ($sql, $sth);
  $sql = "UPDATE analysis_job SET job_claim='', status='READY' WHERE status!='BLOCKED' and analysis_id=?";
  $sth = $self->prepare($sql);
  $sth->execute($analysis_id);
  $sth->finish;

  $self->db->get_AnalysisStatsAdaptor->update_status($analysis_id, 'LOADING');
}

=head2 remove_analysis_id

  Arg [1]    : int $analysis_id
  Example    :
  Description: Remove the analysis from the database.
               Jobs should have been killed before.
  Exceptions : $analysis_id must be defined
  Caller     :

=cut

sub remove_analysis_id {
  my $self        = shift;
  my $analysis_id = shift;

  throw("must define analysis_id") unless($analysis_id);

  my $sql;
  #first just reset the claimed jobs, these don't need a retry_count index increment
  $sql = "DELETE FROM analysis_stats WHERE analysis_id=$analysis_id";
  $self->dbc->do($sql);
  $sql = "ANALYZE TABLE analysis_stats";
  $self->dbc->do($sql);
  $sql = "DELETE FROM analysis_job WHERE analysis_id=$analysis_id";
  $self->dbc->do($sql);
  $sql = "ANALYZE TABLE analysis_job";
  $self->dbc->do($sql);
  $sql = "DELETE FROM hive WHERE analysis_id=$analysis_id";
  $self->dbc->do($sql);
  $sql = "ANALYZE TABLE hive";
  $self->dbc->do($sql);

}

1;

