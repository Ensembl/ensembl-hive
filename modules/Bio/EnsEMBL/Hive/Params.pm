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
            #       $runObj->param_defaults(),          # module-wide built-in defaults have the lowest precedence (will always be the same for this module)
            #       $hive_pipeline->params_as_hash(),   # then come the pipeline-wide parameters from the 'pipeline_wide_parameters' table (define things common to all analyses in this pipeline)
            #       $self->analysis->parameters(),      # analysis-wide 'parameters' are even more specific (can be defined differently for several occurence of the same module)
            #       $job->input_id(),                   # job-specific 'input_id' parameters have the highest precedence
            #       $job->accu_hash(),                  # parameters accumulated and sent for this job by other preceding jobs
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
    that both analysis.parameters and job.input_id fields contain a Perl-style parameter hashref as a string.

    This module implements a generic param() method that allows to set parameters according to the following parameter precedence rules:

        (1) Job-Specific parameters defined in job.input_id hash, they have the highest priority and override everything else.

        (2) Analysis-Wide parameters defined in analysis.parameters hash. Can be overridden by (1).

        (3) Pipeline-Wide parameters defined in the 'meta' table. Can be overridden by (1) and (2).

        (4) Module_Defaults that are hard-coded into modules have the lowest precedence. Can be overridden by (1), (2) and (3).


    param_exists() returns 1 if the parameter is present and can be substituted,
                           undef if the substitution failed.
                           0 if the parameter is absent,
    param_is_defined() returns 1 if the parameter is present and can be substituted to a defined value,
                               undef if the substitution fails,
                               0 otherwise.
    param() returns the value if param_exists() returned true, undef otherwise.
    param_required() is like param() but dies instead of returning undef.

    In practice. given this hash of parameters:
    {
        'a' => 3,
        'b' => undef,
        'c' => '#other#',
    }
    the Params API would return:

                       |  a     b       c       d
    -------------------+----------------------------
    param_exists()     |  1     1     undef     0
    param_is_defined() |  1     0     undef     0
    param()            |  3   undef   undef   undef
    param_required()   |  3   (die)   (die)   (die)


=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2024] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Params;

use strict;
use warnings;

use List::Util qw(first min max minstr maxstr reduce sum shuffle);              # make them available for substituted expressions
use Bio::EnsEMBL::Hive::Utils ('stringify', 'dir_revhash', 'go_figure_dbc', 'throw');    # NB: dir_revhash() is used by some substituted expressions, do not remove!


=head2 new

    Description: a trivial constructor, mostly for testing a Params object

=cut

sub new {
    my $class = shift @_;

    return bless {}, $class;
}


=head2 fuse_param_hashes

    Description: Performs the actual task of evaluating and fusing/merging a preference list of parameter hashes into one parameter hash.

=cut

sub fuse_param_hashes {
    my $self = shift @_; # NB: other parameters will be shifted off it

    my %fused_hash = ();

    foreach my $source (@_) {
        if(ref($source) ne 'HASH') {
            my $param_hash;
               $param_hash = eval($source) if(defined($source));
               $param_hash = {} if(!defined($param_hash));

            if($@) {
                die "Could not evaluate '$source': $@\n";
            } elsif(ref($param_hash) ne 'HASH') {
                die "Expected a {'param'=>'value'} hashref, but got the following string instead: '$source'\n";
            }
            $source = $param_hash;
        }
        while(my ($k,$v) = each %$source ) {
            $fused_hash{$k} = $v;
        }
    }

    return \%fused_hash;
}


=head2 param_init

    Description: Sets up the unsubstituted parameters in the right precedence order (called by AnalysisJob::load_parameters)

=cut

sub param_init {
    my $self = shift @_; # NB: other parameters will be shifted off it

    $self->{'_unsubstituted_param_hash'} = $self->fuse_param_hashes( @_ );
    $self->{'_param_hash'} = {};
}


sub _param_possibly_overridden {
    my ($self, $param_name, $overriding_hash) = @_;

    return ( ( (ref($overriding_hash) eq 'HASH') && exists($overriding_hash->{ $param_name }) )
                    ? $overriding_hash->{ $param_name }
                    : $self->_param_silent($param_name)
           );
}


