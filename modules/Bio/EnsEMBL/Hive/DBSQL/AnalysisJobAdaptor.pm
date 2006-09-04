# Perl module for Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor
#
# Date of creation: 22.03.2004
# Original Creator : Jessica Severin <jessica@ebi.ac.uk>
#
# Copyright EMBL-EBI 2004
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor

=head1 SYNOPSIS

  $analysisJobAdaptor = $db_adaptor->get_AnalysisJobAdaptor;
  $analysisJobAdaptor = $analysisJob->adaptor;

=head1 DESCRIPTION

  Module to encapsulate all db access for persistent class AnalysisJob.
  There should be just one per application and database connection.

=head1 CONTACT

  Contact Jessica Severin on implemetation/design detail: jessica@ebi.ac.uk
  Contact Ewan Birney on EnsEMBL in general: birney@sanger.ac.uk

=head1 APPENDIX

  The rest of the documentation details each of the object methods.
  Internal methods are preceded with a _

=cut


# Let the code begin...

package Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;

use strict;
use Bio::EnsEMBL::Hive::Worker;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Sys::Hostname;
use Data::UUID;

use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;

our @ISA = qw(Bio::EnsEMBL::DBSQL::BaseAdaptor);

our $max_retry_count = 7;

###############################################################################
#
#  CLASS methods
#
###############################################################################

