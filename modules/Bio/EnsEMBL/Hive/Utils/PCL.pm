=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::PCL

=head1 DESCRIPTION

    This module deals with parsing pipeline configuration files written in Perl-based "PipeConfig Language"

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


package Bio::EnsEMBL::Hive::Utils::PCL;

use strict;
use warnings;

use Exporter 'import';
our @EXPORT = qw(WHEN ELSE INPUT_PLUS);

use Bio::EnsEMBL::Hive::Utils ('stringify');


our $cond_group_marker   = 'CONDitionGRoup';

sub WHEN {
    return [ $cond_group_marker, @_ ];
}


sub ELSE ($) {
    my ($foo) = @_;

    return (undef, $foo);
}


sub INPUT_PLUS {
    my $template = shift @_ // '';

    return '+'.(ref($template) ? stringify($template) : $template);
}


sub parse_wait_for {
    my ($pipeline, $ctrled_analysis, $wait_for) = @_;

    $wait_for ||= [];
    $wait_for   = [ $wait_for ] unless(ref($wait_for) eq 'ARRAY'); # force scalar into an arrayref

        # create control rules:
    foreach my $condition_url (@$wait_for) {
        if($condition_url =~ m{^\w+$}) {
            my $condition_analysis = $pipeline->collection_of('Analysis')->find_one_by('logic_name', $condition_url)
                or die "Could not find a local analysis '$condition_url' to create a control rule (in '".($ctrled_analysis->logic_name)."')\n";
        }
        my ($c_rule) = $pipeline->add_new_or_update( 'AnalysisCtrlRule',   # NB: add_new_or_update returns a list
                'condition_analysis_url'    => $condition_url,
                'ctrled_analysis'           => $ctrled_analysis,
        );
    }
}


