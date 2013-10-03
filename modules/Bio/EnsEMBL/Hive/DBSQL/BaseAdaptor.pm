=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::BaseAdaptor

=head1 DESCRIPTION

    The base class for all other Object- or NakedTable- adaptors.
    Performs the low-level SQL needed to retrieve and store data in tables.

=head1 EXTERNAL DEPENDENCIES

    DBI 1.6

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

=cut


package Bio::EnsEMBL::Hive::DBSQL::BaseAdaptor;

use strict;
no strict 'refs';   # needed to allow AUTOLOAD create new methods
use DBI 1.6;        # the 1.6 functionality is important for detecting autoincrement fields and other magic.

use base ('Bio::EnsEMBL::DBSQL::BaseAdaptor');


sub default_table_name {
    die "Please define table_name either by setting it via table_name() method or by redefining default_table_name() in your adaptor class";
}


sub default_insertion_method {
    return 'INSERT_IGNORE';
}


sub table_name {
    my $self = shift @_;

    if(@_) {    # setter
        $self->{_table_name} = shift @_;
        $self->_table_info_loader();
    }
    return $self->{_table_name} || $self->default_table_name();
}


sub insertion_method {
    my $self = shift @_;

    if(@_) {    # setter
        $self->{_insertion_method} = shift @_;
    }
    return $self->{_insertion_method} || $self->default_insertion_method();
}


sub column_set {
    my $self = shift @_;

    if(@_) {    # setter
        $self->{_column_set} = shift @_;
    } elsif( !defined( $self->{_column_set} ) ) {
        $self->_table_info_loader();
    }
    return $self->{_column_set};
}


sub primary_key {        # not necessarily auto-incrementing
    my $self = shift @_;

    if(@_) {    # setter
        $self->{_primary_key} = shift @_;
    } elsif( !defined( $self->{_primary_key} ) ) {
        $self->_table_info_loader();
    }
    return $self->{_primary_key};
}


sub updatable_column_list {    # it's just a cashed view, you cannot set it directly
    my $self = shift @_;

    unless($self->{_updatable_column_list}) {
        my %primary_key_set = map { $_ => 1 } @{$self->primary_key()};
        my $column_set      = $self->column_set();
        $self->{_updatable_column_list} = [ grep { not $primary_key_set{$_} } keys %$column_set ];
    }
    return $self->{_updatable_column_list};
}


sub autoinc_id {
    my $self = shift @_;

    if(@_) {    # setter
        $self->{_autoinc_id} = shift @_;
    } elsif( !defined( $self->{_autoinc_id} ) ) {
        $self->_table_info_loader();
    }
    return $self->{_autoinc_id};
}


sub _table_info_loader {
    my $self = shift @_;

    my $dbc         = $self->dbc();
    my $dbh         = $dbc->db_handle();
    my $driver      = $dbc->driver();
    my $dbname      = $dbc->dbname();
    my $table_name  = $self->table_name();

    my %column_set  = ();
    my %name2type   = ();
    my $autoinc_id  = '';
    my @primary_key = $dbh->primary_key(undef, undef, $table_name);

    my $sth = $dbh->column_info(undef, undef, $table_name, '%');
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        my ($position, $name, $type, $is_ai) = @$row{'ORDINAL_POSITION','COLUMN_NAME', 'TYPE_NAME', 'mysql_is_auto_increment'};

        $column_set{$name}  = 1;
        $name2type{$name}   = $type;
        if($is_ai) {
            $autoinc_id = $name;
        }
    }
    $sth->finish;

    if( ($driver ne 'mysql')
     and scalar(@primary_key)==1 and (uc($name2type{$primary_key[0]}) eq 'INTEGER') ) {
        $autoinc_id = $primary_key[0];
    }

    $self->column_set(  \%column_set );
    $self->primary_key( \@primary_key );
    $self->autoinc_id(   $autoinc_id );
}


