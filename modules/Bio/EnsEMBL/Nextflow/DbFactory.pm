
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

 Bio::EnsEMBL::Nextflow::DbFactory;

=head1 DESCRIPTION

 Given a division or a list of species, dataflow jobs with database names.

=cut

package Bio::EnsEMBL::Nextflow::DbFactory;

use strict;
use warnings;

use Bio::EnsEMBL::Registry;
use base qw/Bio::EnsEMBL::Nextflow::Base/;

sub param_defaults {
  my ($self) = @_;

  return {
    species      => [],
    taxons       => [],
    division     => [],
    run_all      => 0,
    antispecies  => [],
    antitaxons   => [],
    dbname       => [],
    all_dbs_flow => 1,
    db_flow      => 2,
    compara_flow => 5, # compara_flow moved here from SpeciesFactory; retain former flow #5 here, to avoid bugs
    div_synonyms => {
                      'eb'  => 'bacteria',
                      'ef'  => 'fungi',
                      'em'  => 'metazoa',
                      'epl' => 'plants',
                      'epr' => 'protists',
                      'e'   => 'vertebrates',
                      'ev'  => 'vertebrates',
                      'ensembl' => 'vertebrates',
                    },
    meta_filters => {},
    group        => 'core',
    registry_file => undef,
  };
}

sub fetch_input {
  my ($self) = @_;

  # Switched parameter name from 'db_type' to 'group', but for backwards-
  # compatability allow db_type to still be specified.
  if ($self->param_is_defined('db_type')) {
    $self->param('group', $self->param('db_type'));
  }
}

sub run {
  my ($self) = @_;
  my $reg = 'Bio::EnsEMBL::Registry';
  if ($self->param_is_defined('registry_file')) {
    $reg->load_all($self->param('registry_file'));
  }

  my $species = $self->param('species') || [];

  my @species = ( ref($species) eq 'ARRAY' ) ? @$species : ($species);

  my $taxons = $self->param('taxons') || [];
  my @taxons = ( ref($taxons) eq 'ARRAY' ) ? @$taxons : ($taxons);

  my $division = $self->param('division') || [];
  my @division = ( ref($division) eq 'ARRAY' ) ? @$division : ($division);

  my $run_all = $self->param('run_all');

  my $antitaxons = $self->param('antitaxons') || [];
  my @antitaxons = ( ref($antitaxons) eq 'ARRAY' ) ? @$antitaxons : ($antitaxons);

  my $antispecies = $self->param('antispecies') || [];
  my @antispecies = ( ref($antispecies) eq 'ARRAY' ) ? @$antispecies : ($antispecies);

  my $dbnames = $self->param('dbname') || [];
  my @dbnames = ( ref($dbnames) eq 'ARRAY' ) ? @$dbnames : ($dbnames);

  my %meta_filters = %{ $self->param('meta_filters') };

  my $group = $self->param('group');

  my %dbs;
  my %compara_dbs;
  my @all_species;

  # If dbnames are provided, they trump every other parameter,
  # only those are loaded; it's complicated to be be able to use
  # them in conjunction with species/division parameters, and it's
  # not clear if that's a use case worth supporting.
  if (scalar(@dbnames)) {
    foreach my $dbname (@dbnames) {
      my $dbas = $reg->get_all_DBAdaptors_by_dbname($dbname);
      if (scalar(@$dbas)) {
        foreach my $dba (@$dbas) {
          $self->add_species($dba, \%dbs);
        }
      } else {
        $self->warning("Database $dbname not found in registry.");
      }
    }
  } else {
    my $taxonomy_dba;
    if (scalar(@taxons) || scalar(@antitaxons)) {
      $taxonomy_dba = $reg->get_DBAdaptor( 'multi', 'taxonomy' );
    }

    my $all_dbas = $reg->get_all_DBAdaptors( -GROUP => $group );

    my $all_compara_dbas;
    if ($self->param('compara_flow')) {
      $all_compara_dbas = $reg->get_all_DBAdaptors( -GROUP => 'compara' );
    }

    if ( ! scalar(@$all_dbas) && ! scalar(@$all_compara_dbas) ) {
      $self->throw("No $group or compara databases found in the registry");
    }

    if ($run_all) {
      foreach my $dba (@$all_dbas) {
        unless ($dba->species =~ /Ancestral sequences/) {
          # print Dumper $dba;
          $self->add_species($dba, \%dbs);
        }
      }
      $self->warning("All species in " . scalar(keys %dbs) . " databases loaded");

      %compara_dbs = map { $_->species => $_ } @$all_compara_dbas;
    }
    elsif ( scalar(@species) ) {
      foreach my $species (@species) {
        $self->process_species( $all_dbas, $species, \%dbs );
      }
    }
    elsif ( scalar(@taxons) ) {
      foreach my $taxon (@taxons) {
        $self->process_taxon( $all_dbas , $taxonomy_dba, $taxon, "add", \%dbs );
      }
    }
    elsif ( scalar(@division) ) {
      foreach my $division (@division) {
        if ($group ne 'compara') {
          $self->process_division( $all_dbas, $division, \%dbs );
        }
        $self->process_division_compara( $all_compara_dbas, $division, \%compara_dbs );
      }
    }

    if ( scalar(@antitaxons) ) {
      foreach my $antitaxon (@antitaxons) {
        $self->process_taxon( $all_dbas, $taxonomy_dba, $antitaxon, "remove", \%dbs );
        $self->warning("$antitaxon taxon removed");
      }
    }
    if ( scalar(@antispecies) ) {
      foreach my $antispecies (@antispecies) {
        foreach my $dbname ( keys %dbs ) {
          if (exists $dbs{$dbname}{$antispecies}) {
            $self->remove_species($dbname, $antispecies, \%dbs);
            $self->warning("$antispecies removed");
          }
        }
      }
    }

    if ( scalar( keys %meta_filters ) ) {
      foreach my $meta_key ( keys %meta_filters ) {
        $self->filter_species( $meta_key, $meta_filters{$meta_key}, \%dbs );
      }
    }
  }

  foreach my $db_name (keys %dbs) {
    push @all_species, keys %{ $dbs{$db_name} };
  }

  $self->param( 'dbs', \%dbs );
  $self->param( 'compara_dbs', \%compara_dbs );
  $self->param( 'all_species', \@all_species );
}

