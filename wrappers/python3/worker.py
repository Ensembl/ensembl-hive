#!/usr/bin/env python3

import os
import sys

import eHive

def error_quit(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)

def usage(msg):
    error_quit("Command-line error: {1}\nUsage: worker.py module_name [compile | run fd_in fd_out]\n{0}".format(sys.argv, msg))

def find_module(module_name):

    # NB: We assyme that the runnable has the same name as the file itself
    class_name = module_name.split('.')[-1]

    # import
    try:
        module = __import__(module_name)
    except ImportError:
        error_quit("ImportError: No module named '{0}'. sys.path is {1}".format(module_name, sys.path))

    # resolve namespace / module
    if '.' in module_name:
        # Module is the namespace, e.g. LongMult if we required LongMult.AddTogether
        # We need to extract the real module
        module = getattr(module, class_name)

    # get the class in the module
    if not hasattr(module, class_name):
        import difflib
        possible_modules = [_ for _ in dir(module) if isinstance(getattr(module, _), type) and issubclass(getattr(module, _), eHive.BaseRunnable)]
        possible_modules = sorted(possible_modules, key = lambda _ : difflib.SequenceMatcher(a=class_name, b=_, autojunk=False).ratio(), reverse=True)
        s = "ImportError: No class named '{0}' in the module '{1}'.\n"
        if len(possible_modules):
            s += "Tip: You probably meant one of the {2} Runnable classes found in {1}: {3}"
        else:
            s += "Warning: {1} doesn't containts any Runnable classes"
        s += "\n{1} is in {5}, sys.path is {4}"
        error_quit(s.format(class_name, module_name, len(possible_modules), ', '.join(possible_modules), sys.path, module.__file__))

    c = getattr(module, class_name)
    if not issubclass(c, eHive.BaseRunnable):
        error_quit("ImportError: {0} (found in {1}) is not a sub-class of eHive.BaseRunnable".format(class_name, module.__file__))

    return c

if len(sys.argv) < 3:
    usage('Not enough arguments')

mode = sys.argv[2]
if mode not in [ 'compile', 'run' ]:
    usage('Unknown mode')

# Set up PYTHONPATH and load the runnable
sys.path.insert(0, os.environ['EHIVE_ROOT_DIR'] + '/wrappers/python3')
runnable = find_module(sys.argv[1])

if mode == 'run':
    if len(sys.argv) != 5:
        usage('Wrong number of arguments')
    try:
        fd_in = int(sys.argv[3])
        fd_out = int(sys.argv[4])
    except:
        usage('Cannot interpret file descriptors')
    runnable(fd_in, fd_out)

sys.exit(0)

