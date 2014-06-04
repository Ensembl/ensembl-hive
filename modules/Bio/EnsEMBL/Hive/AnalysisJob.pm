=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::AnalysisJob

=head1 DESCRIPTION

    An AnalysisJob is the link between the input_id control data, the analysis and
    the rule system.  It also tracks the state of the job as it is processed

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
    Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::AnalysisJob;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('stringify', 'destringify');
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;

use base (  'Bio::EnsEMBL::Hive::Storable', # inherit dbID(), adaptor() and new() methods
            'Bio::EnsEMBL::Hive::Params',   # inherit param management functionality
         );


=head1 AUTOLOADED

    prev_job_id / prev_job

    analysis_id / analysis

=cut


sub input_id {
    my $self = shift;
    if(@_) {
        my $input_id = shift @_;
        $self->{'_input_id'} = ref($input_id) ? stringify($input_id) : $input_id;
    }

    return $self->{'_input_id'};
}

sub param_id_stack {
    my $self = shift;
    $self->{'_param_id_stack'} = shift if(@_);
    $self->{'_param_id_stack'} = '' unless(defined($self->{'_param_id_stack'}));
    return $self->{'_param_id_stack'};
}

sub accu_id_stack {
    my $self = shift;
    $self->{'_accu_id_stack'} = shift if(@_);
    $self->{'_accu_id_stack'} = '' unless(defined($self->{'_accu_id_stack'}));
    return $self->{'_accu_id_stack'};
}

sub role_id {
    my $self = shift;
    $self->{'_role_id'} = shift if(@_);
    return $self->{'_role_id'};
}

sub status {
    my $self = shift;
    $self->{'_status'} = shift if(@_);
    $self->{'_status'} = ( ($self->semaphore_count>0) ? 'SEMAPHORED' : 'READY' ) unless(defined($self->{'_status'}));
    return $self->{'_status'};
}

sub retry_count {
    my $self = shift;
    $self->{'_retry_count'} = shift if(@_);
    $self->{'_retry_count'} = 0 unless(defined($self->{'_retry_count'}));
    return $self->{'_retry_count'};
}

sub completed {
    my $self = shift;
    $self->{'_completed'} = shift if(@_);
    return $self->{'_completed'};
}

sub runtime_msec {
    my $self = shift;
    $self->{'_runtime_msec'} = shift if(@_);
    $self->{'_runtime_msec'} = 0 unless(defined($self->{'_runtime_msec'}));
    return $self->{'_runtime_msec'};
}

sub query_count {
    my $self = shift;
    $self->{'_query_count'} = shift if(@_);
    $self->{'_query_count'} = 0 unless(defined($self->{'_query_count'}));
    return $self->{'_query_count'};
}

sub semaphore_count {
    my $self = shift;
    $self->{'_semaphore_count'} = shift if(@_);
    $self->{'_semaphore_count'} = 0 unless(defined($self->{'_semaphore_count'}));
    return $self->{'_semaphore_count'};
}

sub semaphored_job_id {
    my $self = shift;
    $self->{'_semaphored_job_id'} = shift if(@_);
    return $self->{'_semaphored_job_id'};
}


sub update_status {
    my ($self, $status ) = @_;
    $self->status($status);
    return unless($self->adaptor);
    $self->adaptor->update_status($self);
}

sub dataflow_rules {    # if ever set will prevent the Job from fetching rules from the DB
    my $self                = shift @_;
    my $branch_name_or_code = shift @_;

    my $branch_code = Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor::branch_name_2_code($branch_name_or_code);

    if(@_) {
        $self->{'_dataflow_rules'}{$branch_code} = shift @_;
    }

    $self->{'_dataflow_rules'} ||= $self->adaptor->db->get_DataflowRuleAdaptor->fetch_all_by_from_analysis_id_HASHED_FROM_branch_code( $self->analysis_id );

    return $self->{'_dataflow_rules'}{$branch_code} || [];
}

sub stdout_file {
  my $self = shift;
  $self->{'_stdout_file'} = shift if(@_);
  return $self->{'_stdout_file'};
}

sub stderr_file {
  my $self = shift;
  $self->{'_stderr_file'} = shift if(@_);
  return $self->{'_stderr_file'};
}

sub accu_hash {
    my $self = shift;
    $self->{'_accu_hash'} = shift if(@_);
    $self->{'_accu_hash'} = {} unless(defined($self->{'_accu_hash'}));
    return $self->{'_accu_hash'};
}


=head2 autoflow

    Title   :  autoflow
    Function:  Gets/sets flag for whether the job should
               be automatically dataflowed on branch 1 when the job completes.
               If the subclass manually sends a job along branch 1 with dataflow_output_id,
               the autoflow will turn itself off.
    Returns :  boolean (1=default|0)