sub write_output {
  my ($self) = @_;
  my $group        = $self->param('group');
  my $dbs          = $self->param_required('dbs');
  my $db_flow      = $self->param_required('db_flow');
  my $all_dbs_flow = $self->param_required('all_dbs_flow');
  my $compara_dbs  = $self->param_required('compara_dbs');
  my $compara_flow = $self->param_required('compara_flow');

  my @dbnames = keys %$dbs;
  foreach my $dbname ( @dbnames ) {
    my @species_list = keys %{ $$dbs{$dbname} };

    my $dataflow_params = {
      dbname       => $dbname,
      species_list => \@species_list,
      species      => $species_list[0],
      group        => $$dbs{$dbname}{$species_list[0]}->group,
    };

    $self->dataflow_output_id( $dataflow_params, $db_flow );
  }

  if ($group eq 'core' || $group eq 'compara') {
    foreach my $division ( keys %$compara_dbs ) {
      my $dbname = $$compara_dbs{$division}->dbc->dbname;
      push @dbnames, $dbname;

      my $dataflow_params = {
        dbname  => $dbname,
        species => $division,
        group   => 'compara',
      };

      $self->dataflow_output_id( $dataflow_params, $compara_flow );
    }
  }

  $self->dataflow_output_id( {all_dbs => \@dbnames}, $all_dbs_flow );
}

sub add_species {
  my ( $self, $dba, $dbs ) = @_;

  $$dbs{$dba->dbc->dbname}{$dba->species} = $dba;

  $dba->dbc->disconnect_if_idle();
}

sub remove_species {
  my ( $self, $dbname, $species, $dbs ) = @_;

  delete $$dbs{$dbname}{$species};

  if ( scalar( keys %{ $$dbs{$dbname} } ) == 0 ) {
    delete $$dbs{$dbname};
  }
}

sub process_species {
  my ( $self, $all_dbas, $species, $dbs ) = @_;
  my $loaded = 0;

  foreach my $dba ( @$all_dbas ) {
    if ( $species eq $dba->species() ) {
      $self->add_species($dba, $dbs);
      $self->warning("$species loaded");
      $loaded = 1;
      last;
    }
  }

  if ( ! $loaded ) {
    $self->warning("Database not found for $species; check registry parameters.");
  }
}