=head2 CreateNewJob

  Args       : -input_id => string of input_id which will be passed to run the job
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

  my ($input_id, $analysis, $prev_analysis_job_id, $blocked) =
     rearrange([qw(INPUT_ID ANALYSIS input_job_id BLOCK )], @args);

  $prev_analysis_job_id=0 unless($prev_analysis_job_id);
  throw("must define input_id") unless($input_id);
  throw("must define analysis") unless($analysis);
  throw("analysis must be [Bio::EnsEMBL::Analysis] not a [$analysis]")
    unless($analysis->isa('Bio::EnsEMBL::Analysis'));
  throw("analysis must have adaptor connected to database")
    unless($analysis->adaptor and $analysis->adaptor->db);

  if(length($input_id) >= 255) {
    my $input_data_id = $analysis->adaptor->db->get_AnalysisDataAdaptor->store_if_needed($input_id);
    $input_id = "_ext_input_analysis_data_id $input_data_id";
  }

  my $sql = q{INSERT ignore into analysis_job 
              (input_id, prev_analysis_job_id,analysis_id,status)
              VALUES (?,?,?,?)};
 
  my $status ='READY';
  $status = 'BLOCKED' if($blocked);

  my $dbc = $analysis->adaptor->db->dbc;
  my $sth = $dbc->prepare($sql);
  $sth->execute($input_id, $prev_analysis_job_id, $analysis->dbID, $status);
  my $dbID = $sth->{'mysql_insertid'};
  $sth->finish;

  $dbc->do("UPDATE analysis_stats SET ".
           "total_job_count=total_job_count+1 ".
           ",unclaimed_job_count=unclaimed_job_count+1 ".
           ",status='LOADING' ".
           "WHERE status!='BLOCKED' and analysis_id='".$analysis->dbID ."'");

  return $dbID;
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
             a.hive_id	      
             a.status 
             a.retry_count          
             a.completed
             a.branch_code
             a.runtime_msec
             a.query_count
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
    $job->hive_id($column{'hive_id'});
    $job->status($column{'status'});
    $job->retry_count($column{'retry_count'});
    $job->completed($column{'completed'});
    $job->branch_code($column{'branch_code'});
    $job->runtime_msec($column{'runtime_msec'});
    $job->query_count($column{'query_count'});
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
    $sql .= ",completed=now(),branch_code=".$job->branch_code;
    $sql .= ",runtime_msec=".$job->runtime_msec;
    $sql .= ",query_count=".$job->query_count;
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

  my $sql = "UPDATE analysis_job SET status='CLAIMED', job_claim=?, hive_id=? WHERE analysis_job_id=?";

  #print("$sql\n");            
  my $sth = $self->prepare($sql);
  $sth->execute($job->job_claim, $job->hive_id, $job->dbID);
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

  my $sql = sprintf("DELETE from analysis_job_file WHERE hive_id=%d and analysis_job_id=%d",
                   $job->hive_id, $job->dbID);
  $self->dbc->do($sql);
  return unless($job->stdout_file or $job->stderr_file);

  $sql = "INSERT ignore INTO analysis_job_file (analysis_job_id, hive_id, retry, type, path) VALUES ";
  if($job->stdout_file) {
    $sql .= sprintf("(%d,%d,%d,'STDOUT','%s')", $job->dbID, $job->hive_id, 
		    $job->retry_count, $job->stdout_file); 
  }
  $sql .= "," if($job->stdout_file and $job->stderr_file);
  if($job->stderr_file) {
    $sql .= sprintf("(%d,%d,%d,'STDERR','%s')", $job->dbID, $job->hive_id, 
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
  #print("claiming jobs for hive_id=", $worker->hive_id, " with uuid $claim\n");

  my $sql_base = "UPDATE analysis_job SET job_claim='$claim'".
                 " , hive_id='". $worker->hive_id ."'".
                 " , status='CLAIMED'".
                 " WHERE job_claim='' and status='READY'". 
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
               the retry_count is incremented and the status set back to READY.
               If the retry_count >= $max_retry_count (7) the job is set to 'FAILED'
               and not rerun again.
  Exceptions : $worker must be defined
  Caller     : Bio::EnsEMBL::Hive::Queen

=cut

sub reset_dead_jobs_for_worker {
  my $self = shift;
  my $worker = shift;
  throw("must define worker") unless($worker);

  #added hive_id index to analysis_job table which made this operation much faster

  my ($sql, $sth);
  #first just reset the claimed jobs, these don't need a retry_count index increment
  $sql = "UPDATE analysis_job SET job_claim='', status='READY'".
         " WHERE status='CLAIMED'".
         " AND hive_id='" . $worker->hive_id ."'";
  $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;
  #print("  done update CLAIMED\n");

  # an update with select on status and hive_id took 4seconds per worker to complete,
  # while doing a select followed by update on analysis_job_id returned almost instantly
  
  $sql = "UPDATE analysis_job SET job_claim='', status='READY'".
         " ,retry_count=retry_count+1".
         " WHERE status in ('GET_INPUT','RUN','WRITE_OUTPUT')".
	 " AND retry_count<$max_retry_count".
         " AND hive_id='" . $worker->hive_id ."'";
  #print("$sql\n");
  $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;

  $sql = "UPDATE analysis_job SET status='FAILED'".
         " ,retry_count=retry_count+1".
         " WHERE status in ('GET_INPUT','RUN','WRITE_OUTPUT')".
	 " AND retry_count>=$max_retry_count".
         " AND hive_id='" . $worker->hive_id ."'";
  #print("$sql\n");
  $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;

  #print(" done update BROKEN jobs\n");
}


sub reset_dead_job_by_dbID {
  my $self = shift;
  my $job_id = shift;

  #added hive_id index to analysis_job table which made this operation much faster

  my $sql;
  #first just reset the claimed jobs, these don't need a retry_count index increment
  $sql = "UPDATE analysis_job SET job_claim='', status='READY'".
         " WHERE status='CLAIMED'".
         " AND analysis_job_id=$job_id";
  $self->dbc->do($sql);
  #print("  done update CLAIMED\n");

  # an update with select on status and hive_id took 4seconds per worker to complete,
  # while doing a select followed by update on analysis_job_id returned almost instantly
  
  $sql = "UPDATE analysis_job SET job_claim='', status='READY'".
         " ,retry_count=retry_count+1".
         " WHERE status in ('GET_INPUT','RUN','WRITE_OUTPUT')".
         " AND retry_count<$max_retry_count".
         " AND analysis_job_id=$job_id";
  #print("$sql\n");
  $self->dbc->do($sql);

  $sql = "UPDATE analysis_job SET status='FAILED'".
         " ,retry_count=retry_count+1".
         " WHERE status in ('GET_INPUT','RUN','WRITE_OUTPUT')".
         " AND retry_count>=$max_retry_count".
         " AND analysis_job_id=$job_id";
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
  $sql = "UPDATE analysis_job SET hive_id=0, job_claim='', status='READY' WHERE analysis_job_id=?";
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
  $sql = "DELETE FROM analysis WHERE analysis_id=$analysis_id";
  $self->dbc->do($sql);
  $sql = "DELETE FROM analysis_stats WHERE analysis_id=$analysis_id";
  $self->dbc->do($sql);
  $sql = "DELETE FROM analysis_job WHERE analysis_id=$analysis_id";
  $self->dbc->do($sql);

}


1;