sub count_all {
    my ($self, $constraint) = @_;

    my $table_name      = $self->table_name();

    my $sql = "SELECT COUNT(*) FROM $table_name";

    if($constraint) {
            # in case $constraint contains any kind of JOIN (regular, LEFT, RIGHT, etc) do not put WHERE in front:
        $sql .= (($constraint=~/\bJOIN\b/i) ? ' ' : ' WHERE ') . $constraint;
    }

    # warn "SQL: $sql\n";

    my $sth = $self->prepare($sql);
    $sth->execute;  
    my ($count) = $sth->fetchrow_array();
    $sth->finish;  

    return $count;
}


sub fetch_all {
    my ($self, $constraint, $one_per_key, $key_list, $value_column) = @_;
    
    my $table_name      = $self->table_name();

    my $sql = 'SELECT ' . join(', ', keys %{$self->column_set()}) . " FROM $table_name";

    if($constraint) { 
            # in case $constraint contains any kind of JOIN (regular, LEFT, RIGHT, etc) do not put WHERE in front:
        if($constraint=~/\bJOIN\b/i) {
            $sql = 'SELECT ' . join(', ', map { "$table_name.$_" } keys %{$self->column_set()}) . " FROM $table_name $constraint";
        } elsif($constraint=~/^LIMIT|ORDER|GROUP/) {
            $sql .= ' '.$constraint;
        } else {
            $sql .= ' WHERE '.$constraint;
        }
    }

    # warn "SQL: $sql\n";

    my $sth = $self->prepare($sql);
    $sth->execute;  

    my $result_struct;  # will be autovivified to the correct data structure

    while(my $hashref = $sth->fetchrow_hashref) {
        my $pptr = \$result_struct;
        if($key_list) {
            foreach my $syll (@$key_list) {
                $pptr = \$$pptr->{$hashref->{$syll}};   # using pointer-to-pointer to enforce same-level vivification
            }
        }
        my $object = $value_column
            ? $hashref->{$value_column}
            : $self->objectify($hashref);
        if($one_per_key) {
            $$pptr = $object;
        } else {
            push @$$pptr, $object;
        }
    }
    $sth->finish;  

    unless(defined($result_struct)) {
        if($key_list and scalar(@$key_list)) {
            $result_struct = {};
        } elsif(!$one_per_key) {
            $result_struct = [];
        }
    }

    return $result_struct;  # either listref or hashref is returned, depending on the call parameters
}


sub primary_key_constraint {
    my $self        = shift @_;
    my $sliceref    = shift @_;

    my $primary_key  = $self->primary_key();  # Attention: the order of primary_key columns of your call should match the order in the table definition!

    if(@$primary_key) {
        return join (' AND ', map { $primary_key->[$_]."='".$sliceref->[$_]."'" } (0..scalar(@$primary_key)-1));
    } else {
        my $table_name = $self->table_name();
        die "Table '$table_name' doesn't have a primary_key";
    }
}


sub fetch_by_dbID {
    my $self = shift @_;    # the rest in @_ should be primary_key column values

    return $self->fetch_all( $self->primary_key_constraint( \@_ ), 1 );
}


sub remove_all {    # remove entries by a constraint
    my $self        = shift @_;
    my $constraint  = shift @_ || 1;

    my $table_name  = $self->table_name();

    my $sql = "DELETE FROM $table_name WHERE $constraint";
    my $sth = $self->prepare($sql);
    $sth->execute();
    $sth->finish();
}


sub remove {    # remove the object by primary_key
    my $self        = shift @_;
    my $object      = shift @_;

    my $primary_key_constraint  = $self->primary_key_constraint( $self->slicer($object, $self->primary_key()) );

    return $self->remove_all( $primary_key_constraint );
}


