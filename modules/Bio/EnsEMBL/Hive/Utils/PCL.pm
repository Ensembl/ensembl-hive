=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::PCL

=head1 DESCRIPTION

    This module deals with parsing pipeline configuration files written in Perl-based "PipeConfig Language"

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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
our @EXPORT = qw(WHEN ELSE);

our $cond_group_marker   = 'CONDitionGRoup';

sub WHEN {
    return [ $cond_group_marker, @_ ];
}


sub ELSE ($) {
    my ($foo) = @_;

    return (undef, $foo);
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

        my $cond_groups = $flow_into->{$branch_tag};

            # force the old format into the new one, making sure we get separate condition groups:
        if(!ref($cond_groups)) {    # treat a scalar as a single target_url:
            $cond_groups = [ WHEN( ELSE( $cond_groups )) ];
        } elsif(ref($cond_groups) eq 'HASH') {
            my @temp_cond_groups = ();
            while(my ($target, $templates) = each %$cond_groups) {
                $templates = [$templates] unless(ref($templates) eq 'ARRAY');
                push @temp_cond_groups, map { WHEN( ELSE( { $target => $_ } )) } @$templates;
            }
            $cond_groups = \@temp_cond_groups;
        } elsif((ref($cond_groups) eq 'ARRAY') and !ref($cond_groups->[0])) {
            if($cond_groups->[0] eq $cond_group_marker) { # one WHEN has to be put into an array:
                $cond_groups = [ $cond_groups ];
            } else {    # otherwise assume it is an array of target_urls:
                $cond_groups = [ map { WHEN( ELSE( $_ )) } @$cond_groups ];
            }
        }

        foreach my $cond_group (@$cond_groups) {

                # chop the condition group marker off:
            my $this_cond_group_marker = shift @$cond_group;
            die "Expecting $cond_group_marker, got $this_cond_group_marker" unless($this_cond_group_marker eq $cond_group_marker);

            my $df_rule = $pipeline->add_new_or_update( 'DataflowRule',
                'from_analysis'             => $from_analysis,
                'branch_code'               => $branch_name_or_code,
                'funnel_dataflow_rule'      => $funnel_dataflow_rule,
            );

            while(@$cond_group) {
                my $on_condition    = shift @$cond_group;
                my $heirs           = shift @$cond_group;

                    # force anything else to the common denominator format:
                $heirs = [ $heirs ] unless(ref($heirs));
                $heirs = { map { ($_ => undef) } @$heirs } if(ref($heirs) eq 'ARRAY');

                while(my ($heir_url, $input_id_template_list) = each %$heirs) {

                    if($heir_url =~ m{^\w+$/}) {
                        my $heir_analysis = $pipeline->collection_of('Analysis')->find_one_by('logic_name', $heir_url)
                            or die "Could not find a local analysis named '$heir_url' (dataflow from analysis '".($from_analysis->logic_name)."')\n";
                    }

                    $input_id_template_list = [ $input_id_template_list ] unless(ref($input_id_template_list) eq 'ARRAY');  # allow for more than one template per analysis

                    foreach my $input_id_template (@$input_id_template_list) {

                        my $df_target = $pipeline->add_new_or_update( 'DataflowTarget',
                            'source_dataflow_rule'      => $df_rule,
                            'on_condition'              => $on_condition,
                            'input_id_template'         => $input_id_template,
                            'to_analysis_url'           => $heir_url,
                        );

                        if($group_role eq 'funnel') {
                            if($group_tag_to_funnel_dataflow_rule{$group_tag}) {
                                die "More than one funnel dataflow_rule defined for group '$group_tag'\n";
                            } else {
                                $group_tag_to_funnel_dataflow_rule{$group_tag} = $df_rule;
                            }
                        }
                    } # /for all templates
                } # /for all heirs
            } # /for each condition and heir
        } # /foreach $cond_group

    } # /for all branch_tags
}

1;
