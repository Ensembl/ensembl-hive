.. ehive creating pipelines guide, a description of accumulators

.. The default language is set to perl. Non-perl code-blocks have to define
   their own language setting
.. highlight:: perl


Accumulators
============

Accumulators are a way of passing data from within a semaphore group
to its controlling funnel.

Accumulators are defined within pipelines as URLs. These must have the
``accu_name`` key, which indicates the name of the funnel's parameter that
will hold the data. These data come from the dataflow event, specifically
the parameter that has the name of the ``accu_name`` key. This can be
overridden with the ``accu_input_variable`` key.
There are five types of Accumulators, all described below:
scalar, pile, multiset, array and hash. For each of them we show how to
initialise them and equivalent Perl code to build the same structure.

Scalar
~~~~~~

:Basic syntax:
    ``?accu_name=scalar_name``

:Extended syntax:
    ``?accu_name=scalar_name&accu_input_variable=output_parameter_name``

:Retrieval:
    ``my $scalar_value = $self->param('scalar_value');``

This is the simplest type of Accumulator. The basic syntax example passes
he value of the ``scalar_name`` parameter from the *fan* to the
*funnel*. The extended syntax example makes the value of the
``output_parameter_name`` parameter from the *fan* available to the
*funnel* as if it were a parameter named ``scalar_name``. If there are
multiple Jobs in the fan, eHive will arbitrarily select one of them to
define the Accumulator.

In Perl, this is equivalent to doing this:

:Accumulator initialisation:
   ::

       my $scalar_name;

:Accumulator extension:
   ::

       $scalar_name = $scalar_name;           # Basic syntax
       $scalar_name = $output_parameter_name; # Extended syntax

:Accumulator retrieval:
   ::

       say "Value: $scalar_name";


Pile
~~~~

:Basic syntax:
    ``?accu_name=pile_name&accu_address=[]``

:Extended syntax:
    ``?accu_name=pile_name&accu_address=[]&accu_input_variable=pile_component``

:Retrieval:
  ::

      my $pile_ref = $self->param('pile_name');
      foreach my $pile_element (@{$pile_ref}) {
          # do something with $pile_element
      }


A pile is an unordered list. All the ``pile_name`` (or ``pile_component``
in the second form) values that are dataflown
into the Accumulator are aggregated into a list named ``pile_name``
in a *random* order.

In Perl, this is similar to doing this:

:Accumulator initialisation:
   ::

       my @pile_name;

:Accumulator extension:
   ::

       push @pile_name, $pile_name;             # Basic syntax
       push @pile_name, $pile_component;        # Extended syntax

:Accumulator retrieval:
   ::

       foreach my $v (@pile_name) {
           say "Value: $v";
       }


Multiset
~~~~~~~~

:Basic syntax:
    ``?accu_name=multiset_name&accu_address=[]``

:Extended syntax:
    ``?accu_name=multiset_name&accu_address=[]&accu_input_variable=multiset_component``

:Retrieval:
   ::

      my $multiset_ref = $self->param('multiset_name');
      foreach my $multiset_key (keys(%{$multiset_ref})) {
          my $count = $multiset_ref->{$multiset_key};
      }

A multiset is a set that allows multiple instances of the same element (see
Wikipedia_). It is implemented in eHive as a *hash* that maps each element
to its multiplicity (a positive integer). The above URLs define a multiset
named ``multiset_name``, filling it with either the ``multiset_name`` or
``multiset_component`` parameter.

.. _Wikipedia: https://en.wikipedia.org/wiki/Multiset

In Perl, this is equivalent to doing this:

:Accumulator initialisation:
   ::

       my %multiset_name;

:Accumulator extension:
   ::

       $multiset_name{$multiset_name} += 1;             # Basic syntax
       $multiset_name{$multiset_component} += 1;        # Extended syntax

:Accumulator retrieval:
   ::

       foreach my $key (keys %multiset_name) {
           say "Value $key is present ".$multiset_name{$key}." times";
       }


Array
~~~~~

:Basic syntax:
    ``?accu_name=array_name&accu_address=[index_name]``

:Extended syntax:
    ``?accu_name=array_name&accu_address=[index_name]&accu_input_variable=array_item``

:Retrieval:
   ::

      my $array_arrayref = $self->param('array_name');
      foreach my $array_element (@{$array_arrayref}) {
          # do something with $array_element
      } 

Here the emitting Job must flow both the value of the array item (either
via the ``array_name`` or ``array_item`` parameter) and its index
``index_name``.
eHive puts together the items at the requested
positions, filling the gaps with `undef`, in an array named ``array_name``.

