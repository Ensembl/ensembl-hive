
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2021] EMBL-European Bioinformatics Institute
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
This module is an implementation of eHive's Param module.
It defines ParamContainer which is an attribute of BaseRunnable
and not its base class as in eHive's class hierarchy.
All the specific warnings and exceptions inherit from ParamWarning
and ParamException.
"""

import collections
import numbers
import unittest


class ParamWarning(Warning):
    """Used by process.BaseRunnable"""
    pass


class ParamException(Exception):
    """Base class for parameters-related exceptions"""
    pass
class ParamNameException(ParamException):
    """Raised when the parameter name is not a string"""
    def __str__(self):
        return '"{0}" (type {1}) is not a valid parameter name'.format(self.args[0], type(self.args[0]).__name__)
class ParamSubstitutionException(ParamException):
    """Raised when ParamContainer tried to substitute an unexpected structure (only dictionaries and lists are accepted)"""
    def __str__(self):
        return 'Cannot substitute elements in objects of type "{0}"'.format(str(type(self.args[0])))
class ParamInfiniteLoopException(ParamException):
    """Raised when parameters depend on each other, forming a loop"""
    def __str__(self):
        return "Substitution loop has been detected on {0}. Parameter-substitution stack: {1}".format(self.args[0], list(self.args[1].keys()))
class NullParamException(ParamException):
    """Raised when a parameter cannot be required because it is null (None)"""
    def __str__(self):
        return "{0} is None".format(self.args[0])


class ParamContainer:
    """Equivalent of eHive's Param module"""

    def __init__(self, unsubstituted_params, debug=False):
        """Constructor. "unsubstituted_params" is a dictionary"""
        self.unsubstituted_param_hash = unsubstituted_params.copy()
        self.param_hash = {}
        self.debug = debug


    # Public methods
    #################

    def set_param(self, param_name, value):
        """Setter. Returns the new value"""
        self.validate_parameter_name(param_name)
        self.param_hash[param_name] = value
        return value

    def get_param(self, param_name):
        """Getter. Performs the parameter substitution"""
        self.validate_parameter_name(param_name)
        self.substitution_in_progress = collections.OrderedDict()
        try:
            return self.internal_get_param(param_name)
        except (KeyError, SyntaxError, ParamException) as e:
            # To hide the part of the stack that is in ParamContainer
            raise e.with_traceback(None)

    def has_param(self, param_name):
        """Returns a boolean. It checks both substituted and unsubstituted parameters"""
        self.validate_parameter_name(param_name)
        return (param_name in self.param_hash) or (param_name in self.unsubstituted_param_hash)

    def substitute_string(self, string):
        """Apply the parameter substitution to the string"""
        self.substitution_in_progress = collections.OrderedDict()
        try:
            return self.param_substitute(string)
        except (KeyError, SyntaxError, ParamException) as e:
            # To hide the part of the stack that is in ParamContainer
            raise e.with_traceback(None)

    # Private methods
    ##################
    def validate_parameter_name(self, param_name):
        """Tells whether "param_name" is a non-empty string"""
        if not isinstance(param_name, str) or (param_name == ''):
            raise ParamNameException(param_name)

    def debug_print(self, *args, **kwargs):
        """Print debug information if the debug flag is turned on (cf constructor)"""
        if self.debug:
            print(*args, **kwargs)

    def internal_get_param(self, param_name):
        """Equivalent of get_param() that assumes "param_name" is a valid parameter name and hence, doesn't have to raise ParamNameException.
        It is only used internally"""
        self.debug_print("internal_get_param", param_name)
        if param_name not in self.param_hash:
            x = self.unsubstituted_param_hash[param_name]
            self.param_hash[param_name] = self.param_substitute(x)
        return self.param_hash[param_name]


    def param_substitute(self, structure):
        """
        Take any structure and replace the pairs of hashes with the values of the parameters / expression they represent
        Compatible types: numbers, strings, lists, dictionaries (otherwise, ParamSubstitutionException is raised)
        """
        self.debug_print("param_substitute", structure)

        if structure is None:
            return None

        elif isinstance(structure, list):
            return [self.param_substitute(_) for _ in structure]

        elif isinstance(structure, dict):
            # NB: In Python, not everything can be hashed and used as a dictionary key.
            #     Perhaps we should check for such errors ?
            return {self.param_substitute(key): self.param_substitute(value) for (key,value) in structure.items()}

        elif isinstance(structure, numbers.Number):
            return structure

        elif isinstance(structure, str):

            # We handle the substitution differently if there is a single reference as we can avoid forcing the result to be a string

            if structure[:6] == '#expr(' and structure[-6:] == ')expr#' and structure.count('#expr(', 6, -6) == 0 and structure.count(')expr#', 6, -6) == 0:
                return self.subst_one_hashpair(structure[1:-1], True)

            if structure[0] == '#' and structure[-1] == '#' and structure.count('#', 1, -1) == 0:
                if len(structure) <= 2:
                    return structure
                return self.subst_one_hashpair(structure[1:-1], False)

            # Fallback to the default parser: all pairs of hashes are substituted
            return self.subst_all_hashpairs(structure, lambda middle_param: self.subst_one_hashpair(middle_param, False) )

        else:
            raise ParamSubstitutionException(structure)


    def subst_all_hashpairs(self, structure, callback):
        """
        Parse "structure" and replace all the pairs of hashes by the result of calling callback() on the pair content
        #expr()expr# are treated differently by calling subst_one_hashpair()
        The result is a string (like structure)
        """
        self.debug_print("subst_all_hashpairs", structure)
        
        # Allow a single literal hash
        if structure.count("#") == 1:
            return structure
        
        result = []
        while True:
            (head,_,tmp) = structure.partition('#')
            result.append(head)
            if _ != '#':
                return ''.join(result)
            if tmp.startswith('expr('):
                i = tmp.find(')expr#')
                if i == -1:
                    raise SyntaxError("Unmatched '#expr(' token")
                val = self.subst_one_hashpair(tmp[:i+5], True)
                tail = tmp[i+6:]
            else:
                (middle_param,_,tail) = tmp.partition('#')
                if _ != '#':
                    raise SyntaxError("Unmatched '#' token")
                if middle_param == '':
                    val = '##'
                else:
                    val = callback(middle_param)
            result.append(str(val))
            structure = tail


    def subst_one_hashpair(self, inside_hashes, is_expr):
        """
        Run the parameter substitution for a single pair of hashes.
        Here, we only need to handle #expr()expr#, #func:params# and #param_name#
        as each condition has been parsed in the other methods
        """
        self.debug_print("subst_one_hashpair", inside_hashes, is_expr)

        # Keep track of the substitutions we've made to detect loops
        if inside_hashes in self.substitution_in_progress:
            raise ParamInfiniteLoopException(inside_hashes, self.substitution_in_progress)
        self.substitution_in_progress[inside_hashes] = 1

        # We ask the caller to provide the is_expr tag to avoid checking the string again for the presence of the "expr" tokens
        if is_expr:
            s = self.subst_all_hashpairs(inside_hashes[5:-5].strip(), 'self.internal_get_param("{0}")'.format)
            val = eval(s)

        elif ':' in inside_hashes:
            (func_name,_,parameters) = inside_hashes.partition(':')
            try:
                f = eval(func_name)
            except:
                raise SyntaxError("Unknown method: " + func_name)
            if callable(f):
                if parameters:
                    val = f(self.internal_get_param(parameters))
                else:
                    val = f()
            else:
                raise SyntaxError(func_name + " is not callable")

        else:
            val = self.internal_get_param(inside_hashes)

        del self.substitution_in_progress[inside_hashes]
        return val


