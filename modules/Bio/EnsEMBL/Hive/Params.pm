
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::Params

=head1 SYNOPSIS

By inheriting from this module you make your module able to deal with parameters:

    1) parsing of parameters in the order of precedence, starting with the lowest:
            #
            ## general usage:
            # $self->param_init( $lowest_precedence_hashref, $middle_precedence_hashref, $highest_precedence_hashref );
            #
            ## typical usage:
            # $job->param_init( 
            #       $runObj->param_defaults(),                      # module-wide built-in defaults have the lowest precedence (will always be the same for this module)
            #       $self->db->get_MetaContainer->get_param_hash(), # then come the pipeline-wide parameters from the 'meta' table (define things common to all modules in this pipeline)
            #       $self->analysis->parameters(),                  # analysis-wide 'parameters' are even more specific (can be defined differently for several occurence of the same module)
            #       $job->input_id(),                               # job-specific 'input_id' parameters have the highest precedence
            # );
          

    2) reading a parameter's value
            #
            #  my $source = $self->param('source'); )

    3) dynamically setting a parameter's value
            #
            #  $self->param('binpath', '/software/ensembl/compara');
            #
        Note: It proved to be a convenient mechanism to exchange params
              between fetch_input(), run(), write_output() and other methods.

=head1 DESCRIPTION

Most of Compara RunnableDB methods work under assumption
that both analysis.parameters and analysis_job.input_id fields contain a Perl-style parameter hashref as a string.

This module implements a generic param() method that allows to set parameters according to the following parameter precedence rules:

    (1) Job-Specific parameters defined in analysis_job.input_id hash, they have the highest priority and override everything else.

    (2) Analysis-Wide parameters defined in analysis.parameters hash. Can be overridden by (1).

    (3) Pipeline-Wide parameters defined in the 'meta' table. Can be overridden by (1) and (2).

    (4) Module_Defaults that are hard-coded into modules have the lowest precedence. Can be overridden by (1), (2) and (3).

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::Params;

use strict;
use Bio::EnsEMBL::Hive::Utils ('stringify');  # import stringify()


=head2 param_init

    Description: Parses the parameters from all sources in the reverse precedence order (supply the lowest precedence hash first).

=cut

sub param_init {
                    
    my $self                = shift @_;
    my $strict_hash_format  = shift @_;

    if( !$self->{'_param_hash'} ) {

        $self->{'_param_hash'} = {};

        foreach my $source (@_) {
            if(ref($source) ne 'HASH') {
                if($strict_hash_format or $source=~/^\{.*\}$/) {
                    my $param_hash = eval($source) || {};
                    if($@ or (ref($param_hash) ne 'HASH')) {
                        die "Expected a {'param'=>'value'} hashref, but got the following string instead: '$source'\n";
                    }
                    $source = $param_hash;
                } else {
                    $source = {};
                }
            }
            while(my ($k,$v) = each %$source ) {
                $self->{'_param_hash'}{$k} = $v;
            }
        }
    }
}


=head2 param

    Arg [1]    : string $param_name

    Arg [2]    : (optional) $param_value

    Description: A getter/setter method for a job's parameters that are initialized through 4 levels of precedence (see param_init() )

    Example 1  : my $source = $self->param('source'); # acting as a getter

    Example 2  : $self->param('binpath', '/software/ensembl/compara');  # acting as a setter

    Returntype : any Perl structure or object that you dared to store

=cut

sub param {
    my $self = shift @_;

    my $param_name = shift @_;
    if(@_) { # If there is a value (even if undef), then set it!
        $self->{'_param_hash'}{$param_name} = shift @_;
    }

    return $self->{'_param_hash'}{$param_name};
}

=head2 param_substitute

    Arg [1]    : Perl structure $string_with_templates

    Description: Performs parameter substitution on strings that contain templates like " #param_name# followed by #another_param_name# " .

    Returntype : *another* Perl structure with matching topology (may be more complex as a result of substituting a substructure for a term)

=cut

sub param_substitute {
    my ($self, $structure) = @_;

    my $type = ref($structure);

    if(!$type) {

        if($structure=~/^#([^#]*)#$/) {    # if the given string is one complete substitution, we don't want to force the output into a string

            return $self->_subst_one_hashpair($1);

        } else {

            $structure=~s/(?:#(.+?)#)/$self->_subst_one_hashpair($1)/eg;
            return $structure;
        }

    } elsif($type eq 'ARRAY') {
        my @substituted_array = ();
        foreach my $element (@$structure) {
            push @substituted_array, $self->param_substitute($element);
        }
        return \@substituted_array;
    } elsif($type eq 'HASH') {
        my %substituted_hash = ();
        while(my($key,$value) = each %$structure) {
            $substituted_hash{$self->param_substitute($key)} = $self->param_substitute($value);
        }
        return \%substituted_hash;
    } else {
        die "Could not substitute parameters in $structure";
    }
}


sub mysql_conn { # an example stringification formatter (others can be defined here or in a descendent of Params)
    my ($self, $db_conn) = @_;

    return "--host=$db_conn->{-host} --port=$db_conn->{-port} --user='$db_conn->{-user}' --pass='$db_conn->{-pass}' $db_conn->{-dbname}";
}

sub mysql_dbname { # another example stringification formatter
    my ($self, $db_conn) = @_;

    return $db_conn->{-dbname};
}

sub csvq { # another example stringification formatter
    my ($self, $list) = @_;

    return join(',', map { "'$_'" } @$list);
}

#--------------------------------------------[private methods]----------------------------------------------

=head2 _subst_one_hashpair
    
    Description: this is a private method that performs one substitution. Called by param_substitute().

=cut

sub _subst_one_hashpair {
    my ($self, $inside_hashes) = @_;

    if($inside_hashes=~/^\w+$/) {

        return $self->param($inside_hashes);

    } elsif($inside_hashes=~/^(\w+):(\w+)$/) {

        return $self->$1($self->param($2));

    } elsif($inside_hashes=~/^expr\((.*)\)expr$/) {

        my $expression = $1;
        $expression=~s/(?:\$(\w+))/stringify($self->param($1))/eg;

        return eval($expression);
    }
}

1;
