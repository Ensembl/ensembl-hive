=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::AnalysisCtrlRule

=head1 DESCRIPTION

    An 'analysis control rule' is a high level blocking control structure where there is
    a 'ctrled_analysis' which is 'BLOCKED' from running until all of its 'condition_analysis' are 'DONE'.
    If a ctrled_analysis requires multiple analysis to be DONE before it can run, a separate
    AnalysisCtrlRule must be created/stored for each condtion analysis.

    Allows the 'condition' analysis to be specified with a network savy URL like
    mysql://ensadmin:<pass>@ecs2:3361/compara_hive_test?analysis.logic_name='blast_NCBI34'

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

=head1 APPENDIX

    The rest of the documentation details each of the object methods.
    Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::AnalysisCtrlRule;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('throw');
use Bio::EnsEMBL::Hive::URLFactory;

use base ( 'Bio::EnsEMBL::Hive::Cacheable', 'Bio::EnsEMBL::Hive::Storable' );


sub unikey {    # override the default from Cacheable parent
    return [ 'condition_analysis_url', 'ctrled_analysis' ];
}   


=head1 AUTOLOADED

    ctrled_analysis_id / ctrled_analysis

=cut


=head2 condition_analysis_url

    Arg[1]  : (optional) string $url
    Usage   : $self->condition_analysis_url($url);
    Function: Get/set method for the analysis which must be 'DONE' in order for
                the controlled analysis to be un-BLOCKED. Specified as a URL.
    Returns : string
  
=cut

sub condition_analysis_url {
    my $self = shift @_;

    if(@_) {
        $self->{'_condition_analysis_url'} = shift @_;
        if( $self->{'_condition_analysis'} ) {
#            warn "setting condition_analysis_url() in an object that had to_analysis() defined";
            $self->{'_condition_analysis'} = undef;
        }
    } elsif( !$self->{'_condition_analysis_url'} and my $condition_analysis=$self->{'_condition_analysis'} ) {

        my $ref_dba = $self->ctrled_analysis && $self->ctrled_analysis->adaptor && $self->ctrled_analysis->adaptor->db;
        $self->{'_condition_analysis_url'} = $condition_analysis->url( $ref_dba );  # the URL may be shorter if DBA is the same for source and target

#        warn "Lazy-loaded condition_analysis_url\n";
    }

    return $self->{'_condition_analysis_url'};
}



=head2 condition_analysis

    Arg[1]  : (optional) Bio::EnsEMBL::Hive::Analysis object
    Usage   : $self->condition_analysis($anal);
    Function: Get/set method for the analysis which must be 'DONE' in order for
                the controlled analysis to be un-BLOCKED
    Returns : Bio::EnsEMBL::Hive::Analysis
  
=cut

sub condition_analysis {
    my ($self,$analysis) = @_;

    if( defined $analysis ) {
        unless ($analysis->isa('Bio::EnsEMBL::Hive::Analysis')) {
            throw( "condition_analysis arg must be a [Bio::EnsEMBL::Hive::Analysis] not a [$analysis]");
        }
        $self->{'_condition_analysis'} = $analysis;
    }

        # lazy load the analysis object if I can
    if( !$self->{'_condition_analysis'} and my $condition_analysis_url = $self->condition_analysis_url ) {

        my $collection = Bio::EnsEMBL::Hive::Analysis->collection();

        if( $collection and $self->{'_condition_analysis'} = $collection->find_one_by('logic_name', $condition_analysis_url) ) {
#            warn "Lazy-loading object from 'Analysis' collection\n";
        } elsif(my $adaptor = $self->adaptor) {
#            warn "Lazy-loading object from AnalysisAdaptor\n";
            $self->{'_condition_analysis'} = $adaptor->db->get_AnalysisAdaptor->fetch_by_logic_name_or_url($condition_analysis_url);
        } else {
#            warn "Lazy-loading object from full URL\n";
            $self->{'_condition_analysis'} = Bio::EnsEMBL::Hive::DBSQL::AnalysisAdaptor->fetch_by_logic_name_or_url($condition_analysis_url);
        }
    }

    return $self->{'_condition_analysis'};
}


=head2 toString

    Args       : (none)
    Example    : print $c_rule->toString()."\n";
    Description: returns a stringified representation of the rule
    Returntype : string

=cut

sub toString {
    my $self = shift;

    return join('',
            'AnalysisCtrlRule: ',
            $self->condition_analysis_url,
            ' ---| ',
            $self->ctrled_analysis->logic_name,
    );
}

1;

