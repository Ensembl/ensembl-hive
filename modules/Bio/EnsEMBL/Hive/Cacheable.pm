package Bio::EnsEMBL::Hive::Cacheable;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('stringify');
use Bio::EnsEMBL::Hive::Utils::Collection;

our %cache_by_class;    # global Hash-of-Hashes


sub collection {
    my $class = shift @_;

    if(@_) {
        $cache_by_class{$class} = shift @_;
    }

    return $cache_by_class{$class};
}


sub unikey {    # to be redefined by individual Cacheable classes
    return undef;
}


sub add_new_or_update {
    my $class = shift @_;

    my $self;

    if( my $unikey_keys = $class->unikey() ) {
        my %other_pairs = @_;
        my %unikey_pairs;
        @unikey_pairs{ @$unikey_keys} = delete @other_pairs{ @$unikey_keys };

        if( $self = $class->collection()->find_one_by( %unikey_pairs ) ) {
            my $found_display = UNIVERSAL::can($self, 'toString') ? $self->toString : stringify($self);
            if(keys %other_pairs) {
                warn "Updating $found_display with (".stringify(\%other_pairs).")\n";
                if( ref($self) eq 'HASH' ) {
                    @$self{ keys %other_pairs } = values %other_pairs;
                } else {
                    while( my ($key, $value) = each %other_pairs ) {
                        $self->$key($value);
                    }
                }
            } else {
                warn "Found a matching $found_display\n";
            }
        }
    } else {
        warn "$class doesn't redefine unikey(), so unique objects cannot be identified";
    }

    unless( $self ) {
        $self = $class->can('new') ? $class->new( @_ ) : { @_ };

        my $found_display = UNIVERSAL::can($self, 'toString') ? $self->toString : 'naked entry '.stringify($self);
        warn "Created a new $found_display\n";

        $class->collection()->add( $self );
    }

    return $self;
}


1;
