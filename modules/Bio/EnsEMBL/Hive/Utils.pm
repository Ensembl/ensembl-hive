package Bio::EnsEMBL::Hive::Utils;

=head1 NAME

Bio::EnsEMBL::Hive::Utils

=head1 DESCRIPTION

Let's keep here various utility functions that are not proper Extensions (do not cunningly extend other classes)

You can either inherit from this package, call the functions directly or import:


=head1 Example of inheritance:

use base ('Bio::EnsEMBL::Hive::Utils', ...);

my $input_id_string = $self->stringify($input_id_hash);



=head1 Example of a direct call:

use Bio::EnsEMBL::Hive::Utils;

my $input_id_string = Bio::EnsEMBL::Hive::Utils::stringify($input_id_hash);



=head1 Example of import:

use Bio::EnsEMBL::Hive::Utils 'stringify';

my $input_id_string = stringify($input_id_hash);


=head1 Author

Leo Gordon, lg4@ebi.ac.uk

=cut

use strict;
use warnings;
use Data::Dumper;

use Exporter 'import';
our @EXPORT_OK = qw( stringify );

sub stringify {
    my $structure = pop @_;

    local $Data::Dumper::Indent   = 0;  # we want everything on one line
    local $Data::Dumper::Terse    = 1;  # and we want it without dummy variable names
    local $Data::Dumper::Sortkeys = 1;  # make stringification more deterministic

    return Dumper($structure);
}

1;