sub update {    # update (some or all) non_primary columns from the primary
    my $self    = shift @_;
    my $object  = shift @_;    # the rest in @_ should be the column names to be updated

    my $table_name              = $self->table_name();
    my $primary_key_constraint  = $self->primary_key_constraint( $self->slicer($object, $self->primary_key()) );
    my $columns_to_update       = scalar(@_) ? \@_ : $self->updatable_column_list();
    my $values_to_update        = $self->slicer( $object, $columns_to_update );

    unless(@$columns_to_update) {
        die "There are no dependent columns to update, as everything seems to belong to the primary key";
    }

    my $sql = "UPDATE $table_name SET ".join(', ', map { "$_=?" } @$columns_to_update)." WHERE $primary_key_constraint";
    # print "SQL: $sql\n";
    my $sth = $self->prepare($sql);
    # print "VALUES_TO_UPDATE: ".join(', ', map { "'$_'" } @$values_to_update)."\n";
    $sth->execute( @$values_to_update);

    $sth->finish();
}


sub check_object_present_in_db {    # return autoinc_id/undef if the table has autoinc_id or just 1/undef if not
    my ( $self, $object ) = @_;

    my $table_name  = $self->table_name();
    my $column_set  = $self->column_set();
    my $autoinc_id  = $self->autoinc_id();

    my $non_autoinc_columns = [ grep { $_ ne $autoinc_id } keys %$column_set ];
    my $non_autoinc_values  = $self->slicer( $object, $non_autoinc_columns );

    my $sql = 'SELECT '.($autoinc_id or 1)." FROM $table_name WHERE ".
            # we look for identical contents, so must skip the autoinc_id columns when fetching:
        join(' AND ', map { my $v=$non_autoinc_values->[$_]; "$non_autoinc_columns->[$_] ".(defined($v) ? "='$v'" : 'IS NULL') } (0..@$non_autoinc_columns-1) );

    my $sth = $self->prepare($sql);
    $sth->execute();

    my ($return_value) = $sth->fetchrow_array();
    $sth->finish;

    return $return_value;
}


sub store {
    my ($self, $object_or_list, $check_presence_in_db_first) = @_;

    my $objects = (ref($object_or_list) eq 'ARRAY')     # ensure we get an array of objects to store
        ? $object_or_list
        : [ $object_or_list ];
    return unless(scalar(@$objects));

    my $table_name              = $self->table_name();
    my $autoinc_id              = $self->autoinc_id();
    my $all_storable_columns    = [ grep { $_ ne $autoinc_id } keys %{ $self->column_set() } ];
    my $driver                  = $self->dbc->driver();
    my $insertion_method        = $self->insertion_method;  # INSERT, INSERT_IGNORE or REPLACE
    $insertion_method           =~ s/_/ /g;
    if($driver eq 'sqlite') {
        $insertion_method =~ s/INSERT IGNORE/INSERT OR IGNORE/ig;
    } elsif($driver eq 'pgsql') {   # FIXME! temporary hack
        $insertion_method = 'INSERT';
    }

    my %hashed_sth = ();  # do not prepare statements until there is a real need

    my $stored_this_time        = 0;

    foreach my $object (@$objects) {
        if($check_presence_in_db_first and my $present = $self->check_object_present_in_db($object)) {
            $self->mark_stored($object, $present);
        } else {
            my ($columns_being_stored, $column_key) = (ref($object) eq 'HASH') ? $self->keys_to_columns($object) : ($all_storable_columns, '*all*');
            # print "COLUMN_KEY='$column_key'\n";

            my $this_sth;

                # only prepare (once!) if we get here:
            unless($this_sth = $hashed_sth{$column_key}) {
                    # By using question marks we can insert true NULLs by setting corresponding values to undefs:
                my $sql = "$insertion_method INTO $table_name (".join(', ', @$columns_being_stored).') VALUES ('.join(',', (('?') x scalar(@$columns_being_stored))).')';
                # print "STORE: $sql\n";
                $this_sth = $hashed_sth{$column_key} = $self->prepare( $sql ) or die "Could not prepare statement: $sql";
            }

            # print "STORED_COLUMNS: ".join(', ', map { "`$_`" } @$columns_being_stored)."\n";
            my $values_being_stored = $self->slicer( $object, $columns_being_stored );
            # print "STORED_VALUES: ".join(', ', map { "'$_'" } @$values_being_stored)."\n";

            my $return_code = $this_sth->execute( @$values_being_stored )
                    # using $return_code in boolean context allows to skip the value '0E0' ('no rows affected') that Perl treats as zero but regards as true:
                or die "Could not store fields\n\t{$column_key}\nwith data:\n\t(".join(',', @$values_being_stored).')';
            if($return_code > 0) {     # <--- for the same reason we have to be explicitly numeric here
                my $liid = $autoinc_id && $self->dbc->db_handle->last_insert_id(undef, undef, $table_name, $autoinc_id);
                $self->mark_stored($object, $liid );
                ++$stored_this_time;
            }
        }
    }

    foreach my $sth (values %hashed_sth) {
        $sth->finish();
    }

    return ($object_or_list, $stored_this_time);
}


