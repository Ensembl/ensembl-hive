=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Analysis

=head1 DESCRIPTION

    An Analysis object represents a "stage" of the Hive pipeline that groups together
    all jobs that share the same module and the same common parameters.

    Individual Jobs are said to "belong" to an Analysis.

    Control rules unblock when their condition Analyses are done.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2021] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Analysis;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('stringify', 'throw');
use Bio::EnsEMBL::Hive::AnalysisCtrlRule;
use Bio::EnsEMBL::Hive::DataflowRule;
use Bio::EnsEMBL::Hive::GuestProcess;
use Bio::EnsEMBL::Hive::Utils::Collection;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;


use base ( 'Bio::EnsEMBL::Hive::Cacheable', 'Bio::EnsEMBL::Hive::Storable' );
 

sub unikey {    # override the default from Cacheable parent
    return [ 'logic_name' ];
}


=head1 AUTOLOADED

    resource_class_id / resource_class

=cut


sub logic_name {
    my $self = shift;
    $self->{'_logic_name'} = shift if(@_);
    return $self->{'_logic_name'};
}

sub name {              # a useful synonym
    my $self = shift;

    return $self->logic_name(@_);
}


sub module {
    my $self = shift;
    $self->{'_module'} = shift if(@_);
    return $self->{'_module'};
}


sub language {
    my $self = shift;
    $self->{'_language'} = shift if(@_);
    return $self->{'_language'};
}


sub parameters {
    my $self = shift;
    if(@_) {
        my $parameters = shift @_;
        $self->{'_parameters'} = ref($parameters) ? stringify($parameters) : $parameters;
    }
    return $self->{'_parameters'};
}


sub failed_job_tolerance {
    my $self = shift;
    $self->{'_failed_job_tolerance'} = shift if(@_);
    $self->{'_failed_job_tolerance'} = 0 unless(defined($self->{'_failed_job_tolerance'}));
    return $self->{'_failed_job_tolerance'};
}


sub max_retry_count {
    my $self = shift;
    $self->{'_max_retry_count'} = shift if(@_);
    $self->{'_max_retry_count'} = 3 unless(defined($self->{'_max_retry_count'}));
    return $self->{'_max_retry_count'};
}


sub can_be_empty {
    my $self = shift;
    $self->{'_can_be_empty'} = shift if(@_);
    $self->{'_can_be_empty'} = 0 unless(defined($self->{'_can_be_empty'}));
    return $self->{'_can_be_empty'};
}


sub priority {
    my $self = shift;
    $self->{'_priority'} = shift if(@_);
    $self->{'_priority'} = 0 unless(defined($self->{'_priority'}));
    return $self->{'_priority'};
}


sub meadow_type {
    my $self = shift;
    $self->{'_meadow_type'} = shift if(@_);
    return $self->{'_meadow_type'};
}


sub analysis_capacity {
    my $self = shift;
    $self->{'_analysis_capacity'} = shift if(@_);
    return $self->{'_analysis_capacity'};
}


sub get_compiled_module_name {
    my $self = shift;

    my $runnable_module_name = $self->module
        or die "Analysis '".$self->logic_name."' does not have its 'module' defined";

    if ($self->language) {
        my $wrapper = Bio::EnsEMBL::Hive::GuestProcess::_get_wrapper_for_language($self->language);
        if (system($wrapper, 'compile', $runnable_module_name)) {
            die "The runnable module '$runnable_module_name' cannot be loaded or compiled:\n";
        }
        return 'Bio::EnsEMBL::Hive::GuestProcess';
    }

    eval "require $runnable_module_name";
    die "The runnable module '$runnable_module_name' cannot be loaded or compiled:\n$@" if($@);
    die "Problem accessing methods in '$runnable_module_name'. Please check that it inherits from Bio::EnsEMBL::Hive::Process and is named correctly.\n"
        unless($runnable_module_name->isa('Bio::EnsEMBL::Hive::Process'));

    die "DEPRECATED: the strict_hash_format() method is no longer supported in Runnables - the input_id() in '$runnable_module_name' has to be a hash now.\n"
        if($runnable_module_name->can('strict_hash_format'));

    return $runnable_module_name;
}