sub process_taxon {
  my ( $self, $all_dbas, $taxonomy_dba, $taxon, $action, $dbs ) = @_;
  my $species_count = 0;

  my $node_adaptor = $taxonomy_dba->get_TaxonomyNodeAdaptor();
  my $node = $node_adaptor->fetch_by_name_and_class($taxon,"scientific name");;
  $self->throw("$taxon not found in the taxonomy database") if (!defined $node);
  my $taxon_name = $node->names()->{'scientific name'}->[0];

  foreach my $dba (@$all_dbas) {
    #Next if DB is Compara ancestral sequences
    next if $dba->species() =~ /ancestral/i;
    my $dba_ancestors = $self->get_taxon_ancestors_name($dba,$node_adaptor);
    if (grep(/$taxon_name/, @$dba_ancestors)){
      if ($action eq "add"){
        $self->add_species($dba, $dbs);
        $species_count++;
      }
      elsif ($action eq "remove")
      {
        $self->remove_species($dba->dbc->dbname, $dba->species, $dbs);
        $self->warning($dba->species() . " removed");
        $species_count++;
      }
    }
    $dba->dbc->disconnect_if_idle();
  }

  if ($species_count == 0) {
    $self->warning("$taxon was processed but no species was added/removed")
  }
  else {
    if ($action eq "add") {
      $self->warning("$species_count species loaded for taxon $taxon_name");
    }
    if ($action eq "remove") {
      $self->warning("$species_count species removed for taxon $taxon_name");
    }
  }
}

# Return all the taxon ancestors names for a given dba
sub get_taxon_ancestors_name {
  my ($self, $dba, $node_adaptor) = @_;
  my $dba_node = $node_adaptor->fetch_by_coredbadaptor($dba);
  my @dba_lineage = @{$node_adaptor->fetch_ancestors($dba_node)};
  my @dba_ancestors;
  for my $lineage_node (@dba_lineage) {
    push @dba_ancestors, $lineage_node->names()->{'scientific name'}->[0];
  }
  return \@dba_ancestors;
}

sub process_division {
  my ( $self, $all_dbas, $division, $dbs ) = @_;
  my $species_count = 0;

  my %div_synonyms = %{ $self->param('div_synonyms') };
  if ( exists $div_synonyms{$division} ) {
    $division = $div_synonyms{$division};
  }

  $division = lc($division);
  $division =~ s/ensembl//;
  my $div_long = 'Ensembl' . ucfirst($division);

  foreach my $dba (@$all_dbas) {
    my $dbname = $dba->dbc->dbname();

    if ( $dbname =~ /$division\_.+_collection_/ ) {
      $self->add_species($dba, $dbs);
      $species_count++;
    }
    elsif ( $dbname !~ /_collection_/ ) {
      my $db_division;
      if ($dba->group eq 'core') {
        $db_division = $dba->get_MetaContainer->get_division();
      } else {
        my $dna_dba = $dba->dnadb();
        $db_division = $dna_dba->get_MetaContainer->get_division();
        unless ($db_division) {
          $self->throw("Could not retrieve DNA database for $dbname");
        }
      }

      if ( $div_long eq $db_division ) {
        $self->add_species($dba, $dbs);
        $species_count++;
      }
      $dba->dbc->disconnect_if_idle();
    }
  }
  $self->warning("$species_count species loaded for $division");
}

sub process_division_compara {
  my ( $self, $all_compara_dbas, $division, $compara_dbs ) = @_;

  foreach my $dba (@$all_compara_dbas) {
    my $compara_div = $dba->species();
    if ( $compara_div eq 'multi' ) {
      $compara_div = 'vertebrates';
    }
    if ( $compara_div eq $division ) {
      $$compara_dbs{$division} = $dba;
      $self->warning("Added compara for $division");
    }
  }
}

sub filter_species {
  my ( $self, $meta_key, $meta_value, $dbs ) = @_;

  foreach my $dbname ( keys %$dbs ) {
    foreach my $species ( keys %{ $$dbs{$dbname} } ) {
      my $dba = $$dbs{$dbname}{$species};
      my $meta_values = $dba->get_MetaContainer->list_value_by_key($meta_key);
      unless ( exists { map { $_ => 1 } @$meta_values }->{$meta_value} ) {
        $self->remove_species($dbname, $species, $dbs);
        $self->warning("$species removed by filter '$meta_key = $meta_value'" );
      }
    }
  }
}

1;