sub DESTROY { }   # to simplify AUTOLOAD

sub AUTOLOAD {
    our $AUTOLOAD;

    if($AUTOLOAD =~ /::fetch(_all)?(?:_by_(\w+?))?(?:_HASHED_FROM_(\w+?))?(?:_TO_(\w+?))?$/) {
        my $all             = $1;
        my $filter_string   = $2;
        my $key_string      = $3;
        my $value_column    = $4;

        my ($self) = @_;
        my $column_set = $self->column_set();

        my $filter_components = $filter_string && [ split(/_AND_/i, $filter_string) ];
        foreach my $column_name ( @$filter_components ) {
            unless($column_set->{$column_name}) {
                die "unknown column '$column_name'";
            }
        }
        my $key_components = $key_string && [ split(/_AND_/i, $key_string) ];
        foreach my $column_name ( @$key_components ) {
            unless($column_set->{$column_name}) {
                die "unknown column '$column_name'";
            }
        }
        if($value_column && !$column_set->{$value_column}) {
            die "unknown column '$value_column'";
        }

#        print "Setting up '$AUTOLOAD' method\n";
        *$AUTOLOAD = sub {
            my $self = shift @_;
            return $self->fetch_all(
                join(' AND ', map { "$filter_components->[$_]='$_[$_]'" } 0..scalar(@$filter_components)-1),
                !$all,
                $key_components,
                $value_column
            );
        };
        goto &$AUTOLOAD;    # restart the new method

    } elsif($AUTOLOAD =~ /::count_all_by_(\w+)$/) {
        my $filter_string = $1;

        my ($self) = @_;
        my $column_set = $self->column_set();

        my $filter_components = $filter_string && [ split(/_AND_/i, $filter_string) ];
        foreach my $column_name ( @$filter_components ) {
            unless($column_set->{$column_name}) {
                die "unknown column '$column_name'";
            }
        }

#        print "Setting up '$AUTOLOAD' method\n";
        *$AUTOLOAD = sub {
            my $self = shift @_;
            return $self->count_all(
                join(' AND ', map { "$filter_components->[$_]='$_[$_]'" } 0..scalar(@$filter_components)-1),
            );
        };
        goto &$AUTOLOAD;    # restart the new method

    } elsif($AUTOLOAD =~ /::remove_all_by_(\w+)$/) {
        my $filter_name = $1;

        my ($self) = @_;
        my $column_set = $self->column_set();

        if($column_set->{$filter_name}) {
#            print "Setting up '$AUTOLOAD' method\n";
            *$AUTOLOAD = sub { my ($self, $filter_value) = @_; return $self->remove_all("$filter_name='$filter_value'"); };
            goto &$AUTOLOAD;    # restart the new method
        } else {
            die "unknown column '$filter_name'";
        }
    } elsif($AUTOLOAD =~ /::update_(\w+)$/) {
        my @columns_to_update = split(/_AND_/i, $1);
#        print "Setting up '$AUTOLOAD' method\n";
        *$AUTOLOAD = sub { my ($self, $object) = @_; return $self->update($object, @columns_to_update); };
        goto &$AUTOLOAD;    # restart the new method
    } else {
        print "sub '$AUTOLOAD' not implemented";
    }
}

1;

