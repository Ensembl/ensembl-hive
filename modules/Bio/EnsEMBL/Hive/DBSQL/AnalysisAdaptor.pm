=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::AnalysisAdaptor

=head1 SYNOPSIS

    $analysis_adaptor = $db_adaptor->get_AnalysisAdaptor;

    $analysis_adaptor = $analysis_object->adaptor;

=head1 DESCRIPTION

    Module to encapsulate all db access for persistent class Analysis.
    There should be just one such adaptor per application and database connection.

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


package Bio::EnsEMBL::Hive::DBSQL::AnalysisAdaptor;

use strict;
use warnings;
use Bio::EnsEMBL::Hive::Analysis;
use Bio::EnsEMBL::Hive::URLFactory;

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


sub default_table_name {
    return 'analysis_base';
}


sub default_insertion_method {
    return 'INSERT';
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::Analysis';
}


sub fetch_all_failed_analyses {
    my $self = shift;

    return $self->fetch_all( "JOIN analysis_stats s USING(analysis_id) WHERE s.status='FAILED'" );
}


=head2 fetch_by_logic_name_or_url

    Description: given a URL gets the analysis from URLFactory, otherwise fetches it from the db

=cut

sub fetch_by_logic_name_or_url {
    my $self                = shift @_; # can either be $self or class name
    my $logic_name_or_url   = shift @_;

    if($logic_name_or_url =~ m{^\w*://}) {
        return Bio::EnsEMBL::Hive::URLFactory->fetch($logic_name_or_url, ref($self) && $self->db);
    } else {
        return $self->fetch_by_logic_name($logic_name_or_url);
    }
}


=head2 fetch_by_url_query

    Description: fetches the analysis either by logic_name or by dbID (either coming from the tail of the URL)

=cut

sub fetch_by_url_query {
    my ($self, $field_name, $field_value) = @_;

    if(!$field_name or !$field_value) {

        return;

    } elsif($field_name eq 'logic_name') {

        return $self->fetch_by_logic_name($field_value);

    } elsif($field_name eq 'dbID') {

        return $self->fetch_by_dbID($field_value);

    }
}


1;
