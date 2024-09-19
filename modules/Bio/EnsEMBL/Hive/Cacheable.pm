=head1 LICENSE

See the NOTICE file distributed with this work for additional information
regarding copyright ownership.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

=pod

=head1 NAME

Bio::EnsEMBL::Hive::Cacheable - base class to cache collections

=cut

package Bio::EnsEMBL::Hive::Cacheable;

use strict;
use warnings;

use Scalar::Util qw(weaken);
use Bio::EnsEMBL::Hive::Utils::URL ('hash_to_url');


sub hive_pipeline {
    my $self = shift @_;
    if (@_) {
        $self->{'_hive_pipeline'} = shift @_;
        weaken($self->{'_hive_pipeline'});
    }
    return $self->{'_hive_pipeline'};
}


sub is_local_to {
    my $self            = shift @_;
    my $rel_pipeline    = shift @_;

    return $self->hive_pipeline == $rel_pipeline;
}


sub count_local_and_remote_objects {
    my $self            = shift @_;
    my $objects         = shift @_;

    my $this_pipeline   = $self->hive_pipeline;
    my $local_count     = 0;
    my $remote_count    = 0;

    foreach my $object (@$objects) {
        if($object->hive_pipeline == $this_pipeline) {
            $local_count++;
        } else {
            $remote_count++;
        }
    }

    return ($local_count, $remote_count);
}


sub relative_display_name {
    my ($self, $ref_pipeline) = @_;  # if 'reference' hive_pipeline is the same as 'my' hive_pipeline, a shorter display_name is generated

    my $my_pipeline = $self->hive_pipeline;
    my $my_dba      = $my_pipeline && $my_pipeline->hive_dba;

    if ($my_dba and !$self->is_local_to($ref_pipeline)) {
        if (($my_dba->dbc->driver eq 'sqlite') and ($my_dba->dbc->dbname =~ /([^\/]*)$/)) {
            return $1 . '/' . $self->display_name;
        } else {
            return $my_dba->dbc->dbname . '/' . $self->display_name;
        }
    } else {
        return $self->display_name;
    }
}


sub relative_url {
     my ($self, $ref_pipeline) = @_;  # if 'reference' hive_pipeline is the same as 'my' hive_pipeline, a shorter url is generated

    my $my_pipeline = $self->hive_pipeline;
    my $my_dba      = $my_pipeline && $my_pipeline->hive_dba;
    my $url_hash    = ($my_dba and !$self->is_local_to($ref_pipeline) ) ? $my_dba->dbc->to_url_hash : {};

    $url_hash->{'query_params'} = $self->url_query_params;      # calling a specific method for each class that supports URLs

    my $object_type = ref($self);
    $object_type=~s/^.+:://;
    $url_hash->{'query_params'}{'object_type'} = $object_type;

    return Bio::EnsEMBL::Hive::Utils::URL::hash_to_url( $url_hash );
}


sub display_name {
    my ($self) = @_;
    return "$self";     # Default implementation
}


sub unikey {    # to be redefined by individual Cacheable classes
    return undef;
}


1;