=head2 url

  Arg [1]    : none
  Example    : $url = $analysis->url;
  Description: Constructs a URL string for this database connection
               Follows the general URL rules.
  Returntype : string of format
               mysql://<user>:<pass>@<host>:<port>/<dbname>/analysis?logic_name=<name>
  Exceptions : none
  Caller     : general

=cut

sub url {
    my ($self, $ref_dba) = @_;  # if reference dba is the same as 'my' dba, a shorter url is generated

    my $my_dba = $self->adaptor && $self->adaptor->db;
    return ( ($my_dba and $my_dba ne ($ref_dba//'') ) ? $my_dba->dbc->url.'?logic_name=' : '') . $self->logic_name;
}


sub display_name {
    my ($self) = @_;
    return $self->logic_name;
}


=head2 stats

  Arg [1]    : none
  Example    : $stats = $analysis->stats;
  Description: returns either the previously cached AnalysisStats object, or if it is missing - pulls a fresh one from the DB.
  Returntype : Bio::EnsEMBL::Hive::AnalysisStats object
  Exceptions : none
  Caller     : general

=cut

sub stats {
    my $self = shift @_;

    return $self->hive_pipeline->collection_of( 'AnalysisStats' )->find_one_by('analysis', $self);
}


# --------------------------------- dispatch the following calls directly to our Stats: ---------------------------------------

sub status {
    my $self = shift @_;

    return $self->stats->status(@_);
}

sub batch_size {
    my $self = shift @_;

    return $self->stats->batch_size(@_);
}

sub hive_capacity {
    my $self = shift @_;

    return $self->stats->hive_capacity(@_);
}

# ------------------------------------------------------------------------------------------------------------------------------


sub jobs_collection {
    my $self = shift @_;

    $self->{'_jobs_collection'} = shift if(@_);

    return $self->{'_jobs_collection'} ||= [];
}


sub control_rules_collection {
    my $self = shift @_;

    return $self->hive_pipeline->collection_of( 'AnalysisCtrlRule' )->find_all_by('ctrled_analysis', $self);
}


sub dataflow_rules_collection {
    my $self = shift @_;

    return $self->hive_pipeline->collection_of( 'DataflowRule' )->find_all_by('from_analysis', $self);
}


=head2 get_grouped_dataflow_rules

  Args       : none
  Example    : $groups = $analysis->get_grouped_dataflow_rules;
  Description: returns a listref of pairs, where the first element is a separate dfr or a funnel, and the second element is a listref of semaphored fan dfrs
  Returntype : listref

=cut

sub get_grouped_dataflow_rules {
    my $self = shift @_;

    my %set_of_groups = ();     # Note that the key (being a stringified reference) is unusable,
                                # so we end up packing it as the first element of the structure,
                                # and only returning the listref of the values.

    foreach my $dfr ( sort { ($b->funnel_dataflow_rule // 0) <=> ($a->funnel_dataflow_rule // 0) } @{$self->dataflow_rules_collection}) {

        my $df_targets = $dfr->get_my_targets;

        if(my $funnel_dfr = $dfr->funnel_dataflow_rule) {
            unless($set_of_groups{$funnel_dfr}) {   # both the type check and the initial push will only be done once per funnel
                my $funnel_targets = $funnel_dfr->get_my_targets;
                foreach my $funnel_target (@$funnel_targets) {
                    unless($funnel_target->to_analysis->isa('Bio::EnsEMBL::Hive::Analysis')) {
                        throw("Each conditional branch of a semaphored funnel rule must point at an Analysis");
                    }
                }
                $set_of_groups{$funnel_dfr} = [$funnel_dfr, [], $funnel_targets];
            }
            my $this_group = $set_of_groups{$funnel_dfr};

            foreach my $df_target (@$df_targets) {
                unless($df_target->to_analysis->isa('Bio::EnsEMBL::Hive::Analysis')) {
                    throw("Each conditional branch of a semaphored fan rule must point at an Analysis");
                }
            }
            push @{$this_group->[1]}, $dfr;
        } else {
            $set_of_groups{$dfr} ||= [$dfr, [], $df_targets];
        }
    }
    return [ sort { scalar(@{$a->[1]}) <=> scalar(@{$b->[1]}) or $a->[0]->branch_code <=> $b->[0]->branch_code } values %set_of_groups ];
}


sub dataflow_rules_by_branch {
    my $self = shift @_;

    if (not $self->{'_dataflow_rules_by_branch'}) {
        my %dataflow_rules_by_branch = ();
        foreach my $df_rule (@{$self->dataflow_rules_collection}) {
            my $dfr_bb = $dataflow_rules_by_branch{ $df_rule->branch_code } ||= []; # no autovivification here, have to do it manually

            if($df_rule->funnel_dataflow_rule) {    # sort rules so that semaphored fan rules come before other (potentially fan) rules for the same branch_code
                unshift @$dfr_bb, $df_rule;
            } else {
                push @$dfr_bb, $df_rule;
            }
        }
        $self->{'_dataflow_rules_by_branch'} = \%dataflow_rules_by_branch;
    }

    return $self->{'_dataflow_rules_by_branch'};
}


sub dataflow {
    my ( $self, $output_ids_for_this_rule, $emitting_job, $push_emitting_job_on_stack, $df_rule ) = @_;

    my $param_id_stack  = $emitting_job->param_id_stack;
    my $accu_id_stack   = $emitting_job->accu_id_stack;

    if($push_emitting_job_on_stack) {
        my $input_id        = $emitting_job->input_id;
        my $accu_hash       = $emitting_job->accu_hash;
        my $emitting_job_id = $emitting_job->dbID;

        if($input_id and ($input_id ne '{}')) {     # add the parent to the param_id_stack if it had non-trivial extra parameters
            $param_id_stack = ($param_id_stack ? $param_id_stack.',' : '').$emitting_job_id;
        }
        if(scalar(keys %$accu_hash)) {    # add the parent to the accu_id_stack if it had "own" accumulator
            $accu_id_stack = ($accu_id_stack ? $accu_id_stack.',' : '').$emitting_job_id;
        }
    }

    my $common_params = [
        'prev_job'          => $emitting_job,
        'analysis'          => $self,
        'param_id_stack'    => $param_id_stack,
        'accu_id_stack'     => $accu_id_stack,
    ];

    my $job_adaptor     = $self->adaptor->db->get_AnalysisJobAdaptor;
    my @output_job_ids  = ();

    if( my $funnel_dataflow_rule = $df_rule->funnel_dataflow_rule ) {    # members of a semaphored fan will have to wait in cache until the funnel is created:

        my $fan_cache_this_branch = $emitting_job->fan_cache->{"$funnel_dataflow_rule"} ||= [];
        push @$fan_cache_this_branch, map { Bio::EnsEMBL::Hive::AnalysisJob->new(
                                                @$common_params,
                                                'input_id'          => $_,
                                                # semaphored_job_id  => to be set when the $funnel_job has been stored
                                            ) } @$output_ids_for_this_rule;

    } else {    # either a semaphored funnel or a non-semaphored dataflow:

        my $fan_jobs = delete $emitting_job->fan_cache->{"$df_rule"};   # clear the cache at the same time

        if( $fan_jobs && @$fan_jobs ) { # a semaphored funnel

            if( (my $funnel_job_count = scalar(@$output_ids_for_this_rule)) !=1 ) {

                $emitting_job->transient_error(0);
                die "Asked to dataflow into $funnel_job_count funnel jobs instead of 1";

            } else {
                my $funnel_job = Bio::EnsEMBL::Hive::AnalysisJob->new(
                                    @$common_params,
                                    'input_id'          => $output_ids_for_this_rule->[0],
                                    'semaphore_count'   => scalar(@$fan_jobs),          # "pre-increase" the semaphore count before creating the dependent jobs
                                    'semaphored_job_id' => $emitting_job->semaphored_job_id(),  # propagate parent's semaphore if any
                );

                my ($funnel_job_id) = @{ $job_adaptor->store_jobs_and_adjust_counters( [ $funnel_job ], 0) };

                unless($funnel_job_id) {    # apparently it has been created previously, trying to leech to it:

                    if( $funnel_job = $job_adaptor->fetch_by_analysis_id_and_input_id( $funnel_job->analysis->dbID, $funnel_job->input_id) ) {
                        $funnel_job_id = $funnel_job->dbID;

                        if( $funnel_job->status eq 'SEMAPHORED' ) {
                            $job_adaptor->increase_semaphore_count_for_jobid( $funnel_job_id, scalar(@$fan_jobs) );    # "pre-increase" the semaphore count before creating the dependent jobs

                            $job_adaptor->db->get_LogMessageAdaptor->store_job_message($emitting_job->dbID, "Discovered and using an existing funnel ".$funnel_job->toString, 0);
                        } else {
                            die "The funnel job (id=$funnel_job_id) fetched from the database was not in SEMAPHORED status";
                        }
                    } else {
                        die "The funnel job could neither be stored nor fetched";
                    }
                }

                foreach my $fan_job (@$fan_jobs) {  # set the funnel in every fan's job:
                    $fan_job->semaphored_job_id( $funnel_job_id );
                }
                push @output_job_ids, $funnel_job_id, @{ $job_adaptor->store_jobs_and_adjust_counters( $fan_jobs, 1) };

            }
        } else {    # non-semaphored dataflow (but potentially propagating any existing semaphores)
            my @non_semaphored_jobs = map { Bio::EnsEMBL::Hive::AnalysisJob->new(
                                                @$common_params,
                                                'input_id'          => $_,
                                                'semaphored_job_id' => $emitting_job->semaphored_job_id(),  # propagate parent's semaphore if any
            ) } @$output_ids_for_this_rule;

            push @output_job_ids, @{ $job_adaptor->store_jobs_and_adjust_counters( \@non_semaphored_jobs, 0) };
        }
    } # /if funnel

    return \@output_job_ids;
}


sub toString {
    my $self = shift @_;

    return 'Analysis['.($self->dbID // '').']: '.$self->display_name.'->('.join(', ', ($self->module // 'no_module').($self->language ? sprintf(' (%s)', $self->language) : ''), $self->parameters // '{}', $self->resource_class ? $self->resource_class->name : 'no_rc').')';
}


sub print_diagram_node {
    my ($self, $ref_pipeline, $prefix, $seen_analyses) = @_;

    if($seen_analyses->{$self}++) {
        print "(".$self->relative_display_name($ref_pipeline).")\n";  # NB: the prefix of the label itself is done by the previous level
        return;
    }

    print $self->relative_display_name($ref_pipeline)."\n";  # NB: the prefix of the label itself is done by the previous level

    my $groups = $self->get_grouped_dataflow_rules;

    foreach my $i (0..scalar(@$groups)-1) {

        my ($funnel_dfr, $fan_dfrs, $df_targets) = @{ $groups->[$i] };

        my $this_funnel_offset  = '';

        if(scalar(@$groups)>1 and scalar(@$fan_dfrs)) {     # if more than one group (no single backbone) and semaphored, the semaphored group will be offset:
            print $prefix." │\n";
            print $prefix." ╘════╤══╗\n";   # " └────┬──┐\n";
            $this_funnel_offset = ($i < scalar(@$groups)-1) ? ' │   ' : '     ';    # non-last vs last group
        }

        foreach my $j (0..scalar(@$fan_dfrs)-1) {   # for each of the dependent fan rules, show them one by one:
            my $fan_dfr     = $fan_dfrs->[$j];
            my $fan_branch  = $fan_dfr->branch_code;

            print $prefix.$this_funnel_offset." │  ║\n";
            print $prefix.$this_funnel_offset." │  ║\n";
            print $prefix.$this_funnel_offset." │  ║#$fan_branch\n";

            my $fan_df_targets = $fan_dfr->get_my_targets;

            foreach my $k (0..scalar(@$fan_df_targets)-1) {   # for each fan's target
                my $fan_target = $fan_df_targets->[$k];

                print $prefix.$this_funnel_offset." │  ║\n";

                if(my $fan_choice = (scalar(@$fan_df_targets)!=1) || defined($fan_target->on_condition)) {
                    if(defined(my $on_condition = $fan_target->on_condition)) {
                        print $prefix.$this_funnel_offset." │  ║ WHEN $on_condition\n";
                    } else {
                        print $prefix.$this_funnel_offset." │  ║ ELSE\n";
                    }
                }
                print $prefix.$this_funnel_offset.' │├─╚═> ';

                my $next_fan_or_condition_offset = ($j<scalar(@$fan_dfrs)-1 or $k<scalar(@$fan_df_targets)-1) ? ' │  ║   ' : ' │      ';

                if(my $template = $fan_target->input_id_template) {
                    print "$template\n";
                    print $prefix.$this_funnel_offset.$next_fan_or_condition_offset." │\n";
                    print $prefix.$this_funnel_offset.$next_fan_or_condition_offset." V\n";
                    print $prefix.$this_funnel_offset.$next_fan_or_condition_offset;
                }

                $fan_target->to_analysis->print_diagram_node($ref_pipeline, $prefix.$this_funnel_offset.$next_fan_or_condition_offset, $seen_analyses );
            }
        }

        my $funnel_branch   = $funnel_dfr->branch_code;

        print $prefix.$this_funnel_offset." │\n";
        print $prefix.$this_funnel_offset." │\n";
        print $prefix.$this_funnel_offset." │#$funnel_branch\n";

        foreach my $k (0..scalar(@$df_targets)-1) {   # for each funnel's target
            my $df_target = $df_targets->[$k];

            print $prefix.$this_funnel_offset." │\n";

            my $funnel_choice = (scalar(@$df_targets)!=1) || defined($df_target->on_condition);

            if($funnel_choice) {
                if(defined(my $on_condition = $df_target->on_condition)) {
                    print $prefix.$this_funnel_offset." │ WHEN $on_condition\n";
                } else {
                    print $prefix.$this_funnel_offset." │ ELSE\n";
                }
            }

            my $next_funnel_or_condition_offset = '';

            if( (scalar(@$groups)==1 or $this_funnel_offset) and !$funnel_choice ) {  # 'the only group' (backbone) or a semaphore funnel ...
                print $prefix.$this_funnel_offset." V\n";       # ... make a vertical arrow
                print $prefix.$this_funnel_offset;
            } else {
                print $prefix.$this_funnel_offset.' └─▻ ';      # otherwise fork to the right
                $next_funnel_or_condition_offset = ($i<scalar(@$groups)-1 or $k<scalar(@$df_targets)-1) ? ' │  ' : '    ';
            }
            if(my $template = $df_target->input_id_template) {
                print "$template\n";
                print $prefix.$this_funnel_offset.$next_funnel_or_condition_offset." │\n";
                print $prefix.$this_funnel_offset.$next_funnel_or_condition_offset." V\n";
                print $prefix.$this_funnel_offset.$next_funnel_or_condition_offset;
            }

            my $target = $df_target->to_analysis;
            if($target->can('print_diagram_node')) {
                $target->print_diagram_node($ref_pipeline, $prefix.$this_funnel_offset.$next_funnel_or_condition_offset, $seen_analyses );
            } elsif($target->isa('Bio::EnsEMBL::Hive::NakedTable')) {
                print '[[ '.$target->relative_display_name($ref_pipeline)." ]]\n";
            } elsif($target->isa('Bio::EnsEMBL::Hive::Accumulator')) {
                print '<<-- '.$target->relative_display_name($ref_pipeline)."\n";
            }
        }
    }
}

1;

