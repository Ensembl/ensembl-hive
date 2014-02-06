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

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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

1;

