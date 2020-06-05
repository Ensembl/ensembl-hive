
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
This module provide utility methods.
"""

import sys

from .process import BaseRunnable


def find_module(module_name):
    """Find and instantiate a Runnable, given its name"""

    module = None
    def import_error(msg):
        if msg[-1] != "\n":
            msg += "\n"
        if (module is not None) and hasattr(module, '__file__'):
            msg += module.__name__ + " is in " + module.__file__ + "\n"
        msg += "sys.path is " + str(sys.path)
        raise ImportError(msg)

    # Import the whole module chain
    try:
        module = __import__(module_name)
    except ImportError as e:
        import_error("Cannot import '{0}' : {1}".format(module_name, e))

    # Traverse the namespaces down to the module
    # e.g. If module_name is "eHive.examples.LongMult.AddTogether", module represents "LongMult" at this stage
    for submodule in module_name.split('.')[1:]:
        if hasattr(module, submodule):
            module = getattr(module, submodule)
        else:
            import_error("Cannot find '{0}' in '{1}'".format(submodule, module))
    # e.g. module now represents "AddTogether"

    if not hasattr(module, '__file__'):
        import_error('"{0}" is a namespace, not a module'.format(module.__name__))

    # NB: We assume that the runnable has the same name as the file itself
    class_name = module_name.split('.')[-1]

    # get the class in the module
    if not hasattr(module, class_name):
        # it could be a typo ... Let's print the available modules by decreasing distance to the required name
        possible_modules = [_ for _ in dir(module) if isinstance(getattr(module, _), type) and issubclass(getattr(module, _), BaseRunnable)]
        if possible_modules:
            import difflib
            possible_modules.sort(key=lambda s: difflib.SequenceMatcher(a=class_name, b=s, autojunk=False).ratio(), reverse=True)
            s = "No class named '{0}' in the module '{1}'.\n"
            s += "Warning: {1} contains {2} Runnable classes ({3}). Should one of them be renamed ?"
            import_error(s.format(class_name, module_name, len(possible_modules), ', '.join('"%s"' % _ for _ in possible_modules)))
        else:
            import_error("Warning: {} doesn't contain any Runnable classes".format(module_name))

    # Check that the class is a runnable
    c = getattr(module, class_name)
    if not isinstance(c, type):
        import_error("{0} (found in {1}) is not a class but a {2}".format(class_name, module.__file__, type(c)))
    if not issubclass(c, BaseRunnable):
        import_error("{0} (found in {1}) is not a sub-class of eHive.BaseRunnable".format(class_name, module.__file__))

    return c

