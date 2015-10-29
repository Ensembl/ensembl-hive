=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DataflowTarget

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


package Bio::EnsEMBL::Hive::DataflowTarget;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('stringify', 'throw');
use Bio::EnsEMBL::Hive::TheApiary;

use base ( 'Bio::EnsEMBL::Hive::Cacheable', 'Bio::EnsEMBL::Hive::Storable' );


sub unikey {    # override the default from Cacheable parent
    return [ 'source_dataflow_rule', 'on_condition', 'input_id_template', 'to_analysis_url' ];
} 


=head1 AUTOLOADED

    source_dataflow_rule_id / source_dataflow_rule

=cut


=head2 on_condition

    Function: getter/setter method for the on_condition of the dataflow target

=cut

sub on_condition {
    my $self = shift @_;

    if(@_) {
        $self->{'_on_condition'} = shift @_;
    }
    return $self->{'_on_condition'};
}


=head2 input_id_template

    Function: getter/setter method for the input_id_template of the dataflow target

=cut

sub input_id_template {
    my $self = shift @_;

    if(@_) {
        my $input_id_template = shift @_;
        $self->{'_input_id_template'} = (ref($input_id_template) ? stringify($input_id_template) : $input_id_template),
    }
    return $self->{'_input_id_template'};
}


=head2 to_analysis_url

    Arg[1]  : (optional) string $url
    Usage   : $self->to_analysis_url($url);
    Function: Get/set method for the 'to' analysis objects URL for this rule
    Returns : string
  
=cut

sub to_analysis_url {
    my $self = shift @_;

    if(@_) {
        $self->{'_to_analysis_url'} = shift @_;
        if( $self->{'_to_analysis'} ) {
            $self->{'_to_analysis'} = undef;
        }
    } elsif( !$self->{'_to_analysis_url'} and my $target_object=$self->{'_to_analysis'} ) {

        my $ref_dba = $self->from_analysis && $self->from_analysis->adaptor && $self->from_analysis->adaptor->db;
        $self->{'_to_analysis_url'} = $target_object->url( $ref_dba );      # the URL may be shorter if DBA is the same for source and target
    }

    return $self->{'_to_analysis_url'};
}


=head2 to_analysis

    Usage   : $self->to_analysis($analysis);
    Function: Get/set method for the goal analysis object of this rule.
    Returns : Bio::EnsEMBL::Hive::Analysis
    Args    : Bio::EnsEMBL::Hive::Analysis
  
=cut

sub to_analysis {
    my ($self, $target_object) = @_;

    if( defined $target_object ) {
        unless ($target_object->can('url')) {
            throw( "to_analysis arg must support 'url' method, '$target_object' does not know how to do it");
        }
        $self->{'_to_analysis'} = $target_object;
    }

    if( !$self->{'_to_analysis'} and my $to_analysis_url = $self->to_analysis_url ) {   # lazy-load through TheApiary

        $self->{'_to_analysis'} = Bio::EnsEMBL::Hive::TheApiary->find_by_url( $to_analysis_url, $self->hive_pipeline );
    }

    return $self->{'_to_analysis'};
}


=head2 toString

    Args       : (none)
    Example    : print $df_rule->toString()."\n";
    Description: returns a stringified representation of the rule
    Returntype : string

=cut

sub toString {
    my $self    = shift @_;
    my $short   = shift @_;

    my $on_condition = $self->on_condition;

    return join('',
            $short ? () : ( 'DataflowTarget: ' ),
            defined($on_condition) ? 'WHEN '.$on_condition : 'DEFAULT ',
            '--> ',
            $self->to_analysis_url,
            ($self->input_id_template ? (' WITH TEMPLATE: '.$self->input_id_template) : ''),
    );
}

1;

