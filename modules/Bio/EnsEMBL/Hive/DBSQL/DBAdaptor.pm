#
# BioPerl module for DBSQL::Obj
#
# Cared for by Ewan Birney <birney@sanger.ac.uk>
#
# Copyright Ewan Birney
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Hive::DBSQL::DBAdaptor

=head1 SYNOPSIS

    $db = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(
        -user   => 'root',
        -dbname => 'pog',
        -host   => 'caldy',
        -driver => 'mysql',
        );


=head1 DESCRIPTION
  This object represents the handle for a Hive system enabled database

=head1 CONTACT

Post questions the the EnsEMBL developer list: <ensembl-dev@ebi.ac.uk>

=cut


# Let the code begin...


package Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::DBSQL::DBConnection;
use Bio::EnsEMBL::DBSQL::DBAdaptor;

@ISA = qw( Bio::EnsEMBL::DBSQL::DBAdaptor );


sub get_AnalysisAdaptor {
  my $self = shift;
  return $self->_get_adaptor("Bio::EnsEMBL::DBSQL::AnalysisAdaptor" );
}

sub get_Queen {
  my $self = shift;

  return $self->_get_adaptor("Bio::EnsEMBL::Hive::Queen" );
}

sub get_AnalysisJobAdaptor {
  my $self = shift;
  return $self->_get_adaptor("Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor" );
}

sub get_AnalysisStatsAdaptor {
  my $self = shift;
  return $self->_get_adaptor("Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor" );
}

sub get_DataflowRuleAdaptor {
  my $self = shift;
  return $self->_get_adaptor("Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor" );
}

sub get_AnalysisCtrlRuleAdaptor {
  my $self = shift;
  return $self->_get_adaptor("Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor" );
}

1;

