package Bio::EnsEMBL::Hive::Cacheable;

use Data::Dumper;
use Bio::EnsEMBL::Hive::Utils::Collection;

our $cache_by_class;    # global Hash-of-Hashes


sub collection {
    my $class = shift @_;

    if(@_) {
        $cache_by_class{$class} = shift @_;
    }

    return $cache_by_class{$class} ||= Bio::EnsEMBL::Hive::Utils::Collection->new();
}


1;
