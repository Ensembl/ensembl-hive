
# an extension of GraphViz that supports nested clusters

package Bio::EnsEMBL::Hive::Utils::GraphViz;

use strict;
use warnings;
use base ('GraphViz');


sub subgraphs {
    my $self = shift @_;
    if(@_) {
        $self->{_subgraphs} = shift @_;
    }
    return $self->{_subgraphs};
}


sub colour_scheme {
    my $self = shift @_;
    if(@_) {
        $self->{_colour_scheme} = shift @_;
    }
    return $self->{_colour_scheme};
}


sub colour_offset {
    my $self = shift @_;
    if(@_) {
        $self->{_colour_offset} = shift @_;
    }
    return $self->{_colour_offset};
}


sub get_top_clusters {
    my $self = shift @_;

    my $subgraphs = $self->subgraphs();

    my %set = ();
    foreach my $potential_top_cluster (values %$subgraphs) {
        if( $potential_top_cluster and !$subgraphs->{ $potential_top_cluster } ) {  # if it's a valid node not mentioned in the keys, it is a top cluster
            $set{$potential_top_cluster}++;
        }
    }
    return [ keys %set ];
}


sub get_nodes_that_point_at {
    my ($self, $node) = @_;

    my $subgraphs = $self->subgraphs();
    my %set = ();
    while( my ($key,$value) = each %$subgraphs) {
        if($value and ($value eq $node)) {
            $set{$key}++;
        }
    }
    return [ keys %set ];
}


sub display_subgraph {
    my ($self, $cluster_name, $depth) = @_;

    my $colour_scheme   = $self->colour_scheme();
    my $colour_offset   = $self->colour_offset();

    my $prefix = "\t" x $depth;

    my $text = '';

    $text .= $prefix . "subgraph cluster_${cluster_name} {\n";
#     $text .= $prefix . "\tlabel=\"$cluster_name\";\n";
    $text .= $prefix . "\tcolorscheme=$colour_scheme;\n";
    $text .= $prefix . "\tstyle=filled;\n";
    $text .= $prefix . "\tcolor=".($depth+$colour_offset).";\n";

    foreach my $node_name ( @{ $self->get_nodes_that_point_at( $cluster_name ) } ) {

        $text .= $prefix . "\t${node_name};\n";
        if( @{ $self->get_nodes_that_point_at( $node_name ) } ) {
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

    foreach my $node_name ( @{ $self->get_top_clusters() } ) {
        $text .= $self->display_subgraph( $node_name, 1);
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

