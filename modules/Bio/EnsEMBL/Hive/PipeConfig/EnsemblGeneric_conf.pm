=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::PipeConfig::EnsemblGeneric_conf

=head1 DESCRIPTION

    Generic configuration module for all Ensembl-derived pipelines.
    It extends HiveGeneric_conf with specifically Ensembl things (knows about the release number, for instance).

    So if your pipeline has anything to do with Ensembl API/schema, please inherit (directly or not) your config from this file.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::PipeConfig::EnsemblGeneric_conf;

use strict;
use warnings;

use Bio::EnsEMBL::ApiVersion ();

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');


=head2 default_options

    Description : Interface method that should return a hash of option_name->default_option_value pairs.
                  Please see existing PipeConfig modules for examples.

=cut

sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },   # inherit from parent

            # Please note: ENVironment variables may be "exported" to inherit from enclosing shell,
            # but if you want to *prevent* that you need to specifically say so
            #  (setting a password to empty string does exactly that - sets it to an empty string)
            #
            #   [bash]      export -n ENSEMBL_CVS_ROOT_DIR  # will stop exporting, but the value in current shell stays as it was
            #   [tcsh]      unsetenv ENSEMBL_CVS_ROOT_DIR   # will destroy the variable even in current shell, and stop exporting

        'ensembl_cvs_root_dir'  => $ENV{'ENSEMBL_CVS_ROOT_DIR'} || $self->o('ensembl_cvs_root_dir'),    # it will make sense to set this variable if you are going to use ehive with ensembl

        'ensembl_release'       => Bio::EnsEMBL::ApiVersion::software_version(),                        # snapshot of EnsEMBL Core API version. Please do not change if not sure.
        'rel_suffix'            => '',                                                                  # an empty string by default, a letter otherwise
        'rel_with_suffix'       => $self->o('ensembl_release').$self->o('rel_suffix'),

        'pipeline_name'         => $self->pipeline_name().'_'.$self->o('rel_with_suffix'),

        'user'                  => $ENV{'EHIVE_USER'} || 'ensadmin',
        'password'              => $ENV{'EHIVE_PASS'} // $ENV{'ENSADMIN_PSW'} // $self->o('password'),  # people will have to make an effort NOT to insert it into config files like .bashrc etc
    };
}


=head2 pipeline_wide_parameters

    Description : Interface method that should return a hash of pipeline_wide_parameter_name->pipeline_wide_parameter_value pairs.
                  The value doesn't have to be a scalar, can be any Perl structure now (will be stringified and de-stringified automagically).
                  Please see existing PipeConfig modules for examples.

=cut

sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },      # inherit from parent

#        'schema_version' => $self->o('ensembl_release'),   # commented out to avoid duplicating 'schema_version' inserted by the schema mysql file
    };
}

1;