sub _param_silent {
    my $self        = shift @_;
    my $param_name  = shift @_
        or throw("ParamError: calling param() without arguments");

    if(@_) { # If there is a value (even if undef), then set it!
        my $new_val = shift @_;
        if (@_ and (shift)) {
            # If there is an extra parameter after the value, it means that
            # the value is unsubstituted
            $self->{'_unsubstituted_param_hash'}{$param_name} = $new_val;
        } else {
            $self->{'_param_hash'}{$param_name} = $new_val;
        }
    } elsif( !exists( $self->{'_param_hash'}{$param_name}) ) {
        if (exists( $self->{'_unsubstituted_param_hash'}{$param_name} ) ) {
            my $ini_used_missing_param = $self->{'_used_missing_params'};
            delete $self->{'_used_missing_params'};
            my $unsubstituted = $self->{'_unsubstituted_param_hash'}{$param_name};
            my $substituted = $self->param_substitute( $unsubstituted );
            if (my $failed_dep = $self->{'_used_missing_params'}) {
                delete $self->{'_used_missing_params'};
                delete $self->{'_substitution_in_progress'};
                die "ParamError: the evaluation of '$param_name' requires '$failed_dep' which is missing\n";
            }
            $self->{'_param_hash'}{$param_name} = $substituted;
            $self->{'_used_missing_params'} = $ini_used_missing_param if $ini_used_missing_param;
        } else {
            $self->{'_used_missing_params'} = $param_name;
        }
    } else {
        # The parameter has already been substituted
    }

    return exists( $self->{'_param_hash'}{$param_name} )
                ? $self->{'_param_hash'}{$param_name}
                : undef;
}


=head2 param_required

    Arg [1]    : string $param_name

    Description: A strict getter method for a job's parameter; will die if the parameter was not set or is undefined

    Example    : my $source = $self->param_required('source');

    Returntype : any Perl structure or object that you dared to store

=cut

sub param_required {
    my $self        = shift @_;
    my $param_name  = shift @_;

    my $value = $self->_param_silent($param_name);

    return defined( $value )
            ? $value
            : die "ParamError: value for param_required('$param_name') is required and has to be defined\n";
}


=head2 param_exists

    Arg [1]    : string $param_name

    Description: A predicate tester for whether the parameter has been initialized (even to undef)

    Example    : if( $self->param_exists('source') ) { print "'source' exists\n"; } else { print "never heard of 'source'\n"; }

    Returntype : boolean

=cut

sub param_exists {
    my $self        = shift @_;
    my $param_name  = shift @_;

    $self->_param_silent($param_name);
    if (exists( $self->{'_param_hash'}{$param_name} )) {
        return 1;
    } elsif (exists( $self->{'_unsubstituted_param_hash'}{$param_name} )) {
        # In this case, the substitution failed
        return undef;
    } else {
        return 0;
    }
}

=head2 param_is_defined

    Arg [1]    : string $param_name

    Description: A predicate tester for definedness of a parameter

    Example    : if( $self->param_is_defined('source') ) { print "defined, possibly zero"; } else { print "undefined"; }

    Returntype : boolean

=cut

sub param_is_defined {
    my $self        = shift @_;
    my $param_name  = shift @_;

    my $value = $self->_param_silent($param_name);
    if (exists( $self->{'_param_hash'}{$param_name} )) {
        return (defined $value ? 1 : 0);
    } elsif (exists( $self->{'_unsubstituted_param_hash'}{$param_name} )) {
        # In this case, the substitution failed
        return undef;
    } else {
        return 0;
    }
}


=head2 param

    Arg [1]    : string $param_name

    Arg [2]    : (optional) $param_value

    Arg [3]    : (optional) $value_needs_substitution (in case you want to define a parameter with '#other_param#' and let the system compute its true value later)

    Description: A getter/setter method for a job's parameters that are initialized through multiple levels of precedence (see param_init() )

    Example 1  : my $source = $self->param('source'); # acting as a getter

    Example 2  : $self->param('binpath', '/software/ensembl/compara');  # acting as a setter

    Returntype : any Perl structure or object that you dared to store

=cut

sub param {
    my $self        = shift @_;
    my $param_name  = shift @_
        or throw("ParamError: calling param() without arguments");

    my $value = $self->_param_silent( $param_name, @_ );
    
    unless( exists( $self->{'_param_hash'}{$param_name} )) {
        warn "ParamWarning: value for param('$param_name') is used before having been initialized!\n";
    }

    return $value;
}


