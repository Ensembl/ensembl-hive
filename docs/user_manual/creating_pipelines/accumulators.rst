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
will hold the data. The data come from the Dataflow event, specifically
the parameter that has the name of the ``accu_name`` key. This can be
overriden with the ``accu_input_variable`` key.
There are five types of accumulators, all described below:
scalar, pile, multiset, array and hash. For each of them we show how to
initialize them and equivalent Perl code to build the same structure.

Scalar
~~~~~~

:Syntax:
    ``?accu_name=scalar_name``

This is the simplest type of accumulator. The value of the ``scalar_name``
parameter is passed from the *fan* to the *funnel*. If there are multiple jobs
in the fan, eHive will arbitrarily select one of them to define the
accumulator.

In Perl, this is equivalent to doing this:

:Accumulator initialization:
   ::

       my $scalar_name;

:Accumulator extension:
   ::

       $scalar_name = $scalar_name;

:Accumulator retrieval:
   ::

       say "Value: $scalar_name";


Pile
~~~~

:Basic syntax:
    ``?accu_name=pile_name&accu_address=[]``

:Extended syntax:
    ``?accu_name=pile_name&accu_address=[]&accu_input_variable=pile_component``

A pile is an unordered list. All the ``pile_name`` (or ``pile_component``
in the second form) values that are flown
into the accumulator are aggregated into a list named ``pile_name``
in a **random** order.

In Perl, this is equivalent to doing this:

:Accumulator initialization:
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

A multiset is a set that allows multiple instances of the same element (see
Wikipedia_). It is implemented in eHive as a *hash* that maps each element
to its multiplicity (a positive integer). The above URLs define a multiset
named ``multiset_name``, filling it with either the ``multiset_name`` or
``multiset_component`` parameter.

.. _Wikipedia: https://en.wikipedia.org/wiki/Multiset

In Perl, this is equivalent to doing this:

:Accumulator initialization:
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

Here the emitting job must flow both the value of the array item (either
via the ``array_name`` or ``array_item`` parameter) and its index
``index_name``.
eHive puts together the items at the requested
positions, filling the gaps with `undef`, in an array named ``array_name``.

In Perl, this is equivalent to doing this:

:Accumulator initialization:
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
    ``?accu_name=hash_name&accu_address=[key_name]``

:Extended syntax:
    ``?accu_name=hash_name&accu_address=[key_name]&accu_input_variable=hash_item``

Here the emitting job must flow both the value of the hash item (either
via the ``hash_name`` or ``hash_item`` parameter) and the key name
``key_name``.
eHive puts together the items in a hash named ``hash_name``.

In Perl, this is equivalent to doing this:

:Accumulator initialization:
   ::

       my %hash_name;

:Accumulator extension:
   ::

       $hash_name[$key_name] = $hash_name;          # Basic syntax
       $hash_name[$key_name] = $hash_item;          # Extended syntax

:Accumulator retrieval:
   ::

       foreach my $key (keys %hash_name) {
           say "Value $key is mapped to ".$hash_name{$key};
       }


Advanced data structures
~~~~~~~~~~~~~~~~~~~~~~~~

The ``accu_address`` key can actually define more complex data structures
by chaining the *simple* address types shown above. For instance the
following accumulator definition
will create a multi-level hash that stores the list of all genes on each triplet (species,
chromosome, strand).

.. code-block:: none

    ?accu_name=gene_lists&accu_address={species}{chromosome}{strand}[]&accu_input_variable=gene_name

Traversing the resulting hash can be done this way in Perl:

::

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


