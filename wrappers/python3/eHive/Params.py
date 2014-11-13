
import sys
import numbers
import collections

__doc__ = """
This module is an implementation of eHive's Param module.
It defines ParamContainer which is an attribute of BaseRunnable
and not its base class as in eHive's class hierarchy.
All the specific warnings and exceptions inherit from ParamWarning
and ParamException.
"""


class ParamWarning(Warning):
    """Used by Process.BaseRunnable"""
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


class ParamContainer(object):

    def __init__(self, unsubstituted_params, debug=False):
        """Constructor. "unsubstituted_params" is a dictionary"""
        self._unsubstituted_param_hash = unsubstituted_params
        self._param_hash = {}
        self.debug = debug


    # Public methods
    #################

    def set_param(self, param_name, value):
        """Setter. Returns the new value"""
        if not self.validate_parameter_name(param_name):
            raise ParamNameException(param_name)
        self._param_hash[param_name] = value
        return value

    def get_param(self, param_name):
        """Getter. Performs the parameter substitution"""
        if not self.validate_parameter_name(param_name):
            raise ParamNameException(param_name)
        self._substitution_in_progress = collections.OrderedDict()
        try:
            return self.internal_get_param(param_name)
        except (KeyError, SyntaxError, ParamException) as e:
            # To hide the part of the stack that is in ParamContainer
            raise type(e)(*e.args) from None

    def has_param(self, param_name):
        """Returns a boolean. It checks both substituted and unsubstituted parameters"""
        if not self.validate_parameter_name(param_name):
            raise ParamNameException(param_name)
        return (param_name in self._param_hash) or (param_name in self._unsubstituted_param_hash)


    # Private methods
    ##################
    def validate_parameter_name(self, param_name):
        return isinstance(param_name, str) and (param_name != '')

    def debug_print(self, *args, **kwargs):
        if self.debug:
            print(*args, **kwargs)

    # Parameters of _internal_get_param are known to be valid
    def internal_get_param(self, param_name):
        self.debug_print("internal_get_param", param_name)
        if param_name not in self._param_hash:
            x = self._unsubstituted_param_hash[param_name]
            self._param_hash[param_name] = self.param_substitute(x)
        return self._param_hash[param_name]


    """
    Take any structure and replace the pairs of hashes with the values of the parameters / expression they represent
    Compatible types: numbers, strings, lists, dictionaries (otherwise, ParamSubstitutionException is raised)
    """
    def param_substitute(self, structure):
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
        self.debug_print("subst_all_hashpairs", structure)
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
        self.debug_print("subst_one_hashpair", inside_hashes, is_expr)

        # Keep track of the substitutions we've made to detect loops
        if inside_hashes in self._substitution_in_progress:
            raise ParamInfiniteLoopException(inside_hashes, self._substitution_in_progress)
        self._substitution_in_progress[inside_hashes] = 1

        # We ask the caller to provide the is_expr tag to avoid checking the string again for the presence of the "expr" tokens
        if is_expr:
            s = self.subst_all_hashpairs(inside_hashes[5:-5].strip(), lambda middle_param: 'self.internal_get_param("{0}")'.format(middle_param))
            return eval(s)

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

        del self._substitution_in_progress[inside_hashes]
        return val



if __name__ == '__main__':

    seed_params = {
        'alpha' : 2,
        'beta' : 5,
        'delta' : '#expr( #alpha#*#beta# )expr#',

        'gamma' : [10,20,33,15],
        'gamma_prime' : '#expr( list(#gamma#) )expr#',

        'age' : { 'Alice' : 17, 'Bob' : 20, 'Chloe' : 21},
        'age_prime' : '#expr( dict(#age#) )expr#',

        'csv' : '[123,456,789]',
        'listref' : '#expr( eval(#csv#) )expr#',

        'null' : None,
        'ref_null' : '#null#',
        'ref2_null' : '#expr( #null# )expr#',
        'ref3_null' : '#alpha##null##beta#',
    }

    p = ParamContainer(seed_params, True)
    p.get_param('null')
    p.get_param('ref_null')
    p.get_param('ref2_null')
    try:
        p.get_param('ppppppp')
    except KeyError as e:
        print("KeyError raised")
    else:
        print("KeyError NOT raised")

    try:
        p.get_param(0) # should raise ParamNameException
    except ParamNameException as e:
        print("ParamNameException raised")
    else:
        print("ParamNameException NOT raised")

    try:
        ParamContainer({'a': '#b#', 'b': '#a#'}, True).get_param('a')
    except ParamInfiniteLoopException as e:
        print("ParamInfiniteLoopException raised")
    else:
        print("ParamInfiniteLoopException NOT raised")


    print('All the parameters')
    for (key,value) in seed_params.items():
        print("\t>", key)
        x = p.get_param(key)
        print("\t=", x, type(x))
        #print("\t'{0}' is '{1}' in the seeded hash, and '{2}' as a result of p.param()".format(key, value, p.get_param(key)))

    print("Numbers")
    print(p.param_substitute( "\tSubstituting one scalar: #alpha# and another: #beta# and again one: #alpha# and the other: #beta# . Their product: #delta#" ));

    print("Lists")
    print(p.param_substitute( "\tdefault stringification of gamma: #gamma#" ));
    print(p.param_substitute( "\texpr-stringification gamma: #expr( #gamma#  )expr#" ));
    print(p.param_substitute( "\tcomplex join of gamma: #expr( '~'.join([str(_) for _ in sorted(#gamma#)])  )expr#" ));
    print(p.param_substitute( "\tcomplex join of gamma_prime: #expr( '~'.join([str(_) for _ in sorted(#gamma_prime#)])  )expr#" ));

    print("Global methods")
    print(p.param_substitute( "\tsum(gamma) -> #expr( sum(#gamma#) )expr#" ));
    print(p.param_substitute( "\tmin(gamma) -> #expr( min(#gamma#) )expr#" ));
    print(p.param_substitute( "\tmax(gamma) -> #expr( max(#gamma#) )expr#" ));
    print(p.param_substitute( "\tdir() -> #expr( dir() )expr#" ));
    print(p.param_substitute( "\tdir() -> #dir:#" ));

    print("Dictionaries")
    print(p.param_substitute( '\tdefault stringification of age: #age#'))
    print(p.param_substitute( '\texpr-stringification of age: #expr( #age# )expr#'))
    print(p.param_substitute( '\tcomplex fold of age: #expr( "\t".join(["{0} is {1} years old".format(p,a) for (p,a) in #age#.items()]) )expr#'));
    print(p.param_substitute( '\tcomplex fold of age_prime: #expr( "\t".join(["{0} is {1} years old".format(p,a) for (p,a) in #age_prime#.items()]) )expr#'));

    print("With indexes")
    print(p.param_substitute( '\tadding indexed values: #expr( #age#["Alice"]+max(#gamma#)+#listref#[0] )expr#'));

    print("Evaluation")
    print("\tcsv =", p.get_param('csv'), "(it is a {0}".format(type(p.get_param('csv'))), ')')
    l = p.param_substitute( '#listref#' )
    print("\tlist reference produced by doing expr() on csv: ", l)


