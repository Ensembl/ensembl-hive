=pod

This module extends Bio::EnsEMBL::Hive::Process by implementing param() method.

A majority of Compara RunnableDB methods work under assumption
that both analysis.parameters and analysis_job.input_id fields contain a Perl-style parameter hashref as a string.

This module implements the following capabilities:
    1) parsing of these parameters in the right order of precedence (including built-in defaults, if supplied)
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

=cut

package Bio::EnsEMBL::Hive::ProcessWithParams;

use strict;
use base ('Bio::EnsEMBL::Hive::Process');

sub strict_hash_format {    # This public virtual must be redefined to "return 0;" in all inheriting classes
                            # that want more flexibility for the format of parameters() or input_id()
    return 1;
}

sub param_init {    # normally will run automatically on the first execution of $self->param(),
                    # but you can enforce it by running manually, optionally supplying the default values
                    
    my $self     = shift @_;

    if( !$self->{'_param_hash'} or scalar(@_) ) {

        my $defaults_hash    = scalar(@_) ? { @_ } : {};            # module-wide built-in defaults have the lowest precedence (will always be the same for this module)

        my $meta_params_hash = $self->_parse_meta();                # then come the pipeline-wide parameters from the 'meta' table (define things common to all modules in this pipeline)

        my $parameters_hash  = $self->_parse_string('parameters');  # analysis-wide 'parameters' are even more specific (can be defined differently for several occurence of the same module)

        my $input_id_hash    = $self->_parse_string('input_id');    # job-specific 'input_id' parameters have the highest precedence

        $self->{'_param_hash'} = { %$defaults_hash, %$meta_params_hash, %$parameters_hash, %$input_id_hash };
    }
}

sub param {
    my $self = shift @_;

    $self->param_init(); # normally will only run on the first execution

    my $param_name = shift @_;
    if(@_) { # If there is a value (even if undef), then set it!
        $self->{'_param_hash'}{$param_name} = shift @_;
    }

    return $self->{'_param_hash'}{$param_name};
}

sub param_substitute {
    my ($self, $string) = @_;

    $string=~s/(?:#(\w+?)#)/$self->param($1)/eg;

    return $string;
}

#--------------------------------------------[private methods]----------------------------------------------

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

    # Unfortunately, MetaContainer is useless for us, as we need to load all the parameters in one go
    #
sub _parse_meta {
    my $self = shift @_;

    my %meta_params_hash = ();

        # Here we are assuming that meta_keys are unique.
        # If they are not, you'll be getting the value with the highest meta_id.
        #
    my $sth = $self->db->dbc()->prepare("SELECT meta_key, meta_value FROM meta ORDER BY meta_id");
    $sth->execute();
    while (my ($meta_key, $meta_value)=$sth->fetchrow_array()) {
        $meta_params_hash{$meta_key} = $meta_value;
    }
    $sth->finish();

    return \%meta_params_hash;
}

1;
