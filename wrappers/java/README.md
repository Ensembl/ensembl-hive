
This is the Java implementation of the *GuestLanguage* protocol in eHive.

It allows to write Runnables in Java and add them to standard eHive pipelines, 
potentially alongside Perl and Python Runnables.

Like in Perl, analyses are given a module name, which must contain a class
of the same name. The class must inherit from `org.ensembl.hive.BaseRunnable` 
(see `org.ensembl.hive.longmult.DigitFactory` for an example) and implement the 
abstract `fetchInput()`, `run()` and `writeOutput()` methods. The stub 
`preCleanUp()` and `postCleanUp()` methods may also be overridden as required.

Job information is encapsulated in the `org.ensembl.hive.Job` and parameters in 
`org.ensembl.hive.ParamContainer`. Currently, parameter handling _does not_ support 
dynamic parameter expansion using `#expr` markup

Due to the use of JSON for parent-child communication, params, input and output are 
handled as `Map<String,Object>`.
