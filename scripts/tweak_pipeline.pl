#!/usr/bin/env perl

use strict;
use warnings;
use JSON qw(encode_json);

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}

use Getopt::Long qw(:config pass_through no_auto_abbrev);
use Pod::Usage;

use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module');
use Bio::EnsEMBL::Hive::Utils::URL;

Bio::EnsEMBL::Hive::Utils::URL::hide_url_password();

main();


sub main {

    my $self    = {};
    my $tweaks  = [];

    GetOptions(
            # connection parameters
        'url=s'                 => \$self->{'url'},
        'reg_conf|reg_file=s'   => \$self->{'reg_conf'},
        'reg_type=s'            => \$self->{'reg_type'},
        'reg_alias|reg_name=s'  => \$self->{'reg_alias'},
        'nosqlvc'             => \$self->{'nosqlvc'},     # using "nosqlvc" instead of "sqlvc!" for consistency with scripts where it is a propagated option
        'json'                  => \$self->{'json'},
        'tweak|SET=s@'          => \$tweaks,
        'DELETE=s'              => sub { my ($opt_name, $opt_value) = @_; push @$tweaks, $opt_value.'#'; },
        'SHOW=s'                => sub { my ($opt_name, $opt_value) = @_; push @$tweaks, $opt_value.'?'; },

        'h|help'                => \$self->{'help'},
    ) or die "\nERROR: in command line arguments\n";

    if (@ARGV) {
        die "\nERROR: There are invalid arguments on the command-line: ". join(" ", @ARGV). "\n";
    }

    if($self->{'help'}) {
        pod2usage({-exitvalue => 0, -verbose => 2});
    }

    my $pipeline;

    if($self->{'url'} or $self->{'reg_alias'}) {
        $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
            -url                            => $self->{'url'},
            -reg_conf                       => $self->{'reg_conf'},
            -reg_type                       => $self->{'reg_type'},
            -reg_alias                      => $self->{'reg_alias'},
            -no_sql_schema_version_check    => $self->{'nosqlvc'},
        );

    } else {
        die "\nERROR: Connection parameters (url or reg_conf+reg_alias) need to be specified\n";
    }
    if(@$tweaks) {
        my ($need_write, $listRef, $responceStructure) = $pipeline->apply_tweaks( $tweaks );

        $responceStructure->{URL} = $self->{'url'};
        my $json = JSON->new->allow_nonref;

        print $self->{'json'} ? $json->encode($responceStructure) : join('', @$listRef);
        if ($need_write) {
            $pipeline->hive_dba()->dbc->requires_write_access();
            $pipeline->save_collections();
        }
    }

}


__DATA__

=pod

=head1 NAME

tweak_pipeline.pl

=head1 SYNOPSIS

    tweak_pipeline.pl [ -url mysql://user:pass@server:port/dbname | -reg_conf <reg_conf_file> -reg_alias <reg_alias> ] -tweak 'analysis[mafft%].analysis_capacity=undef'

=head1 DESCRIPTION

This is a script to "tweak" attributes or parameters of an existing eHive pipeline.

=head1 OPTIONS

=over

=item --url <url>

URL defining where eHive database is located

=item --reg_conf <path>

path to a Registry configuration file

=item --reg_type <name>

Registry type of the eHive DBAdaptor

=item --reg_alias <name>

species/alias name for the eHive DBAdaptor

=item --nosqlvc

"No SQL Version Check" - set if you want to force working with a database created by a potentially schema-incompatible API

=item --tweak <string>

An assignment command that performs one individual "tweak". You can "tweak" global/Analysis parameters, Analysis attributes and Resource Classes:

    -tweak 'pipeline.param[take_time]=20'                   # override a value of a pipeline-wide parameter; can also create a non-existent parameter
    -tweak 'analysis[take_b_apart].param[base]=10'          # override a value of an Analysis-wide parameter; can also create a non-existent parameter
    -tweak 'analysis[add_together].analysis_capacity=undef' # override a value of an Analysis attribute
    -tweak 'analysis[add_together].batch_size=15'           # override a value of an Analysis_stats attribute
    -tweak 'analysis[part_multiply].resource_class=urgent'  # set the Resource Class of an Analysis (whether a Resource Class with this name existed or not)
    -tweak 'resource_class[urgent].LSF=-q yesteryear'       # update or create a new Resource Description

If multiple "tweaks" are requested, they will be performed in the given order.

=item --DELETE <selector>

Shortcut to delete a parameter

=item --SHOW <selector>

Shortcut to show a parameter value

=back

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2019] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

Please subscribe to the eHive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss eHive-related questions or to be notified of our updates

=cut
