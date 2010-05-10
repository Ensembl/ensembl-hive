
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::ProcessWithParams

=head1 SYNOPSIS

This module extends Bio::EnsEMBL::Hive::Process by implementing the following capabilities:

    1) parsing of parameters in the right order of precedence (including built-in defaults, if supplied)
            #
            # $self->param_init('taxon_id' => 10090, 'source' => 'UniProt');
            #
        Note: you should only be running the parser $self->param_init(...) manually
              if you want to supply built-in defaults, otherwise it will run by itself - no need to worry.

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

This module extends Bio::EnsEMBL::Hive::Process by implementing a generic param() method that sets module parameters
accorting to the following parameter precedence rules:

    (1) Job-Specific parameters defined in analysis_job.input_id hash, they have the highest priority and override everything else.

    (2) Analysis-Wide parameters defined in analysis.parameters hash. Can be overridden by (1).

    (3) Pipeline-Wide parameters defined in the 'meta' table. Can be overridden by (1) and (2).

    (4) Module_Defaults that are hard-coded into modules have the lowest precedence. Can be overridden by (1), (2) and (3).

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::ProcessWithParams;

use strict;
use Bio::EnsEMBL::Hive::Utils 'destringify';  # import 'destringify()'
use base ('Bio::EnsEMBL::Hive::Process');


=head2 strict_hash_format

    Description: This public virtual method should either return 1 or 0, depending on whether it is expected that input_id() and parameters() contain a hashref or not

    Callers    : Bio::EnsEMBL::Hive::RunnableDB::SystemCmd
                 and Bio::EnsEMBL::Hive::RunnableDB::SqlCmd

=cut

sub strict_hash_format {    # This public virtual must be redefined to "return 0;" in all inheriting classes
                            # that want more flexibility for the format of parameters() or input_id()
    return 1;
}

=head2 param_init

    Args       : (optional) a hash that defines Module_Defaults

    Example    : $self->param_init('taxon_id' => 10090, 'source' => 'UniProt');

    Description: Parses the parameters from all sources in the correct precedence order.
                 Can be invoked explicitly with defaults, or will run implicitly before a call to param().

=cut

sub param_init {    # normally will run automatically on the first execution of $self->param(),
                    # but you can enforce it by running explicitly, optionally supplying the default values
                    
    my $self     = shift @_;

    if( !$self->{'_param_hash'} or scalar(@_) ) {

        my $defaults_hash    = scalar(@_) ? { @_ } : {};            # module-wide built-in defaults have the lowest precedence (will always be the same for this module)

        my $meta_params_hash = $self->_parse_meta();                # then come the pipeline-wide parameters from the 'meta' table (define things common to all modules in this pipeline)

        my $parameters_hash  = $self->_parse_string('parameters');  # analysis-wide 'parameters' are even more specific (can be defined differently for several occurence of the same module)

        my $input_id_hash    = $self->_parse_string('input_id');    # job-specific 'input_id' parameters have the highest precedence

        $self->{'_param_hash'} = { %$defaults_hash, %$meta_params_hash, %$parameters_hash, %$input_id_hash };
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

    $self->param_init(); # normally will only run on the first execution

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
         $structure=~s/(?:#(\w+?)#)/$self->param($1)/eg;
        return $structure;
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

#--------------------------------------------[private methods]----------------------------------------------

=head2 _parse_string
    
    Description: this is a private method that deals with parsing of parameters out of strings.

=cut

sub _parse_string {
    my ($self, $method) = @_;

    my $string = $self->$method();

    if($self->strict_hash_format() or $string=~/^\{.*\}$/) {
        my $param_hash = eval($string) || {};
        if($@ or (ref($param_hash) ne 'HASH')) {
            die "The module '".ref($self)."' for analysis '".$self->analysis->logic_name()
                ."' assumes analysis.$method should evaluate into a {'param'=>'value'} hashref."
                ." The current value is '$string'\n";
        }
        return $param_hash;
    } else {
        return {};
    }
}

=head2 _parse_meta
    
    Description: this is a private method that deals with parsing of parameters out of 'meta' table.

=cut

sub _parse_meta {            # Unfortunately, MetaContainer is useless for us, as we need to load all the parameters in one go
    my $self = shift @_;

    my %meta_params_hash = ();

        # Here we are assuming that meta_keys are unique.
        # If they are not, you'll be getting the value with the highest meta_id.
        #
    my $sth = $self->db->dbc()->prepare("SELECT meta_key, meta_value FROM meta ORDER BY meta_id");
    $sth->execute();
    while (my ($meta_key, $meta_value)=$sth->fetchrow_array()) {

        $meta_params_hash{$meta_key} = destringify($meta_value);
    }
    $sth->finish();

    return \%meta_params_hash;
}

1;
