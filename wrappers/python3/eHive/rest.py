# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""REST API to interact with eHive pipelines."""

__all__ = ["logger", "HiveRESTClient"]

import contextlib
import logging

import requests
from requests.adapters import HTTPAdapter
from urllib3 import Retry

from .process import BaseRunnable


logger = logging.getLogger(__name__)


class HiveRESTClient(BaseRunnable):
    """
    Basic Root class to interact with random REST API in a Hive Pipeline.
    Allow random call to an API from a Ensembl-Hive Pipeline config file
    TODO: Authentication, Secured, Files upload.

    """

    available_method = ("post", "get", "put", "patch")

    def param_defaults(self):
        """
        Default parameter set
        :return: dict
        """
        return {
            "payload": {},
            "headers": {"content-type": "application/json; charset=utf8"},
            "files": [],
            "method": "get",
            "timeout": 1,
            "retry": 3,
            "check_status": True,
            "status_retry": list(Retry.RETRY_AFTER_STATUS_CODES),
            "method_retry": list(Retry.DEFAULT_ALLOWED_METHODS),
        }

    def _open_session(self):
        """Set up an ``HTTPAdapter`` to allow API call retries in case of Networks failures or remote API
        unavailability.

        Returns:
            A new ``requests.Session`` object
        """
        adapter = HTTPAdapter(
            max_retries=Retry(
                total=self.param("retry"),
                status_forcelist=self.param("status_retry"),
                allowed_methods=self.param("method_retry"),
            )
        )
        http = requests.Session()
        http.mount("https://", adapter)
        http.mount("http://", adapter)
        return http

    def _close_session(self, session):
        """
        Close all potential remaining connections in current Session
        :return None
        """
        session.close()

    @contextlib.contextmanager
    def _session_scope(self):
        """Ensure HTTP session is closed after processing code"""
        session = self._open_session()
        logger.debug("HTTP Session opened %s", session)
        try:
            yield session
        except requests.HTTPError as e:
            message = f"Error performing request {self.param('endpoint')}: {e.strerror}"
            self.warning(message)
            raise e
        finally:
            logger.debug("Closing session")
            self._close_session(session)

    def fetch_input(self):
        """
        Basic call to request parameters specified in pipeline parameters
        Return response received.
        """
        with self._session_scope() as http:
            response = http.request(
                self.param_required("method"),
                self.param_required("endpoint"),
                headers=self.param("headers"),
                files=self.param("files"),
                data=self.param("payload"),
                timeout=self.param("timeout"),
            )
            self.param("response", response)

    def write_output(self):
        """
        Added code to process the response received from api call.
        For easiness, this is supposed to be the only method needing override to process API HTTP response
        :param response:
        :return:
        """
        self.dataflow({"rest_response": self.param("response").json()}, 1)
