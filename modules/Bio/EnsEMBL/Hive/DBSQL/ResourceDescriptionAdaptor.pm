=pod

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::ResourceDescriptionAdaptor

=head1 SYNOPSIS

  $resource_description_adaptor = $db_adaptor->get_ResourceDescriptionAdaptor;

  $resource_description_adaptor = $resource_description_object->adaptor;

=head1 DESCRIPTION

  Module to encapsulate all db access for persistent class ResourceDescription.
  There should be just one per application and database connection.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::ResourceDescriptionAdaptor;

use strict;
use Bio::EnsEMBL::Hive::ResourceDescription;

use base ('Bio::EnsEMBL::DBSQL::BaseAdaptor');

sub fetch_by_rcid_meadowtype {
    my ($self, $rc_id, $meadow_type) = @_;

    my $constraint = "rd.rc_id = $rc_id AND rd.meadow_type = '$meadow_type'";
    my ($rd) = @{ $self->_generic_fetch($constraint) };

    return $rd;     # returns one object or undef
}

sub fetch_all_by_meadowtype {
    my ($self, $meadow_type) = @_;

    my $constraint = "rd.meadow_type = '$meadow_type'";
    return $self->_generic_fetch($constraint);      # returns an arrayref
}

sub store {
    my ( $self, $rd ) = @_;

    my $sth = $self->prepare( q{REPLACE INTO resource_description (rc_id, meadow_type, parameters, description) VALUES (?,?,?,?) } );
    $sth->execute($rd->rc_id, $rd->meadow_type, $rd->parameters, $rd->description);
    $sth->finish();

    return $rd;
}

sub remove {
    my ( $self, $rd ) = @_;

    my $sth = $self->prepare( q{DELETE FROM resource_description WHERE rc_id = ? AND meadow_type = ?} );
    $sth->execute($rd->rc_id, $rd->meadow_type);
    $sth->finish();
}

sub create_new {
    my $self = shift @_;

    my $rd = Bio::EnsEMBL::Hive::ResourceDescription->new(@_, -ADAPTOR => $self);
    return $self->store($rd);
}

############################
#
# INTERNAL METHODS
# (pseudo subclass methods)
#
############################

#internal method used in multiple calls above to build objects from table data

sub _tables {
    my $self = shift;

    return (['resource_description', 'rd']);
}


sub _columns {
    my $self = shift;

    return qw (rd.rc_id
             rd.meadow_type
             rd.parameters
             rd.description
    );
}


sub _objs_from_sth {
    my ($self, $sth) = @_;
    my @rds = ();

    while(my ($rc_id, $meadow_type, $parameters, $description) = $sth->fetchrow_array) {
        my $rd = Bio::EnsEMBL::Hive::ResourceDescription->new(
            -ADAPTOR     => $self,
            -RC_ID       => $rc_id,
            -MEADOW_TYPE => $meadow_type,
            -PARAMETERS  => $parameters,
            -DESCRIPTION => $description,
        );
        push @rds, $rd;
    }
    return \@rds;
}


sub _default_where_clause {
    my $self = shift;
    return '';
}


sub _final_clause {
    my $self = shift;
    return '';
}

###############################################################################
#
# General access methods that could be moved
# into a superclass
#
###############################################################################

sub fetch_all {
    my $self = shift;
    return $self->_generic_fetch();
}


sub _generic_fetch {
  my ($self, $constraint, $join) = @_;

  my @tables = $self->_tables;
  my $columns = join(', ', $self->_columns());

  if ($join) {
    foreach my $single_join (@{$join}) {
      my ($tablename, $condition, $extra_columns) = @{$single_join};
      if ($tablename && $condition) {
        push @tables, $tablename;

        if($constraint) {
          $constraint .= " AND $condition";
        } else {
          $constraint = " $condition";
        }
      }
      if ($extra_columns) {
        $columns .= ", " . join(', ', @{$extra_columns});
      }
    }
  }

  #construct a nice table string like 'table1 t1, table2 t2'
  my $tablenames = join(', ', map({ join(' ', @$_) } @tables));

  my $sql = "SELECT $columns FROM $tablenames";

  my $default_where = $self->_default_where_clause;
  my $final_clause = $self->_final_clause;

  #append a where clause if it was defined
  if($constraint) {
    $sql .= " WHERE $constraint ";
    if($default_where) {
      $sql .= " AND $default_where ";
    }
  } elsif($default_where) {
    $sql .= " WHERE $default_where ";
  }

  #append additional clauses which may have been defined
  $sql .= " $final_clause";

  my $sth = $self->prepare($sql);
  $sth->execute;

#  print STDERR $sql,"\n";

  return $self->_objs_from_sth($sth);
}

1;

