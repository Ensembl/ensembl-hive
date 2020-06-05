
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2020] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Reference python3 implementation of eHive's "GuestLanguage" protocol.

It allows to write Runnables in python3 and add them to standard eHive
pipelines, potentially alongside Perl Runnables.

Like in Perl, analyses are given a module name, which must contain a class
of the same name. The class must inherit from eHive.BaseRunnable (see
eHive.examples.LongMult.DigitFactory for an example) and implement the
usual `fetch_input()`, `run()`, and / or `write_output()` methods.

Runnables can use the eHive API (like `param()`). See eHive.BaseRunnable
for the list of available methods.
"""

# We take all the interesting classes from both modules, i.e. BaseRunnable and all the exceptions
from .process import BaseRunnable, CompleteEarlyException, JobFailedException, __version__
from .params import ParamException, ParamNameException, ParamSubstitutionException, ParamInfiniteLoopException, ParamWarning

__all__ = ['BaseRunnable', 'CompleteEarlyException', 'JobFailedException', 'ParamException', 'ParamNameException', 'ParamSubstitutionException', 'ParamInfiniteLoopException', 'ParamWarning', '__version__']

