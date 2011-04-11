# Perl module for Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor
#
# Date of creation: 22.03.2004
# Original Creator : Jessica Severin <jessica@ebi.ac.uk>
#
# Copyright EMBL-EBI 2004
#
# You may distribute this module under the same terms as perl itself

=pod

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor 

=head1 SYNOPSIS

  $dataflowRuleAdaptor = $db_adaptor->get_DataflowRuleAdaptor;
  $dataflowRuleAdaptor = $dataflowRuleObj->adaptor;

=head1 DESCRIPTION

  Module to encapsulate all db access for persistent class DataflowRule.
  There should be just one per application and database connection.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _
  
=cut


package Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;

use strict;
use Carp;
use Bio::EnsEMBL::Hive::DataflowRule;
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;
use Bio::EnsEMBL::Hive::Utils ('stringify');  # import 'stringify()'

use base ('Bio::EnsEMBL::DBSQL::BaseAdaptor');

=head2 branch_name_2_code

Description: encodes a branch mnemonic name into numeric code

=cut

sub branch_name_2_code {
    my $branch_name_or_code = pop @_;   # NB: we take the *last* arg, so it works both as a method and a subroutine

    $branch_name_or_code=1 unless(defined($branch_name_or_code));

    my $branch_code = ($branch_name_or_code=~/^\-?\d+$/)
        ? $branch_name_or_code
        : {
            'MAIN'          =>  1,

            'ANYFAILURE'    =>  0,
            'MEMLIMIT'      => -1,
            'RUNLIMIT'      => -2,
        }->{$branch_name_or_code};
    return defined($branch_code) ? $branch_code : die "Could not map the branch_name '$branch_name_or_code' to the internal code";
}

=head2 fetch_all_by_from_analysis_id_and_branch_code

  Args       : unsigned int $analysis_id, unsigned int $branch_code
  Example    : my @rules = @{$ruleAdaptor->fetch_all_by_from_analysis_id_and_branch_code($analysis_id, $branch_code)};
  Description: searches database for rules with given from_analysis_id and branch_code
               and returns all such rules in a list (by reference)
  Returntype : reference to list of Bio::EnsEMBL::Hive::DataflowRule objects
  Exceptions : none
  Caller     : Bio::EnsEMBL::Hive::AnalysisJob::dataflow_output_id

=cut

sub fetch_all_by_from_analysis_id_and_branch_code {
    my ($self, $analysis_id, $branch_name_or_code) = @_;

    return [] unless($analysis_id);

    my $branch_code = $self->branch_name_2_code($branch_name_or_code);

    my $constraint = "r.from_analysis_id=${analysis_id} AND r.branch_code=${branch_code}";

    return $self->_generic_fetch($constraint);
}

sub check_rule_exists_in_db {
    my ( $self, $rule ) = @_;

    my $from_analysis_id  = $rule->from_analysis_id;
    my $to_analysis_url   = $rule->to_analysis_url;
    my $branch_code       = $rule->branch_code;
    my $input_id_template = ref($rule->input_id_template) ? stringify($rule->input_id_template) : $rule->input_id_template;

    my $sql = qq{
        SELECT dataflow_rule_id
          FROM dataflow_rule
         WHERE from_analysis_id='$from_analysis_id'
           AND to_analysis_url='$to_analysis_url'
           AND branch_code='$branch_code'
           AND input_id_template
    } . ( defined($input_id_template) ? "='$input_id_template'" : "IS NULL" );

    my $sth = $self->prepare($sql);
    $sth->execute();

    if(my ($dataflow_rule_id) = $sth->fetchrow()) {
        $sth->finish;
        return $dataflow_rule_id;
    } else {
        $sth->finish;
        return 0;
    }
}

=head2 store

  Usage   : $self->store( $rule );
  Function: Stores a rule in db
            Sets adaptor and dbID in DataflowRule
  Returns : -
  Args    : Bio::EnsEMBL::Hive::DataflowRule

=cut

sub store {
    my ( $self, $rule ) = @_;

    my $dataflow_rule_id;

    if($dataflow_rule_id = $self->check_rule_exists_in_db($rule)) {

        $rule->dbID($dataflow_rule_id);
        $rule->adaptor( $self );
        return 0;

    } else {
        
        my $from_analysis_id  = $rule->from_analysis_id;
        my $to_analysis_url   = $rule->to_analysis_url;
        my $branch_code       = $rule->branch_code;
        my $input_id_template = ref($rule->input_id_template) ? stringify($rule->input_id_template) : $rule->input_id_template;

        my $sth = $self->prepare("INSERT INTO dataflow_rule (from_analysis_id, to_analysis_url, branch_code, input_id_template) VALUES (?,?,?,?)");

        my $rtnCode = $sth->execute($from_analysis_id, $to_analysis_url, $branch_code, $input_id_template);

        if($rtnCode and ($rtnCode != 0E0)) {   # we managed to insert a new row (0E0 would indicate success when no rows were inserted)
            $dataflow_rule_id = $sth->{'mysql_insertid'};
            $sth->finish();
            $rule->dbID($dataflow_rule_id);
            $rule->adaptor( $self );
            return 1;
        } else {
            die "Could not create a dataflow_rule('$from_analysis_id', '$to_analysis_url', '$branch_code', '$input_id_template')";
        }
    }
}


