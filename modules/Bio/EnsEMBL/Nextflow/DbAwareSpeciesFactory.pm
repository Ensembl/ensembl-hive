
=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2022] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 NAME

 Bio::EnsEMBL::Nextflow::DbAwareSpeciesFactory;

=head1 DESCRIPTION

 Given a list of species, dataflow jobs with species names.
 Optionally send output down different dataflow if a species has chromosomes or variants.

=cut

package Bio::EnsEMBL::Nextflow::DbAwareSpeciesFactory;

use strict;
use warnings;

use Bio::EnsEMBL::Registry;
use base qw/Bio::EnsEMBL::Nextflow::SpeciesFactory/;

sub param_defaults {
  my ($self) = @_;

  return {
    %{$self->SUPER::param_defaults},
    compara_flow => 0,
  };
}

sub run {
  my ($self) = @_;
  my $species_list = $self->param_required('species_list');

  $self->param( 'all_species', $species_list );
}

1;

