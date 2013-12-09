=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::AnalysisDataAdaptor

=head1 SYNOPSIS

    $dataDBA = $db_adaptor->get_AnalysisDataAdaptor;

=head1 DESCRIPTION

   analysis_data table holds LONGTEXT data that is currently used as an extension of some fixed-width fields of 'job' table.
   It is no longer general-purpose. Please avoid accessing this table directly or via the adaptor.

=head1 LICENSE

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

    The rest of the documentation details each of the object methods.
    Internal methods are preceded with a _

=cut


package Bio::EnsEMBL::Hive::DBSQL::AnalysisDataAdaptor;

use strict;

use base ('Bio::EnsEMBL::DBSQL::BaseAdaptor');


sub fetch_by_dbID {
  my ($self, $data_id) = @_;

  my $sql = "SELECT data FROM analysis_data WHERE analysis_data_id = ?";
  my $sth = $self->prepare($sql);
  $sth->execute($data_id);

  my ($data) = $sth->fetchrow_array();
  $sth->finish();
  return $data;
}

#
# STORE METHODS
#
################

sub store {
  my ($self, $data) = @_;
  
  return 0 unless($data);
  
  my $sth = $self->prepare("INSERT INTO analysis_data (data) VALUES (?)");
  $sth->execute($data);
  my $data_id = $self->dbc->db_handle->last_insert_id(undef, undef, 'analysis_data', 'analysis_data_id');
  $sth->finish;

  return $data_id;
}


sub store_if_needed {
  my ($self, $data) = @_;
  my $data_id;

  return 0 unless($data);

  my $sth = $self->prepare("SELECT analysis_data_id FROM analysis_data WHERE data = ?");
  $sth->execute($data);
  ($data_id) = $sth->fetchrow_array();
  $sth->finish;

  if($data_id) {
    # print("data already stored as id $data_id\n");
    return $data_id;
  }

  return $self->store($data);
}

1;