=cut

sub autoflow {
  my $self = shift;

  $self->{'_autoflow'} = shift if(@_);
  $self->{'_autoflow'} = 1 unless(defined($self->{'_autoflow'}));  

  return $self->{'_autoflow'};
}


##-----------------[indicators to the Worker]--------------------------------


sub lethal_for_worker {     # Job should set this to 1 prior to dying (or before running code that might cause death - such as RunnableDB's compilation)
                            # if it believes that the state of things will not allow the Worker to continue normally.
                            # The Worker will check the flag and commit suicide if it is set to true.
    my $self = shift;
    $self->{'_lethal_for_worker'} = shift if(@_);
    return $self->{'_lethal_for_worker'};
}

sub transient_error {       # Job should set this to 1 prior to dying (or before running code that might cause death)
                            # if it believes that it makes sense to retry the same job without any changes.
                            # It may also set it to 0 prior to dying (or before running code that might cause death)
                            # if it believes that there is no point in re-trying (say, if the parameters are wrong).
                            # The Worker will check the flag and make necessary adjustments to the database state.
    my $self = shift;
    $self->{'_transient_error'} = shift if(@_);
    return $self->{'_transient_error'};
}

sub incomplete {            # Job should set this to 0 prior to throwing if the job is done,
                            # but it wants the thrown message to be recorded with is_error=0.
    my $self = shift;
    $self->{'_incomplete'} = shift if(@_);
    return $self->{'_incomplete'};
}

##-----------------[/indicators to the Worker]-------------------------------

=head2 warning

    Description:    records a non-error message in 'log_message' table linked to the current job

=cut

sub warning {
    my ($self, $msg) = @_;

    if( my $job_adaptor = $self->adaptor ) {
        $job_adaptor->db->get_LogMessageAdaptor()->store_job_message($self->dbID, $msg, 0);
    } else {
        print STDERR "Warning: $msg\n";
    }
}

sub fan_cache {     # a self-initializing getter (no setting)
                    # Returns a hash-of-lists { 2 => [list of jobs waiting to be funneled into 2], 3 => [list of jobs waiting to be funneled into 3], etc}
    my $self = shift;

    return $self->{'_fan_cache'} ||= {};
}

=head2 dataflow_output_id

    Title        :  dataflow_output_id
    Arg[1](req)  :  <string> $output_id 
    Arg[2](opt)  :  <int> $branch_name_or_code (optional, defaults to 1)
    Usage        :  $self->dataflow_output_id($output_id, $branch_name_or_code);
    Function:  
      If a RunnableDB(Process) needs to create jobs, this allows it to have jobs 
      created and flowed through the dataflow rules of the workflow graph.
      This 'output_id' becomes the 'input_id' of the newly created job at
      the ends of the dataflow pipes.  The optional 'branch_name_or_code' determines
      which dataflow pipe(s) to flow the job through.      

=cut

