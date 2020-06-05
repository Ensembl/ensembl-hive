
This is the reference python3 implementation of the *GuestLanguage*
protocol in eHive.

It allows to write Runnables in python3 and add them to standard eHive
pipelines, potentially alongside Perl Runnables.

Like in Perl, analyses are given a module name, which must contain a class
of the same name. The class must inherit from eHive.BaseRunnable (see
eHive.examples.LongMult.DigitFactory for an example) and implement the
usual `fetch_input()`, `run()`, and / or `write_output()` methods.

Runnables can use the eHive API (like `param()`). See eHive.process.BaseRunnable
for the list of available methods.

