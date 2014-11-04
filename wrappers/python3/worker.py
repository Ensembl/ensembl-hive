#!/usr/bin/env python3

import os
import sys

assert len(sys.argv) == 4, ("There must be 3 arguments to the script", sys.argv)
assert isinstance(sys.argv[1], str), ("The first argument must be a module name", sys.argv[1])

# Set up PYTHONPATH and load the runnable
sys.path.insert(0, os.environ['EHIVE_ROOT_DIR'] + '/wrappers/python3')
module_name = sys.argv[1]
module = __import__(module_name)

# NB: We assyme that the runnable has the same name as the file itself
class_name = module_name.split('.')[-1]
if '.' in module_name:
    assert hasattr(module, class_name), "Could not get inside the loaded module"
    module = getattr(module, class_name)
assert hasattr(module, class_name), ("Could not find the class '{0}' in the module '{1}'".format(class_name, module_name))

# We construct the object, which starts the life-cycle
runnable = getattr(module, class_name)(int(sys.argv[2]), int(sys.argv[3]))

