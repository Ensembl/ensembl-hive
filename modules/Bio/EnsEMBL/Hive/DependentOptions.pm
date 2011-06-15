
package Bio::EnsEMBL::Hive::DependentOptions;

use strict;
use warnings;
use Data::Dumper;
use Getopt::Long qw(:config pass_through);


sub new {
    my $class = shift @_;

    my $self = bless { @_ }, $class;

    return $self;
}


sub use_cases {      # getter/setter for the list of methods from where $self->o() is called
    my $self    = shift @_;

    if(@_) {
        $self->{_use_cases} = shift @_;
    }
    return $self->{_use_cases} || die "use_cases() has to be set before using";
}


sub load_cmdline_options {
    my $self        = shift @_;
    my $expected    = shift @_;
    my $target      = shift @_ || {};

    local @ARGV = @ARGV;    # make this function reenterable by forbidding it to modify the original parameters
    GetOptions( $target,
        map { my $ref_type = ref($expected->{$_}); $_=~m{\!$} ? $_ : ($ref_type eq 'HASH') ? "$_=s%" : ($ref_type eq 'ARRAY') ? "$_=s@" : "$_=s" } keys %$expected
    );
    return $target;
}


sub root {      # getter/setter for the root
    my $self    = shift @_;

    if(@_) {
        $self->{_root} = shift @_;
    }
    return $self->{_root} ||= {};
}


sub fully_defined_string {
    my $self    = shift @_;
    my $input   = shift @_;

    return $input !~ /#\:.+?\:#/;
}


sub fully_defined_structure {
    my $self    = shift @_;
    my $input   = shift @_;

    unless(my $ref_type = ref($input)) {

        return $self->fully_defined_string($input);

    } elsif($ref_type eq 'HASH') {
        foreach my $value (values %$input) {
            unless($self->fully_defined_structure($value)) {
                return 0;
            }
        }
    } elsif($ref_type eq 'ARRAY') {
        foreach my $value (@$input) {
            unless($self->fully_defined_structure($value)) {
                return 0;
            }
        }
    }
    return 1;
}


sub hash_leaves {
    my $self      = shift @_;
    my $hash_to   = shift @_ || {};
    my $source    = shift @_; unless(defined($source)) { $source = $self->root; }
    my $prefix    = shift @_ || '';

    if(ref($source) eq 'HASH') {
        while(my ($key, $value) = each %$source) {
            my $hash_element_prefix = ($prefix ? "$prefix->" : '') . "{'$key'}";

            $self->hash_leaves($hash_to, $value, $hash_element_prefix);
        }
    } elsif(ref($source) eq 'ARRAY') {
        foreach my $index (0..scalar(@$source)-1) {
            my $element = $source->[$index];
            my $array_element_prefix = ($prefix ? "$prefix->" : '') . "[$index]";

            $self->hash_leaves($hash_to, $element, $array_element_prefix);
        }
    } elsif(!$self->fully_defined_string($source)) {
        $hash_to->{$prefix} = 1;
    }

    return $hash_to;
}


sub o {
    my $self    = shift @_;

    my $ptr = $self->root();

    my @syll_seen = ();

    while(defined(my $option_syll = shift @_)) {
        push @syll_seen, $option_syll;

        if( exists($ptr->{$option_syll})
        and ((ref($ptr->{$option_syll}) eq 'HASH') or $self->fully_defined_string( $ptr->{$option_syll} ))
        ) {
            $ptr = $ptr->{$option_syll};        # just descend one level
        } elsif(@_) {
            $ptr = $ptr->{$option_syll} = {};   # force intermediate level vivification, even if it overwrites a fully_defined_string
        } else {
            $ptr = $ptr->{$option_syll} = "#:subst ".join('->',@syll_seen).":#";   # force leaf level vivification
        }
    }
    return $ptr;
}


sub substitute {
    my $self    = shift @_;
    my $ref     = shift @_;

    my $ref_type = ref($$ref);

    if(!$ref_type) {
        if($$ref =~ /^#\:subst ([^:]+)\:#$/) {      # if the given string is one complete substitution, we don't want to force the output into a string
            $$ref = $self->o(split/->/,$1);
        } else {
            $$ref =~ s{(?:#\:subst (.+?)\:#)}{$self->o(split(/->/,$1))}eg;
        }

    } elsif($ref_type eq 'HASH') {
        foreach my $value (values %$$ref) {
            $self->substitute( \$value );
        }
    } elsif($ref_type eq 'ARRAY') {
        foreach my $value (@$$ref) {
            $self->substitute( \$value );
        }
    }
    return $$ref;
}


sub merge_from_rules {
    my $self    = shift @_;
    my $from    = shift @_;
    my $top     = shift @_;

    my $ref_type = ref($$top);

    unless($ref_type) {
        $$top = $from;
    } elsif($ref_type eq 'HASH') {
        foreach my $key (keys %$from) {
            $self->merge_from_rules( $from->{$key}, \$$top->{$key} );
        }
    }
}

sub process_options {
    my $self    = shift @_;

    my $definitely_used_options = $self->root();

        # dry-run of these methods allows us to collect definitely_used_options
    foreach my $method (@{ $self->use_cases() }) {
        $self->$method();
    }

    my $possibly_used_options = {};
    $self->root( $possibly_used_options );

        # the first run of this method allows us to collect possibly_used_options
    my $rules = $self->default_options();

    $self->load_cmdline_options( { %$definitely_used_options, %$possibly_used_options }, $rules );

    $self->root( $definitely_used_options );


    my $rules_to_go;
    my $attempts = 32;
    do {
        $rules_to_go = 0;
        foreach my $key (keys %$definitely_used_options) {
            if(exists $rules->{$key}) {
                my $value = $self->substitute( \$rules->{$key} );

                    # it has to be intelligently (recursively, on by-element basis) merged back into the tree under $self->o($key):
                $self->merge_from_rules( $value, \$self->root->{$key} );

                if($self->fully_defined_structure($value)) {
                    # warn "Resolved rule: $key -> ".Dumper($value)."\n";
                } else {
                    # warn "Unresolved rule: $key -> ".Dumper($value)."\n";
                    $rules_to_go++;
                }
            }
        }
        #warn "=======================[$rules_to_go rules to go]=================\n\n";
        #warn " definitely_used_options{} contains: ".Dumper($definitely_used_options)."\n";
        $attempts--;
    } while($rules_to_go and $attempts);

    my $missing_options = $self->hash_leaves();
    if(scalar(keys %$missing_options)) {
        warn "Missing or incomplete definition of the following options:\n";
        foreach my $key (sort keys %$missing_options) {
            print "\t$key\n";
        }
        exit(1);
    } else {
        warn "Done parsing options!\n";
    }
}

1;

