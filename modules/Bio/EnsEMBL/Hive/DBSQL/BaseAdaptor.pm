package Bio::EnsEMBL::Hive::DBSQL::BaseAdaptor;

use strict;
no strict 'refs';   # needed to allow AUTOLOAD create new methods

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

    if(($driver eq 'sqlite') and scalar(@primary_key)==1 and (uc($name2type{$primary_key[0]}) eq 'INTEGER') ) {
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
        $sql .= " WHERE $constraint ";
    }

    print STDOUT $sql,"\n";

    my $sth = $self->prepare($sql);
    $sth->execute;  
    my ($count) = $sth->fetchrow();
    $sth->finish;  

    return $count;
}


sub fetch_all {
    my ($self, $constraint, $one_per_key, $key_list, $value_column) = @_;
    
    my $table_name      = $self->table_name();
    my $columns_csv     = join(', ', keys %{$self->column_set()});

    my $sql = "SELECT $columns_csv FROM $table_name";

    if($constraint) { 
        $sql .= " WHERE $constraint ";
    }

    # print STDOUT $sql,"\n";

    my $sth = $self->prepare($sql);
    $sth->execute;  

    my $result_struct;  # will be autovivified to the correct data structure

    while(my $hashref = $sth->fetchrow_hashref) {
        my $pptr = \$result_struct;
        foreach my $syll (@$key_list) {
            $pptr = \$$pptr->{$hashref->{$syll}};   # using pointer-to-pointer to enforce same-level vivification
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
        if(scalar(@$key_list)) {
            $result_struct = {};
        } elsif(!$one_per_key) {
            $result_struct = [];
        }
    }

    return $result_struct;  # either listref or hashref is returned, depending on the call parameters
}


sub primary_key_constraint {
    my $self = shift @_;

    my $primary_key  = $self->primary_key();  # Attention: the order of primary_key columns of your call should match the order in the table definition!

    if(@$primary_key) {
        return join (' AND ', map { $primary_key->[$_]."='".$_[$_]."'" } (0..scalar(@$primary_key)-1));
    } else {
        my $table_name = $self->table_name();
        die "Table '$table_name' doesn't have a primary_key";
    }
}


sub fetch_by_dbID {
    my $self = shift @_;    # the rest in @_ should be primary_key column values

    return $self->fetch_all( $self->primary_key_constraint( @_ ) );
}


sub remove {    # remove the object by primary_key
    my $self    = shift @_;
    my $object  = shift @_;

    my $table_name              = $self->table_name();
    my $primary_key_constraint  = $self->primary_key_constraint( $self->slicer($object, $self->primary_key()) );

    my $sql = "DELETE FROM $table_name WHERE $primary_key_constraint";
    my $sth = $self->prepare($sql);
    $sth->execute();
    $sth->finish();
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

    my $sql = "UPDATE $table_name SET ".join(', ', map { "$columns_to_update->[$_]=$values_to_update->[$_]" } (0..@$columns_to_update-1) )." WHERE $primary_key_constraint";
    my $sth = $self->prepare($sql);
    $sth->execute();
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

    my ($return_value) = $sth->fetchrow();
    $sth->finish;

    return $return_value;
}


sub store {
    my ($self, $object_or_list, $check_presence_in_db_first) = @_;

    my $objects = (ref($object_or_list) eq 'ARRAY')     # ensure we get an array of objects to store
        ? $object_or_list
        : [ $object_or_list ];
    return unless(scalar(@$objects));

    my $table_name          = $self->table_name();
    my $column_set          = $self->column_set();
    my $autoinc_id          = $self->autoinc_id();
    my $driver              = $self->dbc->driver();
    my $insertion_method    = $self->insertion_method;  # INSERT, INSERT_IGNORE or REPLACE
    $insertion_method       =~ s/_/ /g;
    if($driver eq 'sqlite') {
        $insertion_method =~ s/INSERT IGNORE/INSERT OR IGNORE/ig;
    }

        # NB: let's pretend we are storing all columns:
    my $stored_columns = [ keys %$column_set ];
    # my $stored_columns = [ grep { $_ ne $autoinc_id } keys %$column_set ];

        # By using question marks we can insert true NULLs by setting corresponding values to undefs:
    my $sql = "$insertion_method INTO $table_name (".join(', ', @$stored_columns).') VALUES ('.join(',', (('?') x scalar(@$stored_columns))).')';
    my $sth;    # do not prepare the statement until there is a real need

    foreach my $object (@$objects) {
        if($check_presence_in_db_first and my $present = $self->check_object_present_in_db($object)) {
            $self->mark_stored($object, $present);
        } else {
            #print "STORE: $sql\n";
            $sth ||= $self->prepare( $sql );    # only prepare (once) if we get here

            #print "STORED_COLUMNS: ".join(', ', @$stored_columns)."\n";
            my $stored_values = $self->slicer( $object, $stored_columns );
            #print "STORED_VALUES: ".join(', ', @$stored_values)."\n";

            my $return_code = $sth->execute( @$stored_values )
                    # using $return_code in boolean context allows to skip the value '0E0' ('no rows affected') that Perl treats as zero but regards as true:
                or die "Could not perform\n\t$sql\nwith data:\n\t(".join(',', @$stored_values).')';
            if($return_code > 0) {     # <--- for the same reason we have to be expliticly numeric here
                $self->mark_stored($object, $self->dbc->db_handle->last_insert_id(undef, undef, $table_name, $autoinc_id) );
            }
        }
    }

    $sth && $sth->finish();

    return $object_or_list;
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

        my $filter_components = $filter_string && [ split('_and_', $filter_string) ];
        foreach my $column_name ( @$filter_components ) {
            unless($column_set->{$column_name}) {
                die "unknown column '$column_name'";
            }
        }
        my $key_components = $key_string && [ split('_and_', $key_string) ];
        foreach my $column_name ( @$key_components ) {
            unless($column_set->{$column_name}) {
                die "unknown column '$column_name'";
            }
        }
        if($value_column && !$column_set->{$value_column}) {
            die "unknown column '$value_column'";
        }

        print "Setting up '$AUTOLOAD' method\n";
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
        my $filter_name = $1;

        my ($self) = @_;
        my $column_set = $self->column_set();

        if($column_set->{$filter_name}) {
            print "Setting up '$AUTOLOAD' method\n";
            *$AUTOLOAD = sub { my ($self, $filter_value) = @_; return $self->count_all("$filter_name='$filter_value'"); };
            goto &$AUTOLOAD;    # restart the new method
        } else {
            die "unknown column '$filter_name'";
        }
    } elsif($AUTOLOAD =~ /::update_(\w+)$/) {
        my @columns_to_update = split('_and_', $1);
        print "Setting up '$AUTOLOAD' method\n";
        *$AUTOLOAD = sub { my ($self, $object) = @_; return $self->update($object, @columns_to_update); };
        goto &$AUTOLOAD;    # restart the new method
    } else {
        print "sub '$AUTOLOAD' not implemented";
    }
}

1;

