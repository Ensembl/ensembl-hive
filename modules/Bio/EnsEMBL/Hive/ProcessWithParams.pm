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

sub param_init {    # normally will run automatically on the first execution of $self->param(),
                    # but you can enforce it by running manually, optionally supplying the default values
                    
    my $self     = shift @_;

    if( !$self->{'_param_hash'} or scalar(@_) ) {

        my $defaults = scalar(@_) ? { @_ } : {};    # built-in defaults have the lowest precedence

        my $parameters = eval($self->parameters()) || {};
        if($@) {
            die "The module '".ref($self)."' for analysis '".$self->analysis->logic_name()
                ."' assumes analysis.parameters should evaluate into a {'param'=>'value'} hashref."
                ." The current value is '".$self->parameters()."'\n";
        }

        my $input_id   = eval($self->input_id()) || {};
        if($@) {
            die "The module '".ref($self)."' for analysis '".$self->analysis->logic_name()
                ."' assumes analysis_job.input_id should evaluate into a {'param'=>'value'} hashref."
                ." The current value is '".$self->input_id()."'\n";
        }

        $self->{'_param_hash'} = { %$defaults, %$parameters, %$input_id };
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

1;
