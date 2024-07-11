# See the NOTICE file distributed with this work for additional information
#   regarding copyright ownership.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#       http://www.apache.org/licenses/LICENSE-2.0
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
"""Unit testing of `ensembl.hive.rest` module.

The unit testing is divided into one test class per submodule/class found in this module, and one test method
per public function/class method.

Typical usage example::

    $ pytest test_rest.py

"""

import unittest

import requests_mock

import eHive
from eHive.rest import HiveRESTClient


class TestHiveRESTClient(unittest.TestCase):
    """Tests `eHive.rest.HiveRESTClient`"""

    def test_ApiCall200(self):
        """Tests an `HiveRESTClient` eHive runnable"""
        mockURL = "http://ensembl.local/api/"
        mockJSON = {"data": "content"}
        with requests_mock.Mocker() as m:
            m.get(mockURL, json=mockJSON)
            eHive.tests.testRunnable(
                self,
                HiveRESTClient,
                {
                    "endpoint": mockURL,
                },
                [
                    eHive.tests.DataflowEvent({"rest_response": mockJSON}, branch_name_or_code=1),
                ],
            )
