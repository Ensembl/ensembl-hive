Serialising dataflow events with JSON
=====================================

There are some facilities to support serialisaiton of events such as dataflow as JSON files or streams.

The :ref:`Runnable API <runnable_api_dataflows>` provides a method
``dataflow_output_ids_from_json($filename, $default_branch)`` to read a set of paramaters (output IDs)
serialised as JSON from a flat file.

Additionally, eHive uses JSON serialisation to interface Runnables written in guest languages (such as Python)
with Workers. This is handled by, and documented in, ``Bio::EnsEMBL::Hive::GuestProcess``. This could serve
as an example for advanced users wishing to construct infrastructure to transmit events between eHive
and other systems.