class ParamContainerTestExceptions(unittest.TestCase):

    def test_infinite_loops(self):
        with self.assertRaises(ParamInfiniteLoopException):
            ParamContainer({'a': '#b#', 'b': '#a#'}).get_param('a')

    def test_missing_param(self):
        with self.assertRaises(KeyError):
            ParamContainer({'a': 3}).get_param('b')

    def test_param_must_be_string(self):
        with self.assertRaises(ParamNameException):
            ParamContainer({'a': 3}).get_param(0)


class ParamContainerTestSubstitutions(unittest.TestCase):

    # Type to clarify seed_params
    TestParamEntry = collections.namedtuple('TestParamEntry', ['name', 'seed_value', 'eval_value'])

    # Test data
    seed_params_list = (
        TestParamEntry('alpha', 2, 2),
        TestParamEntry('beta', 5, 5),
        TestParamEntry('delta', '#expr( #alpha#*#beta# )expr#', 10),
        TestParamEntry('epsilon', 'alpha#beta', 'alpha#beta'),  # Single hash -> no substitution

        TestParamEntry('gamma', [10, 20, 33, 15], [10, 20, 33, 15]),
        TestParamEntry('gamma_prime', '#expr( #gamma# )expr#', [10, 20, 33, 15]),
        TestParamEntry('gamma_second', '#expr( list(#gamma#) )expr#', [10, 20, 33, 15]),

        TestParamEntry('age', {'Alice': 17, 'Bob': 20, 'Chloe': 21}, {'Alice': 17, 'Bob': 20, 'Chloe': 21}),
        TestParamEntry('age_prime', '#expr( #age# )expr#', {'Alice': 17, 'Bob': 20, 'Chloe': 21}),
        TestParamEntry('age_second', '#expr( dict(#age#) )expr#', {'Alice': 17, 'Bob': 20, 'Chloe': 21}),

        TestParamEntry('csv', '[123,456,789]', '[123,456,789]'),
        TestParamEntry('csv_prime', '#expr( #csv# )expr#', '[123,456,789]'),
        TestParamEntry('listref', '#expr( eval(#csv#) )expr#', [123, 456, 789]),

        TestParamEntry('null', None, None),
        TestParamEntry('ref_null', '#null#', None),
        TestParamEntry('ref2_null', '#expr( #null# )expr#', None),
        TestParamEntry('ref3_null', '#alpha##null##beta#', '2None5'),
    )
    seed_params_dict = {p.name: p.seed_value for p in seed_params_list}

    def setUp(self):
        self.params = ParamContainer(self.seed_params_dict)

    def assertSubstitution(self, param_string, expected_value, msg):
        """Helper method to execute the substitution and check the result"""
        value = self.params.substitute_string(param_string)
        self.assertEqual(value, expected_value, msg)

    def test_values(self):
        for p in self.seed_params_list:
            self.assertEqual(self.params.get_param(p.name), p.eval_value, p.name + " can be retrieved")

    def test_numbers(self):
        self.assertSubstitution(
            '#alpha# and another: #beta# and again one: #alpha# and the other: #beta# . Their product: #delta#',
            '2 and another: 5 and again one: 2 and the other: 5 . Their product: 10',
            'Scalar substitutions'
        )

    def test_lists(self):
        self.assertSubstitution(
            '#gamma#',
            [10, 20, 33, 15],
            'gamma not stringified'
        )
        self.assertSubstitution(
            '#expr( #gamma#  )expr#',
            [10, 20, 33, 15],
            'expr-gamma not stringified'
        )
        self.assertSubstitution(
            '#expr( "~".join([str(_) for _ in sorted(#gamma#)])  )expr#',
            '10~15~20~33',
            'gamma stringification'
        )
        self.assertSubstitution(
            '#expr( "~".join([str(_) for _ in sorted(#gamma_prime#)])  )expr#',
            '10~15~20~33',
            'gamma_prime stringification'
        )

    def test_dictionaries(self):
        self.assertSubstitution(
            '#age#',
            {'Alice': 17, 'Bob': 20, 'Chloe': 21},
            'age not stringified'
        )
        self.assertSubstitution(
            '#expr( #age# )expr#',
            {'Alice': 17, 'Bob': 20, 'Chloe': 21},
            'age not stringified'
        )
        self.assertSubstitution(
            '#expr( " and ".join(["{0} is {1} years old".format(p,a) for (p,a) in sorted(#age#.items())]) )expr#',
            'Alice is 17 years old and Bob is 20 years old and Chloe is 21 years old',
            'complex fold of age'
        )
        self.assertSubstitution(
            '#expr( " and ".join(["{0} is {1} years old".format(p,a) for (p,a) in sorted(#age_prime#.items())]) )expr#',
            'Alice is 17 years old and Bob is 20 years old and Chloe is 21 years old',
            'complex fold of age_prime'
        )

    def test_maths_methods(self):
        self.assertSubstitution(
            '#expr( sum(#gamma#) )expr#',
            78,
            'sum(gamma)'
        )
        self.assertSubstitution(
            '#expr( min(#gamma#) )expr#',
            10,
            'min(gamma)'
        )
        self.assertSubstitution(
            '#expr( max(#gamma#) )expr#',
            33,
            'max(gamma)'
        )

    def test_indexes(self):
        self.assertSubstitution(
            '#expr( #age#["Alice"]+max(#gamma#)+#listref#[0] )expr#',
            173,
            'adding indexed and keyed values'
        )

    def test_param_modification(self):
        # Force the substitution of these parameters
        self.params.get_param('gamma')
        self.params.get_param('gamma_prime')
        self.params.get_param('gamma_second')
        # Modify gamma
        self.params.get_param('gamma').append("val0")
        # Only gamma and gamma_prime should be modified
        # because they are the same reference.
        # gamma_second is a copy made before the edition
        # so should still have the initial value.
        self.assertEqual(
            self.params.get_param('gamma'),
            [10, 20, 33, 15, 'val0'],
            'gamma'
        )
        self.assertEqual(
            self.params.get_param('gamma_prime'),
            [10, 20, 33, 15, 'val0'],
            'gamma_prime'
        )
        self.assertEqual(
            self.params.get_param('gamma_second'),
            [10, 20, 33, 15],
            'gamma_second'
        )