=head2 param_substitute

    Arg [1]    : Perl structure $string_with_templates

    Description: Performs parameter substitution on strings that contain templates like " #param_name# followed by #another_param_name# " .

    Returntype : *another* Perl structure with matching topology (may be more complex as a result of substituting a substructure for a term)

=cut

sub param_substitute {
    my ($self, $structure, $overriding_hash) = @_;

    my $ref_type = ref($structure);

    if(!$ref_type) {

        if(!$structure) {

            return $structure;

        } elsif($structure=~/^(?:#(expr\(.+?\)expr|[\w:]+)#)$/) {   # if the given string is one complete substitution, we don't want to force the output into a string

            return $self->_subst_one_hashpair($1, $overriding_hash);

        } else {
            my $scalar_defined  = 1;

            $structure=~s/(?:#(expr\(.+?\)expr|[\w:]+)#)/my $value = $self->_subst_one_hashpair($1, $overriding_hash); $scalar_defined &&= defined($value); $value/eg;

            return $scalar_defined ? $structure : undef;
        }

    } elsif($ref_type eq 'ARRAY') {
        my @substituted_array = ();
        foreach my $element (@$structure) {
            push @substituted_array, $self->param_substitute($element, $overriding_hash);
        }
        return \@substituted_array;
    } elsif($ref_type eq 'HASH') {
        my %substituted_hash = ();
        while(my($key,$value) = each %$structure) {
            $substituted_hash{$self->param_substitute($key, $overriding_hash)} = $self->param_substitute($value, $overriding_hash);
        }
        return \%substituted_hash;
    } else {
        warn "Could not substitute parameters in '$structure' - unsupported data type '$ref_type'\n";
        return $structure;
    }
}


sub mysql_conn { # an example stringification formatter (others can be defined here or in a descendent of Params)
    my ($self, $db_conn) = @_;

    if(ref($db_conn) eq 'HASH') {
        return "--host=$db_conn->{-host} --port=$db_conn->{-port} --user='$db_conn->{-user}' --password='$db_conn->{-pass}' $db_conn->{-dbname}";
    } else {
        my $dbc = go_figure_dbc( $db_conn );
        return '--host='.$dbc->host.' --port='.$dbc->port." --user='".$dbc->username."' --password='".$dbc->password."' ".$dbc->dbname;
    }
}

sub mysql_dbname { # another example stringification formatter
    my ($self, $db_conn) = @_;

    if(ref($db_conn) eq 'HASH') {
        return $db_conn->{-dbname};
    } else {
        my $dbc = go_figure_dbc( $db_conn );
        return $dbc->dbname;
    }
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
    my ($self, $inside_hashes, $overriding_hash) = @_;

    if($self->{'_substitution_in_progress'}{$inside_hashes}++) {
        die "ParamError: substitution loop among {".join(', ', map {"'$_'"} keys %{$self->{'_substitution_in_progress'}})."} has been detected\n";
    }

    my $value;

    # FIXME does not allow substitution of parameters names that have non-alphanumeric characters
    if($inside_hashes=~/^\w+$/) {

        $value =  $self->_param_possibly_overridden($inside_hashes, $overriding_hash);

    } elsif($inside_hashes=~/^(\w+):(\w+)$/) {

        $value = $self->$1($self->_param_possibly_overridden($2, $overriding_hash));

    } elsif($inside_hashes=~/^expr\((.*)\)expr$/) {

        my $expression = $1;

        if($expression=~/\$\w+/) {
            warn "ParamWarning: possibly using old substitution syntax in expression '$expression'; please use new syntax '#alpha#' instead of old '\$alpha'.\n";
        }

        $expression=~s{(?:#(\w+)#)}{\$self->_param_possibly_overridden('$1', \$overriding_hash)}g;

        $value = eval "return ($expression)";   # NB: 'return' is needed to protect the hashrefs from being interpreted as scoping blocks
                                                #       and parentheses are needed because return binds stronger than 'and' and 'or'

        if ($@) {
            delete $self->{'_substitution_in_progress'}{$inside_hashes};    # to allow re-entering the sub
            die $@ if $@ =~ /^ParamError/;                                  # re-raise the underlying Param error
            die "ParamError: Cannot evaluate the expression: '$inside_hashes' ==> '$expression'\n$@";
        }
    }

    delete $self->{'_substitution_in_progress'}{$inside_hashes};
    return $value;
}

1;
