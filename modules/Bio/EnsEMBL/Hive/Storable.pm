=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Storable

=head1 SYNOPSIS

    my $dbID    = $storable_object->dbID();
    my $adaptor = $storable_object->adaptor();

=head1 DESCRIPTION

    Storable is a base class for anything that can be stored.
    It provides two getters/setters: dbID() and adaptor().

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

    The rest of the documentation details each of the object methods.
    Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::Storable;

use strict;
use warnings;

use Scalar::Util qw(weaken);
use Bio::EnsEMBL::Hive::Utils ('throw');
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;


=head2 new

    Args            : pairs of ($method_name, $value)
    Caller          : ObjectAdaptor, AnalysisJob, URLFactory.pm, HiveGeneric_conf, seed_pipeline.pl, standaloneJob.pl
    Description     : create a new Storable object 
    Returntype      : Bio::EnsEMBL::Hive::Storable
    Status          : stable

=cut

sub new {
    my $class = shift @_;

    my $self = bless {}, $class;

    while(my ($method,$value) = splice(@_,0,2)) {
        if(defined($value)) {
            $self->$method($value);
        }
    }

    return $self;
}


=head2 dbID

    Arg [1]         : int $dbID
    Description     : getter/setter for the database internal id
    Returntype      : int
    Caller          : general, set from adaptor on store
    Status          : stable

=cut

sub dbID {
    my $self = shift;
    $self->{'dbID'} = shift if(@_);
    return $self->{'dbID'};
}


=head2 adaptor

    Arg [1]         : Bio::EnsEMBL::Hive::DBSQL::BaseAdaptor $adaptor
    Description     : getter/setter for this objects Adaptor
    Returntype      : Bio::EnsEMBL::Hive::DBSQL::BaseAdaptor
    Caller          : general, set from adaptor on store
    Status          : stable

=cut

sub adaptor {
    my $self = shift;

    if(@_) {
        $self->{'adaptor'} = shift;
        weaken( $self->{'adaptor'} ) if defined( $self->{'adaptor'} );
    }

    return $self->{'adaptor'};
}


sub DESTROY { }     # "If you define an AUTOLOAD in your class,
                    # then Perl will call your AUTOLOAD to handle the DESTROY method.
                    # You can prevent this by defining an empty DESTROY (...)" -- perlobj

sub AUTOLOAD {
    our $AUTOLOAD;

#print "Storable::AUTOLOAD : attempting to run '$AUTOLOAD' (".join(', ', @_).")\n";

    my $self = shift @_;

    if($AUTOLOAD =~ /::(\w+)$/) {
        my $name_to_parse = $1;
        my ($AdaptorType, $is_an_id, $foo_id_method_name, $foo_obj_method_name)
            = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->parse_underscored_id_name( $name_to_parse );

        unless($AdaptorType) {
            throw("Storable::AUTOLOAD : could not parse '$name_to_parse'");
        } elsif ($is_an_id) {  # $name_to_parse was something like foo_dataflow_rule_id

            if(@_) {
                $self->{$foo_id_method_name} = shift @_;
                if( $self->{$foo_obj_method_name} ) {
#                    warn "setting $foo_id_method_name in an object that had $foo_obj_method_name defined";
                    $self->{$foo_obj_method_name} = undef;
                }

                # attempt to lazy-load:
            } elsif( !$self->{$foo_id_method_name} and my $foo_object=$self->{$foo_obj_method_name}) {
                $self->{$foo_id_method_name} = $foo_object->dbID;
#                warn "Lazy-loaded dbID (".$self->{$foo_id_method_name}.") from $AdaptorType object\n";
            }

            return $self->{$foo_id_method_name};

        } else {                # $name_to_parse was something like foo_dataflow_rule

            if(@_) {    # setter of the object itself
                $self->{$foo_obj_method_name} = shift @_;

                # attempt to lazy-load:
            } elsif( !$self->{$foo_obj_method_name} and my $foo_object_id = $self->{$foo_id_method_name}) {
                my $foo_class = 'Bio::EnsEMBL::Hive::'.$AdaptorType;
                my $collection = $foo_class->can('collection') && $foo_class->collection();
                if( $collection and $self->{$foo_obj_method_name} = $collection->find_one_by('dbID', $foo_object_id) ) { # careful: $AdaptorType may not be unique (aliases)
#                    warn "Lazy-loading object from $AdaptorType collection\n";
                } elsif(my $adaptor = $self->adaptor) {
#                    warn "Lazy-loading object from $AdaptorType adaptor\n";
                    $self->{$foo_obj_method_name} = $adaptor->db->get_adaptor( $AdaptorType )->fetch_by_dbID( $foo_object_id );
                } else {
#                    warn "Cannot lazy-load $foo_obj_method_name because the ".ref($self)." is not attached to an adaptor";
                }
            }

            return $self->{$foo_obj_method_name};

        }   # choice of autoloadable functions

    }
}

1;

