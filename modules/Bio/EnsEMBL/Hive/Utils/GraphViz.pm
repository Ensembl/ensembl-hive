
# an extension of GraphViz that supports nested clusters

package Bio::EnsEMBL::Hive::Utils::GraphViz;

use strict;
use warnings;
use base ('GraphViz');

#my ($colorscheme, $coloroffset) = ('ylorbr9', 1);
#my ($colorscheme, $coloroffset) = ('purples7', 1);
#my ($colorscheme, $coloroffset) = ('orrd8', 1);
#my ($colorscheme, $coloroffset) = ('bugn7', 0);
my ($colorscheme, $coloroffset) = ('blues9', 1);


sub subgraphs {
    my $self = shift @_;
    if(@_) {
        $self->{_subgraphs} = shift @_;
    }
    return $self->{_subgraphs};
}


sub get_top_clusters {
    my $self = shift @_;

    my $subgraphs = $self->subgraphs();

    my %set = ();
    foreach my $top_cluster (values %$subgraphs) {
        if( $top_cluster and !$subgraphs->{ $top_cluster } ) {  # if it's a valid node not mentioned in the keys, it is a top cluster
            $set{$top_cluster}++;
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


sub generate_subgraph {
    my ($self, $cluster_name, $depth) = @_;

    my $subgraphs = $self->subgraphs();

    my $prefix = "\t" x $depth;

    my $text = '';

    $text .= $prefix . "subgraph cluster_${cluster_name} {\n";
#    $text .= $prefix . "\tlabel=\"$cluster_name\";\n";
    $text .= $prefix . "\tcolorscheme=$colorscheme;\n";
    $text .= $prefix . "\tstyle=filled;\n";
    $text .= $prefix . "\tcolor=".($depth+$coloroffset).";\n";

    foreach my $node_name ( @{ $self->get_nodes_that_point_at( $cluster_name ) } ) {

        $text .= $prefix . "\t${node_name};\n";
        if( @{ $self->get_nodes_that_point_at( $node_name ) } ) {
            $text .= $self->generate_subgraph( $node_name, $depth+1 );
        }
    }
    $text .= $prefix . "}\n";

    return $text;
}


sub _as_debug {
    my $self = shift @_;

    my $text = $self->SUPER::_as_debug;

    my $subgraphs = $self->subgraphs();

    $text=~s/^}$//m;

    foreach my $node_name ( @{ $self->get_top_clusters() } ) {
        $text .= $self->generate_subgraph( $node_name, 1);
    }
    $text .= "}\n";

#    print $text;

    return $text;
}

1;

