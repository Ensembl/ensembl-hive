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

 Bio::EnsEMBL::Nextflow::SpeciesFactory;

=head1 DESCRIPTION

 Given a division or a list of species, dataflow jobs with species names.
 Optionally send output down different dataflow if a species has chromosomes or variants.

 Dataflow of jobs can be made intentions aware by using ensembl production
 database to decide if a species has had an update to its DNA or not. An update
 means any change to the assembly or repeat masking.

=cut

package Bio::EnsEMBL::Nextflow::SpeciesFactory;

use strict;
use warnings;
use Data::Dumper;

use Bio::EnsEMBL::Registry;
use base qw/Bio::EnsEMBL::Nextflow::DbFactory/;
use Exporter qw/import/;
our @EXPORT_OK = qw(has_variation);

sub param_defaults {
  my ($self) = @_;

  return {
    %{$self->SUPER::param_defaults},
    all_species_flow   => 1,
    core_flow          => 2,
    chromosome_flow    => 3,
    variation_flow     => 4,
    compara_flow       => 5,
    regulation_flow    => 6,
    otherfeatures_flow => 7,
  };
}

sub write_output {
  my ($self) = @_;
  my $all_species      = $self->param_required('all_species');
  my $all_species_flow = $self->param('all_species_flow');
  my $core_flow        = $self->param('core_flow');
  my $group            = $self->param('group');

  foreach my $species ( @{$all_species} ) {
    open(my $core_fh, '>>', "dataflow_$core_flow.json");
    print $core_fh "{\"species\":\"$species\", \"group\":\"$group\"}\n";
    close($core_fh);
  }

  if ($group eq 'core') {
    my ($flow, $flow_species) = $self->flow_species($all_species);
    foreach my $group ( keys %$flow ) {
      foreach my $species ( @{ $$flow_species{$group} } ) {
        open(my $group_fh, '>>', "dataflow_".$$flow{$group}.".json");
        print $group_fh "{\"species\":\"$species\", \"group\":\"$group\"}\n";
        close($group_fh);
      }
    }
  }

  open(my $all_fh, '>', "dataflow_$all_species_flow.json");
  print $all_fh "{\"all_species\":\"".join(",", @{$all_species})."\", \"species_count\":".scalar(@{$all_species})."}\n";
  close($all_fh);
}

sub flow_species {
  my ($self, $all_species) = @_;
  my $chromosome_flow    = $self->param('chromosome_flow');
  my $variation_flow     = $self->param('variation_flow');
  my $regulation_flow    = $self->param('regulation_flow');
  my $otherfeatures_flow = $self->param('otherfeatures_flow');
  my $compara_flow       = $self->param('compara_flow');

  my @chromosome_species;
  my @variation_species;
  my @regulation_species;
  my @otherfeatures_species;
  my @compara_species;

  if ($chromosome_flow || $variation_flow || $regulation_flow || $otherfeatures_flow) {
    foreach my $species ( @{$all_species} ) {
      if ($chromosome_flow) {
        if ( $self->has_chromosome($species) ) {
          push @chromosome_species, $species;
        }
      }

      if ($variation_flow) {
        if ( $self->has_variation($species) ) {
          push @variation_species, $species;
        }
      }
      if ($regulation_flow) {
        if ($self->has_regulation($species)) {
          push @regulation_species, $species;
        }
      }
      if ($otherfeatures_flow){
        if ($self->has_otherfeatures($species)) {
          push @otherfeatures_species, $species;
        }
      }
    }
  }

  if ($compara_flow) {
    my $compara_dbs = $self->param('compara_dbs');
    foreach my $division ( keys %$compara_dbs ) {
      push @compara_species, $division;
    };
  }

  my $flow = {
    'core'          => $chromosome_flow,
    'variation'     => $variation_flow,
    'regulation'    => $regulation_flow,
    'otherfeatures' => $otherfeatures_flow,
    'compara'       => $compara_flow,
  };

  my $flow_species = {
    'core'          => \@chromosome_species,
    'variation'     => \@variation_species,
    'regulation'    => \@regulation_species,
    'otherfeatures' => \@otherfeatures_species,
    'compara'       => \@compara_species,
  };

  return ($flow, $flow_species);
}

sub has_chromosome {
  my ( $self, $species ) = @_;
  my $gc =
    Bio::EnsEMBL::Registry->get_adaptor($species, 'core', 'GenomeContainer');

  my $has_chromosome = $gc->has_karyotype();

  $gc && $gc->dbc->disconnect_if_idle();

  return $has_chromosome;
}

sub has_variation {
  my ( $self, $species ) = @_;
  my $dbva =
    Bio::EnsEMBL::Registry->get_DBAdaptor( $species, 'variation' );
  my $has_variation;
  if (defined $dbva){
    my $source_database = $dbva->get_MetaContainer->single_value_by_key('variation_source.database');
    if(defined($source_database)){
      $has_variation = $source_database == 1 ? 1 : 0;
    }
    else{
      $has_variation = 1;
    }
  }
  else{
    $has_variation = 0;
  }

  $has_variation && $dbva->dbc->disconnect_if_idle();

  return $has_variation;
}

sub has_regulation {
  my ($self, $species) = @_;
  my $dbreg = Bio::EnsEMBL::Registry->get_DBAdaptor($species, 'funcgen');

  my $has_regulation = defined $dbreg ? 1 : 0;

  $has_regulation && $dbreg->dbc->disconnect_if_idle();

  return $has_regulation;
}

sub has_otherfeatures {
  my ($self, $species) = @_;
  my $dbof = Bio::EnsEMBL::Registry->get_DBAdaptor($species, 'otherfeatures');

  my $has_otherfeatures = defined $dbof ? 1 : 0;

  $has_otherfeatures && $dbof->dbc->disconnect_if_idle();

  return $has_otherfeatures;
}

1;