In Perl, this is equivalent to doing this:

:Accumulator initialisation:
   ::

       my @array_name;

:Accumulator extension:
   ::

       $array_name[$index_name] = $array_name;          # Basic syntax
       $array_name[$index_name] = $array_item;          # Extended syntax

:Accumulator retrieval:
   ::

       foreach my $v (@array_name) {
           say "Value: $v";
       }


Hash
~~~~

:Basic syntax:
    ``?accu_name=hash_name&accu_address={key_name}``

:Extended syntax:
    ``?accu_name=hash_name&accu_address={key_name}&accu_input_variable=hash_item``

:Retrieval:
   ::

      my $hash_hashref = $self->param('hash_name');
      foreach my $key (keys(%{$hash_hashref})) {
          my $value = $hash_hashref->{$key};
      }


Here the emitting Job must flow both the value of the hash item (either
via the ``hash_name`` or ``hash_item`` parameter) and the key name
``key_name``.
eHive puts together the items in a hash named ``hash_name``.

In Perl, this is equivalent to doing this:

:Accumulator initialisation:
   ::

       my %hash_name;

:Accumulator extension:
   ::

       $hash_name{$key_name} = $hash_name;          # Basic syntax
       $hash_name{$key_name} = $hash_item;          # Extended syntax

:Accumulator retrieval:
   ::

       foreach my $key (keys %hash_name) {
           say "Value $key is mapped to ".$hash_name{$key};
       }


Advanced data structures
~~~~~~~~~~~~~~~~~~~~~~~~

The ``accu_address`` key can define more complex data structures by
chaining the simple address types shown above. For instance the following
Accumulator definition will create a multi-level hash that stores the list
of all genes on each triplet (species, chromosome, strand).

.. code-block:: none

    ?accu_name=gene_lists&accu_address={species}{chromosome}{strand}[]&accu_input_variable=gene_name

Traversing the resulting hash can be done this way in Perl:

::

    my %gene_list = %{$self->param('gene_list')};
    foreach my $species (keys %gene_list) {
        say "$species has ".scalar(keys %{$gene_list->{$species}})." chromosomes";
        foreach my $chromosome (keys %{$gene_list->{$species}}){
            my $pos_strand_genes = $gene_list->{$species}->{$chromosome}->{1};
            my $neg_strand_genes = $gene_list->{$species}->{$chromosome}->{-1};
            say "Chrom. $chromosome of $species has "
                 .scalar(@$pos_strand_genes)." genes on the positive strand and "
                 .scalar(@$neg_strand_genes)." genes on the negative strand";
        }
    }

K-mer pipeline
''''''''''''''

There are further examples in the Kmer example pipelines. These three
pipelines all perform the same workflow (computing the distribution of k-mer
in a given set of input sequences), but accomplish the task in different ways
using various Accumulator patterns.

The first Analyses of the pipeline will break up the input sequences in
chunks that can be efficiently processed in parallel. The processing and
the dataflowing of each chunk are done *exactly* the same way in all flavours, but
because of different Accumulator syntaxes, the funnel (the "compile_count"
Analysis, which does the final summation) will have to use the resulting data structure in different ways.

The "count_kmers" Analysis dataflows on two branches:

- On branch #3 a hash that has the name of the file (*sequence_file* key) and the counts per k-mer
  (as a hash under the *counts* key).
- On branch #4 a series of hashes that contain the name of the file
  (*sequence_file* key), a k-mer (*kmer* key) and its count in that file
  (*count* key).

:KmerPipelineAoH_conf -- Array of Hashes:

    In this mode, the Accumulator is connected to branch #3 and aggregates
    all the *counts* field in a pile. The information about the initial
    file name is not tracked in the Accumulator.

    The Accumulator syntax is ``?accu_name=all_counts&accu_address=[]&accu_input_variable=counts``

:KmerPipelineHoH_conf -- Hash of Hashes:

    In this mode, the Accumulator is connected to branch #3 and
    aggregates all the *counts* field in a hash indexed by the name of the
    chunk *sequence_file*.

    The Accumulator syntax is ``?accu_name=all_counts&accu_address={sequence_file}&accu_input_variable=counts``

:KmerPipelineHoA_conf -- Hash of Arrays:

    In this mode, the Accumulator is connected to branch #4 and aggregates
    all the counts in one array per k-mer.
    The signature `{kmer}[]` indicates that the final structure is a hash
    indexed by each *kmer*, and whose values are piles of the Accumulator's input variable, i.e. *count*.
    The Accumulator syntax is ``?accu_name=all_counts&accu_address={kmer}[]&accu_input_variable=count``

