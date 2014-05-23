=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DataflowRule

=head1 DESCRIPTION

    A data container object (methods are intelligent getters/setters) that corresponds to a row stored in 'dataflow_rule' table:

    CREATE TABLE dataflow_rule (
        dataflow_rule_id    int(10) unsigned NOT NULL AUTO_INCREMENT,
        from_analysis_id    int(10) unsigned NOT NULL,
        branch_code         int(10) default 1 NOT NULL,
        funnel_dataflow_rule_id  int(10) unsigned default NULL,
        to_analysis_url     varchar(255) default '' NOT NULL,
        input_id_template   TEXT DEFAULT NULL,

        PRIMARY KEY (dataflow_rule_id),
        UNIQUE (from_analysis_id, to_analysis_url)
    );

    A dataflow rule is activated when a Bio::EnsEMBL::Hive::AnalysisJob::dataflow_output_id is called at any moment during a RunnableDB's execution.
    The current RunnableDB's analysis ($from_analysis) and the requested $branch_code (1 by default) define the entry conditions,
    and whatever rules match these conditions will generate new jobs with input_ids specified in the dataflow_output_id() call.
    If input_id_template happens to contain a non-NULL value, it will be used to generate the corresponding intput_id instead.

    Jessica's remark on the structure of to_analysis_url:
        Extended from design of SimpleRule concept to allow the 'to' analysis to be specified with a network savy URL like
        mysql://ensadmin:<pass>@ecs2:3361/compara_hive_test/analysis?logic_name='blast_NCBI34'

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

=cut


package Bio::EnsEMBL::Hive::DataflowRule;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('stringify', 'throw');
use Bio::EnsEMBL::Hive::DBSQL::AnalysisAdaptor;

use base ( 'Bio::EnsEMBL::Hive::Cacheable', 'Bio::EnsEMBL::Hive::Storable' );


sub unikey {    # override the default from Cacheable parent
    return [ 'from_analysis', 'to_analysis_url', 'branch_code', 'funnel_dataflow_rule', 'input_id_template' ];
} 


=head1 AUTOLOADED

    from_analysis_id / from_analysis

    funnel_dataflow_rule_id / funnel_dataflow_rule

=cut


=head2 branch_code

    Function: getter/setter method for the branch_code of the dataflow rule

=cut

sub branch_code {
    my $self = shift @_;

    if(@_) {
        my $branch_name_or_code = shift @_;
        $self->{'_branch_code'} = $branch_name_or_code && Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor::branch_name_2_code( $branch_name_or_code );
    }
    return $self->{'_branch_code'};
}


=head2 input_id_template

    Function: getter/setter method for the input_id_template of the dataflow rule

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
#            warn "setting to_analysis_url() in an object that had to_analysis() defined";
            $self->{'_to_analysis'} = undef;
        }
    } elsif( !$self->{'_to_analysis_url'} and my $analysis_or_nt=$self->{'_to_analysis'} ) {

        # if the 'from' and 'to' share the same adaptor, then use a simple logic_name
        # for the URL rather than a full network distributed URL

            # FIXME: the following block could be incapsulated in Analysis->url() and NakedTable->url()
        my $ref_analysis_adaptor = $self->from_analysis && $self->from_analysis->adaptor;
        if($analysis_or_nt->can('logic_name') and $ref_analysis_adaptor and ($ref_analysis_adaptor == $analysis_or_nt->adaptor)) {
            $self->{'_to_analysis_url'} = $analysis_or_nt->logic_name;
        } else {
            $self->{'_to_analysis_url'} = $analysis_or_nt->url($ref_analysis_adaptor->db);
        }
#        warn "Lazy-loaded to_analysis_url\n";
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
    my ($self, $analysis_or_nt) = @_;

    if( defined $analysis_or_nt ) {
        unless ($analysis_or_nt->can('url')) {
            throw( "to_analysis arg must support 'url' method, '$analysis_or_nt' does not know how to do it");
        }
        $self->{'_to_analysis'} = $analysis_or_nt;
    }

        # lazy load the analysis object if I can
    if( !$self->{'_to_analysis'} and my $to_analysis_url = $self->to_analysis_url ) {
        my $collection = Bio::EnsEMBL::Hive::Analysis->collection();

        if( $collection and $self->{'_to_analysis'} = $collection->find_one_by('logic_name', $to_analysis_url) ) {
#            warn "Lazy-loading object from 'Analysis' collection\n";
        } elsif(my $adaptor = $self->adaptor) {
#            warn "Lazy-loading object from AnalysisAdaptor\n";
            $self->{'_to_analysis'} = $adaptor->db->get_AnalysisAdaptor->fetch_by_logic_name_or_url($to_analysis_url);
        } else {
#            warn "Lazy-loading object from full URL\n";
            $self->{'_to_analysis'} = Bio::EnsEMBL::Hive::DBSQL::AnalysisAdaptor->fetch_by_logic_name_or_url($to_analysis_url);
        }
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

    return join('',
            $short ? () : (
                'DataflowRule[',
                ($self->dbID // ''),
                ']: ',
                $self->from_analysis->logic_name,
            ),
            ' --#',
            $self->branch_code,
            '--> ',
            $self->to_analysis_url,
            ($self->input_id_template ? (' WITH TEMPLATE: '.$self->input_id_template) : ''),
            ($self->funnel_dataflow_rule ? ' ---|| ('.$self->funnel_dataflow_rule->toString(1).' )'  : ''),
    );
}

1;