sub parse_flow_into {
    my ($pipeline, $from_analysis, $flow_into) = @_;

    $flow_into   = { 1 => $flow_into } unless(ref($flow_into) eq 'HASH'); # force non-hash into a hash

    my %group_tag_to_funnel_dataflow_rule = ();

    my $semaphore_sign = '->';

    my @all_branch_tags = keys %$flow_into;
    foreach my $branch_tag ((grep {/^[A-Z]$semaphore_sign/} @all_branch_tags), (grep {/$semaphore_sign[A-Z]$/} @all_branch_tags), (grep {!/$semaphore_sign/} @all_branch_tags)) {

        my ($branch_name_or_code, $group_role, $group_tag);

        if($branch_tag=~/^([A-Z])$semaphore_sign(-?\w+)$/) {
            ($branch_name_or_code, $group_role, $group_tag) = ($2, 'funnel', $1);
        } elsif($branch_tag=~/^(-?\w+)$semaphore_sign([A-Z])$/) {
            ($branch_name_or_code, $group_role, $group_tag) = ($1, 'fan', $2);
        } elsif($branch_tag=~/^(-?\w+)$/) {
            ($branch_name_or_code, $group_role, $group_tag) = ($1, '');
        } elsif($branch_tag=~/:/) {
            die "Please use newer '2${semaphore_sign}A' and 'A${semaphore_sign}1' notation instead of '2:1' and '1'\n";
        } else {
            die "Error parsing the group tag '$branch_tag'\n";
        }

        my $funnel_dataflow_rule = undef;    # NULL by default

        if($group_role eq 'fan') {
            unless($funnel_dataflow_rule = $group_tag_to_funnel_dataflow_rule{$group_tag}) {
                die "No funnel dataflow_rule defined for group '$group_tag'\n";
            }
        }

        my $pre_cond_groups = $flow_into->{$branch_tag};

            # [first pass] force pre_cond_groups into a list:
        if( !ref($pre_cond_groups)                  # a scalar (a single target)
         or (ref($pre_cond_groups) eq 'HASH')       # a hash (a combination of targets with templates)
         or ((ref($pre_cond_groups) eq 'ARRAY') and @$pre_cond_groups and !ref($pre_cond_groups->[0]) and ($pre_cond_groups->[0] eq $cond_group_marker)) # a single WHEN group
        ) {
            $pre_cond_groups = [ $pre_cond_groups ];
        }

        my @uniform_cond_groups = ();

            # [second pass] rework them into a true list of WHEN-groups:
        foreach my $pre_group (@$pre_cond_groups) {
            if( !ref($pre_group) ) {                                            # wrap the scalar:
                push @uniform_cond_groups, WHEN( ELSE( $pre_group ));
            } elsif( ref($pre_group) eq 'HASH') {                               # break up the hash and wrap the parts:
                while(my ($target, $templates) = each %$pre_group) {
                    $templates = [$templates] unless(ref($templates) eq 'ARRAY');
                    push @uniform_cond_groups, map { WHEN( ELSE( { $target => $_ } )) } @$templates;
                }
            } else {                                                            # keep the WHEN groups unchanged
                push @uniform_cond_groups, $pre_group;
            }
        }

        foreach my $cond_group (@uniform_cond_groups) {

            unless(ref($cond_group) eq 'ARRAY') {
                use Data::Dumper;
                die "Expecting ARRAYref, but got ".Dumper($cond_group)." instead.";
            }
                # chop the condition group marker off:
            my $this_cond_group_marker = shift @$cond_group;
            die "Expecting $cond_group_marker, got $this_cond_group_marker" unless($this_cond_group_marker eq $cond_group_marker);

            while(@$cond_group) {
                my $on_condition    = shift @$cond_group;
                my $heirs           = shift @$cond_group;

                    # force anything else to the common denominator format:
                $heirs = [ $heirs ] unless(ref($heirs));
                $heirs = { map { ($_ => undef) } @$heirs } if(ref($heirs) eq 'ARRAY');

                while(my ($heir_url, $input_id_template_list) = each %$heirs) {

                    if($heir_url =~ m{^\w+$}) {
                        my $heir_analysis = $pipeline->collection_of('Analysis')->find_one_by('logic_name', $heir_url)
                            or die "Could not find a local analysis named '$heir_url' (dataflow from analysis '".($from_analysis->logic_name)."')\n";
                    }

                    $input_id_template_list = [ $input_id_template_list ] unless(ref($input_id_template_list) eq 'ARRAY');  # allow for more than one template per analysis

                    foreach my $input_id_template (@$input_id_template_list) {

                        my $template_string = (ref($input_id_template) ? stringify($input_id_template) : $input_id_template);
                        my $extend_param_stack = ($template_string && $template_string=~s/^\+(.*)$/$1/) ? 1 : 0;

                        my ($df_target) = $pipeline->add_new_or_update( 'DataflowTarget',   # NB: add_new_or_update returns a list
                            'source_dataflow_rule'      => undef,           # NB: had to create the "suspended targets" to break the dependence circle
                            'on_condition'              => $on_condition,
                            'input_id_template'         => $template_string,
                            'extend_param_stack'        => $extend_param_stack,
                            'to_analysis_url'           => $heir_url,
                        );

                    } # /for all templates
                } # /for all heirs
            } # /for each condition and heir

            my $suspended_targets = $pipeline->collection_of('DataflowTarget')->find_all_by( 'source_dataflow_rule', undef );

            my ($df_rule, $df_rule_is_new) = $pipeline->add_new_or_update( 'DataflowRule',   # NB: add_new_or_update returns a list
                'from_analysis'             => $from_analysis,
                'branch_code'               => $branch_name_or_code,
                'funnel_dataflow_rule'      => $funnel_dataflow_rule,
                'unitargets'                => Bio::EnsEMBL::Hive::DataflowRule->unitargets($suspended_targets),
#                'unitargets'                => $suspended_targets,
            );

            if( $df_rule_is_new ) {
                foreach my $suspended_target (@$suspended_targets) {
                    $suspended_target->source_dataflow_rule( $df_rule );
                }
            } else {
                foreach my $suspended_target (@$suspended_targets) {
                    $pipeline->collection_of('DataflowTarget')->forget( $suspended_target );
                }
            }

            if($group_role eq 'funnel') {
                if($group_tag_to_funnel_dataflow_rule{$group_tag}) {
                    die "More than one funnel dataflow_rule defined for group '$group_tag'\n";
                } else {
                    $group_tag_to_funnel_dataflow_rule{$group_tag} = $df_rule;
                }
            }
        } # /foreach $cond_group

    } # /for all branch_tags
}

1;
