#
# BioPerl module for DBSQL::Obj
#
# Cared for by Ewan Birney <birney@sanger.ac.uk>
#
# Copyright Ewan Birney
#
# You may distribute this module under the same terms as perl itself

=pod

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

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

use strict;

use Bio::EnsEMBL::Utils::Argument ('rearrange');

use Bio::EnsEMBL::Hive::URLFactory;
use Bio::EnsEMBL::Hive::DBSQL::DBConnection;

use base ('Bio::EnsEMBL::DBSQL::DBAdaptor');


sub new {
    my ($class, @args) = @_;

    my ($url) = rearrange(['URL'], @args);
    if($url) {
        return Bio::EnsEMBL::Hive::URLFactory->fetch($url) || die "Unable to connect to '$url'\n";
    } else {
        return $class->SUPER::new(@args);
    }
}


sub dbc {
    my $self = shift @_;

    my $dbc = $self->SUPER::dbc( @_ );
    bless $dbc, 'Bio::EnsEMBL::Hive::DBSQL::DBConnection' if( $dbc );

    return $dbc;
}


sub hive_use_triggers {  # getter only, not setter
    my $self = shift @_;

    unless( defined($self->{'_hive_use_triggers'}) ) {
        my $hive_use_triggers = $self->get_MetaAdaptor->fetch_by_meta_key( 'hive_use_triggers' );
        $self->{'_hive_use_triggers'} = $hive_use_triggers || 0;
    } 
    return $self->{'_hive_use_triggers'};
}


sub get_available_adaptors {
 
    my %pairs =  (
            # Core adaptors extended with Hive stuff:
        'MetaContainer'         => 'Bio::EnsEMBL::Hive::DBSQL::MetaContainer',

            # "new" Hive adaptors (sharing the same fetching/storing code inherited from the BaseAdaptor class) :
        'AnalysisCtrlRule'      => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor',
        'DataflowRule'          => 'Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor',
        'ResourceDescription'   => 'Bio::EnsEMBL::Hive::DBSQL::ResourceDescriptionAdaptor',
        'ResourceClass'         => 'Bio::EnsEMBL::Hive::DBSQL::ResourceClassAdaptor',
        'LogMessage'            => 'Bio::EnsEMBL::Hive::DBSQL::LogMessageAdaptor',
        'NakedTable'            => 'Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor',
        'Analysis'              => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisAdaptor',
        'Queen'                 => 'Bio::EnsEMBL::Hive::Queen',
        'AnalysisData'          => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisDataAdaptor',
        'Accumulator'           => 'Bio::EnsEMBL::Hive::DBSQL::AccumulatorAdaptor',
        'Meta'                  => 'Bio::EnsEMBL::Hive::DBSQL::MetaAdaptor',

            # "old" Hive adaptors (having their own fetching/storing code) :
        'AnalysisJob'           => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor',
        'AnalysisStats'         => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor',
    );
    return \%pairs;
}

1;
