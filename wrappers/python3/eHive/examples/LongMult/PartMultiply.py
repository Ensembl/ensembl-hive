
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2023] EMBL-European Bioinformatics Institute
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
        self.param('partial_product', rec_multiply(str(a_multiplier), digit, 0))
        time.sleep( self.param('take_time') )


    def write_output(self):
        self.dataflow( { 'partial_product' : self.param('partial_product') }, 1)


def rec_multiply(a_multiplier, digit, carry):
    """Function to multiply a number by a digit"""

    if a_multiplier == '':
        return str(carry) if carry else ''

    prefix = a_multiplier[:-1]
    last_digit = int(a_multiplier[-1])

    this_product = last_digit * digit + carry
    this_result = this_product % 10
    this_carry = this_product // 10

    return rec_multiply(prefix, digit, this_carry) + str(this_result)


