=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::DependentOptions

=head1 DESCRIPTION

    A parser for PipeConfig files that understands how and when to substitute $self->o() expressions.

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

=cut


package Bio::EnsEMBL::Hive::DependentOptions;

use strict;
use warnings;
use Getopt::Long qw(:config pass_through);

use Bio::EnsEMBL::Hive::Utils ('stringify');


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


sub is_fully_substituted_string {
    my $self    = shift @_;
    my $input   = shift @_;

    return (!defined($input) || $input !~ /#\:.+?\:#/);
}


sub is_fully_substituted_structure {
    my $self    = shift @_;
    my $input   = shift @_;

    unless(my $ref_type = ref($input)) {

        return $self->is_fully_substituted_string($input);

    } elsif($ref_type eq 'HASH') {
        foreach my $value (values %$input) {
            unless($self->is_fully_substituted_structure($value)) {
                return 0;
            }
        }
    } elsif($ref_type eq 'ARRAY') {
        foreach my $element (@$input) {
            unless($self->is_fully_substituted_structure($element)) {
                return 0;
            }
        }
    }
    return 1;
}


sub hash_leaves {
    my ($self, $hash_to, $source, $prefix) = @_;

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
    } elsif(!$self->is_fully_substituted_string($source)) {
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
        and ((ref($ptr->{$option_syll}) eq 'HASH') or $self->is_fully_substituted_string( $ptr->{$option_syll} ))
        ) {
            $ptr = $ptr->{$option_syll};        # just descend one level
        } elsif(@_) {
            $ptr = $ptr->{$option_syll} = {};   # force intermediate level vivification, even if it overwrites a fully_substituted_string
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

    if($ref_type eq 'HASH') {
        foreach my $value (values %$$ref) {
            $self->substitute( \$value );
        }
    } elsif($ref_type eq 'ARRAY') {
        foreach my $value (@$$ref) {
            $self->substitute( \$value );
        }
    } elsif( !$ref_type and defined($$ref) ) {

        if($$ref =~ /^#\:subst ([^:]+)\:#$/) {      # if the given string is one complete substitution, we don't want to force the output into a string
            $$ref = $self->o(split/->/,$1);
        } else {
            $$ref =~ s{(?:#\:subst (.+?)\:#)}{$self->o(split(/->/,$1))}eg;
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

    my $possibly_used_options = { 'ENV' => \%ENV };
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

                if($self->is_fully_substituted_structure($value)) {
                    #warn "Resolved rule: $key -> ".stringify($value)."\n";
                } else {
                    #warn "Unresolved rule: $key -> ".stringify($value)."\n";
                    $rules_to_go++;
                }
            }
        }
        $attempts--;
        #warn "=======================[$rules_to_go rules to go; $attempts attempts to go]=================\n\n";
        #warn " definitely_used_options{} contains: ".stringify($definitely_used_options)."\n";
    } while($rules_to_go and $attempts);

    #warn "=======================[out of the substitution loop]=================\n\n";

    my $missing_options = $self->hash_leaves( {}, $self->root, '' );

    if(scalar(keys %$missing_options)) {
        warn "Missing or incomplete definition of the following options:\n";
        foreach my $key (sort keys %$missing_options) {
            print "\t$key\n";
        }
        exit(1);
    } else {
        #warn "Done parsing options!\n";
    }
}

1;

