=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::GraphViz

=head1 DESCRIPTION

    An extension of GraphViz that supports nested clusters

=head1 EXTERNAL DEPENDENCIES

    GraphViz

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


package Bio::EnsEMBL::Hive::Utils::GraphViz;

use strict;
use warnings;
use base ('GraphViz');


sub cluster_2_nodes {
    my $self = shift @_;
    if(@_) {
        $self->{_cluster_2_nodes} = shift @_;
    }
    return $self->{_cluster_2_nodes};
}


sub main_pipeline_name {
    my $self = shift @_;
    if(@_) {
        $self->{_main_pipeline_name} = shift @_;
    }
    return $self->{_main_pipeline_name};
}


sub semaphore_bgcolour {
    my $self = shift @_;
    if(@_) {
        $self->{_semaphore_bgcolour} = shift @_;
    }
    return $self->{_semaphore_bgcolour};
}


sub main_pipeline_bgcolour {
    my $self = shift @_;
    if(@_) {
        $self->{_main_pipeline_bgcolour} = shift @_;
    }
    return $self->{_main_pipeline_bgcolour};
}


sub other_pipeline_bgcolour {
    my $self = shift @_;
    if(@_) {
        $self->{_other_pipeline_bgcolour} = shift @_;
    }
    return $self->{_other_pipeline_bgcolour};
}


sub display_subgraph {
    my ($self, $cluster_name, $depth) = @_;

    my $box_colour_pair  = $depth
        ? $self->semaphore_bgcolour
        : ( $cluster_name eq $self->main_pipeline_name)
            ? $self->main_pipeline_bgcolour
            : $self->other_pipeline_bgcolour;
    my ($colour_scheme, $colour_offset) = $box_colour_pair && @$box_colour_pair;

    my $prefix = "\t" x $depth;
    my  $text = '';
        $text .= $prefix . "subgraph cluster_${cluster_name} {\n";

        # uncomment the following line to see the cluster names:
#     $text .= $prefix . "\tlabel=\"$cluster_name\";\n";

    if($colour_scheme) {
        $text .= $prefix . "\tstyle=filled;\n";

        if(defined($colour_offset)) {
            $text .= $prefix . "\tcolorscheme=$colour_scheme;\n";
            $text .= $prefix . "\tcolor=".($depth+$colour_offset).";\n";
        } else {    # it's just a simple colour:
            $text .= $prefix . "\tcolor=${colour_scheme};\n";
        }
    } # otherwise just draw a black frame around the subgraph

    foreach my $node_name ( @{ $self->cluster_2_nodes->{ $cluster_name } || [] } ) {

        $text .= $prefix . "\t${node_name};\n";
        if( @{ $self->cluster_2_nodes->{ $node_name } || [] } ) {
            $text .= $self->display_subgraph( $node_name, $depth+1 );
        }
    }
    $text .= $prefix . "}\n";

    return $text;
}


sub _as_debug {
    my $self = shift @_;

    my $text = $self->SUPER::_as_debug;

    $text=~s/^}$//m;

    foreach my $node_name ( grep { !/^dfr_/ } keys %{ $self->cluster_2_nodes } ) {
        $text .= $self->display_subgraph( $node_name, 0);
    }
    $text .= "}\n";

        # GraphViz.pm thinks 'record' is the only shape that allows HTML-like labels,
        # but newer versions of dot allow more freedom, so we patch dot input after generation:
        #
    $text=~s/^(\s+table_.*)"record"/$1"tab"/mg;
    $text=~s/^(\s+analysis_.*)"record"/$1"Mrecord"/mg;

        # uncomment the following line to see the final input to dot
#    print $text;

    return $text;
}

1;

