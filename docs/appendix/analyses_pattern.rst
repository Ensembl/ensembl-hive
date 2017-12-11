Analyses pattern syntax
=======================

This document describes the syntax used for the analyses_pattern selector.
It is a simple language to select some analyses in a pipeline.

Overview
--------

The general syntax is expressed in a pseudo-BNF form below.

.. code-block:: abnf

    expression = <integer>
               | <integer> '..' <integer>
               | <integer> '..'
               | '..' <integer>
               | <word>
               | <word-with-%-sign>
               | <word> '==' <any>
               | <word> '!=' <any>
               | <word> '<=' <any>
               | <word> '>=' <any>
               | <word> '<' <any>
               | <word> '>' <any>

    expression-combinator = ',' | '+' | '-'

    pattern = pattern
            | pattern expression-combinator expression


Overall, a pattern is a sequence of expressions separated with a comma, a
plus sign or a minus sign. The pattern is evaluated from left to right,
starting with the content of the first expression, and adding (comma or
plus sign) or substracting (minus sign) the content of the next expression,
until the end is reached.


dbID filtering
--------------

Expressions including an ``<integer>`` select content based on their *dbID*
(the numerical index of the objects in the database).

``<integer>``
    the object with this dbID
``<integer> '..' <integer>``
    the objects within this range of dbIDs (both ends included)
``<integer> '..'``
    the objects with a dbID greater or equal to this number
``'..' <integer>``
    the objects with a dbID lower or equal to this number

Name filtering
--------------

Expressions that consist of a single word select content based on their
*name*.

``<word>``
    the object with this name
``<word-with-%-sign>``
    the objects matching the name, ``%`` meaning "any sequence of
    characters"

General filtering
-----------------

Finally, expressions that consist of a ``<word>`` with a relational
operator and a value allow to filter objects on one of their attributes
(for instance, ``module`` or ``analysis_capacity`` for analyses).

