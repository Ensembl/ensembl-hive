=pod

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::MetaContainer

=head1 SYNOPSIS

  $meta_container = $db_adaptor->get_MetaContainer;

=head1 DESCRIPTION

  This module extends EnsEMBL Core's MetaContainer, adding some Hive-specific stuff.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::MetaContainer;

use strict;
use Bio::EnsEMBL::Hive::Utils ('destringify');  # import both functions

use base ('Bio::EnsEMBL::DBSQL::MetaContainer');

=head2 get_param_hash

    Description: returns the content of the 'meta' table as a hash

=cut

sub get_param_hash {
    my $self = shift @_;

    my %meta_params_hash = ();

        # Here we are assuming that meta_keys are unique.
        # If they are not, you'll be getting the value with the highest meta_id.
        #
    my $sth = $self->prepare("SELECT meta_key, meta_value FROM meta ORDER BY meta_id");
    $sth->execute();
    while (my ($meta_key, $meta_value)=$sth->fetchrow_array()) {

        $meta_params_hash{$meta_key} = destringify($meta_value);
    }
    $sth->finish();

    return \%meta_params_hash;
}

1;
