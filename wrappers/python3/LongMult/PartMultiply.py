
import eHive

import time

class PartMultiply(eHive.BaseRunnable):
    """Runnable to multiply a number by a digit"""

    def param_defaults(self):
        return {
            'take_time' : 0
        }


    def run(self):
        a_multiplier = self.param_required('a_multiplier')
        digit = int(self.param_required('digit'))
        self.param('partial_product', _rec_multiply(str(a_multiplier), digit, 0))
        time.sleep( self.param('take_time') )


    def write_output(self):
        self.dataflow( { 'partial_product' : self.param('partial_product') }, 1)


def _rec_multiply(a_multiplier, digit, carry):
    """Function to multiply a number by a digit"""

    if a_multiplier == '':
        return str(carry) if carry else ''

    prefix = a_multiplier[:-1]
    last_digit = int(a_multiplier[-1])

    this_product = last_digit * digit + carry
    this_result = this_product % 10
    this_carry = this_product // 10

    return _rec_multiply(prefix, digit, this_carry) + str(this_result)