sub dataflow_output_id {
    my ($self, $output_ids, $branch_name_or_code, $create_job_options) = @_;

    my $input_id                = $self->input_id();
    my $param_id_stack          = $self->param_id_stack();
    my $accu_id_stack           = $self->accu_id_stack();

    my $job_adaptor             = $self->adaptor();
    my $hive_use_param_stack    = $job_adaptor && $job_adaptor->db->hive_use_param_stack();

    if($hive_use_param_stack) {
        if($input_id and ($input_id ne '{}')) {     # add the parent to the param_id_stack if it had non-trivial extra parameters
            $param_id_stack = ($param_id_stack ? $param_id_stack.',' : '').$self->dbID();
        }
        if(scalar(keys %{$self->accu_hash()})) {    # add the parent to the accu_id_stack if it had "own" accumulator
            $accu_id_stack = ($accu_id_stack ? $accu_id_stack.',' : '').$self->dbID();
        }
    }

    $output_ids  ||= [ $hive_use_param_stack ? {} : $input_id ];            # by default replicate the parameters of the parent in the child
    $output_ids    = [ $output_ids ] unless(ref($output_ids) eq 'ARRAY');   # force previously used single values into an arrayref

    if($create_job_options) {
        die "Please consider configuring semaphored dataflow from PipeConfig rather than setting it up manually";
    }

        # map branch names to numbers:
    my $branch_code = Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor::branch_name_2_code($branch_name_or_code);

        # if branch_code is set to 1 (explicitly or impliticly), turn off automatic dataflow:
    $self->autoflow(0) if($branch_code == 1);

    my @output_job_ids = ();

        # sort rules to make sure the fan rules come before funnel rules for the same branch_code:
    foreach my $rule (sort {($b->funnel_dataflow_rule_id||0) <=> ($a->funnel_dataflow_rule_id||0)} @{ $self->dataflow_rules( $branch_code ) }) {

            # parameter substitution into input_id_template is rule-specific
        my $output_ids_for_this_rule;
        if(my $template_string = $rule->input_id_template()) {
            my $template_hash = destringify($template_string);
            $output_ids_for_this_rule = [ map { $self->param_substitute($template_hash, $_) } @$output_ids ];
        } else {
            $output_ids_for_this_rule = $output_ids;
        }

        my $target_analysis_or_table = $rule->to_analysis();

        if($target_analysis_or_table->can('dataflow')) {

            $target_analysis_or_table->dataflow( $output_ids_for_this_rule, $self );

        } elsif(my $funnel_dataflow_rule_id = $rule->funnel_dataflow_rule_id()) {    # members of a semaphored fan will have to wait in cache until the funnel is created:

                my $fan_cache_this_branch = $self->fan_cache()->{$funnel_dataflow_rule_id} ||= [];
                push @$fan_cache_this_branch, map { Bio::EnsEMBL::Hive::AnalysisJob->new(
                                                        'prev_job'          => $self,
                                                        'analysis'          => $target_analysis_or_table,   # expecting an Analysis
                                                        'input_id'          => $_,
                                                        'param_id_stack'    => $param_id_stack,
                                                        'accu_id_stack'     => $accu_id_stack,
                                                        # semaphored_job_id  => to be set when the $funnel_job has been stored
                                                    ) } @$output_ids_for_this_rule;

        } else {    # either a semaphored funnel or a non-semaphored dataflow:

                my $fan_jobs = delete $self->fan_cache()->{$rule->dbID};   # clear the cache at the same time

                if($fan_jobs && @$fan_jobs) { # a semaphored funnel

                    if( (my $funnel_job_count = scalar(@$output_ids_for_this_rule)) !=1 ) {

                        $self->transient_error(0);
                        die "Asked to dataflow into $funnel_job_count funnel jobs instead of 1";

                    } else {
                        my $funnel_job = Bio::EnsEMBL::Hive::AnalysisJob->new(
                                            'prev_job'          => $self,
                                            'analysis'          => $target_analysis_or_table,   # expecting an Analysis
                                            'input_id'          => $output_ids_for_this_rule->[0],
                                            'param_id_stack'    => $param_id_stack,
                                            'accu_id_stack'     => $accu_id_stack,
                                            'semaphore_count'   => scalar(@$fan_jobs),          # "pre-increase" the semaphore count before creating the dependent jobs
                                            'semaphored_job_id' => $self->semaphored_job_id(),  # propagate parent's semaphore if any
                        );

                        my ($funnel_job_id) = @{ $job_adaptor->store_jobs_and_adjust_counters( [ $funnel_job ], 0) };
                        if($funnel_job_id) {    # if a semaphored funnel job creation succeeded, then store the fan out of the cache:

                            foreach my $fan_job (@$fan_jobs) {  # set the funnel in every fan's job:
                                $fan_job->semaphored_job_id( $funnel_job_id );
                            }
                            push @output_job_ids, $funnel_job_id, @{ $job_adaptor->store_jobs_and_adjust_counters( $fan_jobs, 1) };
                        }
                    }
                } else {    # non-semaphored dataflow (but potentially propagating any existing semaphores)
                    my @non_semaphored_jobs = map { Bio::EnsEMBL::Hive::AnalysisJob->new(
                                                        'prev_job'          => $self,
                                                        'analysis'          => $target_analysis_or_table,   # expecting an Analysis
                                                        'input_id'          => $_,
                                                        'param_id_stack'    => $param_id_stack,
                                                        'accu_id_stack'     => $accu_id_stack,
                                                        'semaphored_job_id' => $self->semaphored_job_id(),  # propagate parent's semaphore if any
                    ) } @$output_ids_for_this_rule;

                    push @output_job_ids, @{ $job_adaptor->store_jobs_and_adjust_counters( \@non_semaphored_jobs, 0) };
                }
        } # /if
    } # /foreach my $rule

    return \@output_job_ids;
}


sub toString {
    my $self = shift @_;

    my $analysis_label = $self->analysis
        ? ( $self->analysis->logic_name.'('.$self->analysis_id.')' )
        : '(NULL)';

    return 'Job '.$self->dbID." analysis=$analysis_label, input_id='".$self->input_id."', status=".$self->status.", retry_count=".$self->retry_count;
}


1;

