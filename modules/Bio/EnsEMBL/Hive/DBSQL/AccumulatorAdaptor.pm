=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::AccumulatorAdaptor

=head1 SYNOPSIS

    $dba->get_AccumulatorAdaptor->store( \@rows );

=head1 DESCRIPTION

    This is currently an "objectless" adaptor for building accumulated structures.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::AccumulatorAdaptor;

use strict;

use Bio::EnsEMBL::Hive::Utils ('destringify');

use base ('Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor');


sub default_table_name {
    return 'accu';
}


sub fetch_structures_for_job_id {
    my ($self, $receiving_job_id) = @_;

    my $sql = 'SELECT struct_name, key_signature, value FROM accu WHERE receiving_job_id=?';
    my $sth = $self->prepare( $sql );
    $sth->execute( $receiving_job_id );

    my %structures = ();

    ROW: while(my ($struct_name, $key_signature, $stringified_value) = $sth->fetchrow() ) {

        my $value = destringify($stringified_value);

        my $sptr = \$structures{$struct_name};

        while( $key_signature=~/(?:(?:\[(\w*)\])|(?:\{(\w*)\}))/g) {
            my ($array_index, $hash_key) = ($1, $2);
            if(defined($array_index)) {
                unless(length($array_index)) {
                    $array_index = scalar(@{$$sptr||[]});
                }
                $sptr = \$$sptr->[$array_index];
            } elsif(defined($hash_key)) {
                if(length($hash_key)) {
                    $sptr = \$$sptr->{$hash_key};
                } else {
                    $sptr = \$$sptr->{$value};
                    $$sptr++;
                    next ROW;
                }
            }
        }
        $$sptr = $value;
    }
    $sth->finish;

    return \%structures;
}

1;
