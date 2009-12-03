# Perl module for Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor
#
# Date of creation: 22.03.2004
# Original Creator : Jessica Severin <jessica@ebi.ac.uk>
#
# Copyright EMBL-EBI 2004
#
# You may distribute this module under the same terms as perl itself

=pod

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor 

=head1 SYNOPSIS

  $AnalysisCtrlRuleAdaptor = $db_adaptor->get_AnalysisCtrlRuleAdaptor;
  $analysisCtrlRuleAdaptor = $analysisCtrlRuleObj->adaptor;

=head1 DESCRIPTION

  Module to encapsulate all db access for persistent class AnalysisCtrlRule.
  There should be just one per application and database connection.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _
  
=cut



package Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor;

use strict;
use Carp;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::EnsEMBL::Hive::AnalysisCtrlRule;
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;

our @ISA = qw(Bio::EnsEMBL::DBSQL::BaseAdaptor);


=head2 fetch_by_ctrled_analysis_id

  Arg [1]    : int $id
               the unique database identifier for the feature to be obtained
  Example    : $ctrlRuleArray = $adaptor->fetch_by_ctrled_analysis_id($ctrled_analysis->dbID);
  Description: Returns an array reference of all the AnalysisCtrlRule objects 
               for the specified controled analysis.
  Returntype : listref of Bio::EnsEMBL::Hive::AnalysisCtrlRule objects
  Exceptions : thrown if $id is not defined
  Caller     : general
  
=cut

sub fetch_by_ctrled_analysis_id{
  my ($self,$id) = @_;

  unless(defined $id) {
    throw("fetch_by_ctrled_analysis_id must have an id");
  }

  my $constraint = "r.ctrled_analysis_id = $id";

  return $self->_generic_fetch($constraint);
}


=head2 fetch_all

  Arg        : None
  Example    : my $all_rules = $ctrlRuleDBA->fetch_all();
  Description: fetches all AnalysisCtrlRule objects from database
  Returntype : array reference of Bio::EnsEMBL::Hive::AnalysisCtrlRule objects
  Exceptions : none
  Caller     : general
  
=cut

sub fetch_all {
  my $self = shift;
  return $self->_generic_fetch();
}

=head2 store

  Arg[1]     : Bio::EnsEMBL::Hive::AnalysisCtrlRule object
  Usage      : $self->store( $rule );
  Function   : Stores a rule in db
               Sets adaptor and dbID in AnalysisCtrlRule object
  Returntype : none

=cut

sub store {
  my ( $self, $rule ) = @_;

  #print("\nAnalysisCtrlRuleAdaptor->store()\n");
 
  my $sth = $self->prepare(q{INSERT ignore INTO analysis_ctrl_rule 
        (ctrled_analysis_id, condition_analysis_url) VALUES(?,?) });
  if($sth->execute($rule->ctrled_analysis_id, $rule->condition_analysis_url)) {
    $sth->finish();
  }
  $rule->adaptor( $self );
}


=head2 remove_by_condition_analysis_url

  Arg[1]  : string condition_analysis_url
  Usage   : $self->remove_by_condition_analysis_url("ThisAnalysisLogicName");
  Function: removes all the control rules for this condition analysis URL
  Returns : -

=cut

sub remove_by_condition_analysis_url {
  my ( $self, $condition_analysis_url ) = @_;

  my $sth = $self->prepare("DELETE FROM analysis_ctrl_rule WHERE condition_analysis_url =?");
  $sth->execute($condition_analysis_url);
}


=head2 create_rule

  Arg[1]      : condition analysis object (Bio::EnsEMBL::Analysis object)
  Arg[2]      : controled analysis object (Bio::EnsEMBL::Analysis object)
  Example     : $dba->get_AnalysisCtrlRuleAdaptor->create_rule($conditionAnalysis, $ctrledAnalysis);
  Description : Creates an AnalysisCtrlRule where the condition analysis must be completely DONE with
                all jobs in order for the controlled analysis to be unblocked and allowed to proceed.
                If an analysis requires multiple conditions, simply create multiple rules and controlled
                analysis will only unblock if ALL conditions are satisified.
  Returntype  : none
  Exceptions  : none
  Caller      : general
  
=cut


sub create_rule {
  my ($self, $conditionAnalysis, $ctrledAnalysis) = @_;

  return unless($conditionAnalysis and $ctrledAnalysis);
  
  my $rule = Bio::EnsEMBL::Hive::AnalysisCtrlRule->new();
  #must set ctrled_analysis first in order for internal logic to abreviate 'to_url'
  $rule->ctrled_analysis($ctrledAnalysis);
  $rule->condition_analysis($conditionAnalysis);
  
  $self->store($rule);
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

  return (['analysis_ctrl_rule', 'r']);
}


sub _columns {
  my $self = shift;

  return qw (r.ctrled_analysis_id
             r.condition_analysis_url
            );
}


sub _objs_from_sth {
  my ($self, $sth) = @_;
  my @rules = ();

  my ($ctrled_analysis_id, $condition_analysis_url);
  $sth->bind_columns(\$ctrled_analysis_id, \$condition_analysis_url);

  while ($sth->fetch()) {
    my $rule = Bio::EnsEMBL::Hive::AnalysisCtrlRule->new;
    $rule->adaptor($self);
    $rule->ctrled_analysis_id($ctrled_analysis_id);
    $rule->condition_analysis_url($condition_analysis_url);
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
