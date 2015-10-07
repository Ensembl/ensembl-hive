=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

=pod

=head1 NAME

Bio::EnsEMBL::Hive::Cacheable - base class to cache collections

=cut

package Bio::EnsEMBL::Hive::Cacheable;

use strict;
use warnings;

use Scalar::Util qw(weaken);


sub hive_pipeline {
    my $self = shift @_;
    if (@_) {
        $self->{'_hive_pipeline'} = shift @_;
        weaken($self->{'_hive_pipeline'});
    }
    return $self->{'_hive_pipeline'};
}


sub is_local_to {
    my $self            = shift @_;
    my $rel_pipeline    = shift @_;

    return $self->hive_pipeline == $rel_pipeline;
}


sub relative_display_name {
    my ($self, $ref_pipeline) = @_;  # if 'reference' hive_pipeline is the same as 'my' hive_pipeline, a shorter display_name is generated

    my $my_pipeline = $self->hive_pipeline;
    my $my_dba      = $my_pipeline && $my_pipeline->hive_dba;
    return ( ($my_dba and !$self->is_local_to($ref_pipeline) ) ? $my_dba->dbc->dbname . '/' : '' ) . $self->display_name;
}

sub display_name {
    my ($self) = @_;
    return "$self";     # Default implementation
}


sub unikey {    # to be redefined by individual Cacheable classes
    return undef;
}


1;