=head2 remove

  Title   : remove
  Usage   : $self->remove( $rule );
  Function: removes given object from database.
  Returns : -
  Args    : Bio::EnsEMBL::Hive::DataflowRule which must be persistent with a valid dbID
            
=cut

sub remove {
  my ( $self, $rule ) = @_;

  my $dbID = $rule->dbID;
  if( !defined $dbID ) {
    throw( "DataflowRuleAdaptor->remove called with non persistent DataflowRule" );
  }

  my $sth = $self->prepare("DELETE FROM dataflow_rule WHERE dataflow_rule_id = $dbID");
  $sth->execute;
}


=head2 create_rule

  Title   : create_rule
  Usage   : $self->create_rule( $from_analysis, $to_analysis, $branch_code );
  Function: Creates and stores a new rule in the DB.
  Returns : Bio::EnsEMBL::Hive::DataflowRule
  Args[1] : Bio::EnsEMBL::Analysis $from_analysis
  Args[2] : Bio::EnsEMBL::Analysis OR a hive-style URL  $to_analysis_or_url
  Args[3] : (optional) int $branch_code
  Args[4] : (optional) (Perl structure or string) $input_id_template

=cut

sub create_rule {
    my ($self, $from_analysis, $to_analysis_or_url, $branch_name_or_code, $input_id_template) = @_;

    return unless($from_analysis and $to_analysis_or_url);

    my $rule = Bio::EnsEMBL::Hive::DataflowRule->new(
        -from_analysis      =>  $from_analysis,

        ref($to_analysis_or_url)
            ? ( -to_analysis     => $to_analysis_or_url )
            : ( -to_analysis_url => $to_analysis_or_url ),

        -branch_code        =>  $self->branch_name_2_code($branch_name_or_code),
        -input_id_template  =>  $input_id_template,
    );

    return $self->store($rule);
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

  return (['dataflow_rule', 'r']);
}


sub _columns {
  my $self = shift;

  return qw (r.dataflow_rule_id
             r.from_analysis_id
             r.to_analysis_url
             r.branch_code
             r.input_id_template
            );
}


sub _objs_from_sth {
  my ($self, $sth) = @_;
  my @rules = ();

  my ($dataflow_rule_id, $from_analysis_id, $to_analysis_url, $branch_code, $input_id_template);
  $sth->bind_columns(\$dataflow_rule_id, \$from_analysis_id, \$to_analysis_url, \$branch_code, \$input_id_template);

  while ($sth->fetch()) {
    my $rule = Bio::EnsEMBL::Hive::DataflowRule->new(
        -dbID               =>  $dataflow_rule_id,
        -adaptor            =>  $self,

        -from_analysis_id   =>  $from_analysis_id,
        -to_analysis_url    =>  $to_analysis_url,
        -branch_code        =>  $branch_code,
        -input_id_template  =>  $input_id_template,
    );
    push @rules, $rule;
  }
  return \@rules;
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

=head2 fetch_by_dbID
  
  Arg [1]    : int $id
               the unique database identifier for the feature to be obtained
  Example    : $feat = $adaptor->fetch_by_dbID(1234);
  Description: Returns the Member created from the database defined by the
               the id $id.
  Returntype : Bio::EnsEMBL::Hive::DataflowRule
  Exceptions : thrown if $id is not defined
  Caller     : general
  
=cut

sub fetch_by_dbID {
  my ($self,$id) = @_;

  unless(defined $id) {
    throw("fetch_by_dbID must have an id");
  }

  my @tabs = $self->_tables;

  my ($name, $syn) = @{$tabs[0]};

  #construct a constraint like 't1.table1_id = 1'
  my $constraint = "${syn}.${name}_id = $id";

  #return first element of _generic_fetch list
  my ($obj) = @{$self->_generic_fetch($constraint)};
  return $obj;
}


=head2 fetch_all

  Arg        : None
  Example    :
  Description:
  Returntype :
  Exceptions :
  Caller     :

=cut

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

