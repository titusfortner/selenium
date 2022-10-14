# Licensed to the Software Freedom Conservancy (SFC) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The SFC licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
import logging
import re
import subprocess
import sys
from pathlib import Path
from typing import Tuple

from selenium.common.exceptions import WebDriverException

logger = logging.getLogger(__name__)


class SeleniumManager:
    """
    Wrapper for getting information from the Selenium Manager binaries.
    """

    @staticmethod
    def get_binary() -> Path:
        """
        Determines the path of the correct Selenium Manager binary.
        :Returns: The Selenium Manager executable location
        """
        directory = sys.platform
        if directory == "linux":
            directory = "linux"
        elif directory == "darwin":
            directory = "macos"
        elif directory in ("win32", "cygwin"):
            directory = "windows"

        file = "selenium-manager.exe" if directory == "windows" else "selenium-manager"

        path = Path(__file__).parent.joinpath(directory, file)

        if not path.is_file():
            raise WebDriverException("Unable to obtain Selenium Manager")

        return path

    @staticmethod
    def driver_location(browser: str) -> str:
        """
        Determines the path of the correct driver.
        :Args:
         - browser: which browser to get the driver path for.
        :Returns: The driver path to use
        """
        if browser not in ("chrome", "edge", "firefox"):
            raise WebDriverException("Unable to locate driver associated with browser name: " + browser)

        args = (str(SeleniumManager.get_binary()), "--browser", browser)
        result = SeleniumManager.run(args)
        command = result.split("\t")[-1].strip()
        logger.info("using driver at: " + command)
        return command

    @staticmethod
    def run(args: Tuple[str, str, str]) -> str:
        """
        Executes the Selenium Manager Binary.
        :Args:
         - args: the components of the command being executed.
        :Returns: The log string containing the driver location.
        """
        logger.debug("executing selenium manager with: " + " ".join(args))
        result = subprocess.run(args, stdout=subprocess.PIPE).stdout.decode("utf-8")

        pattern = re.compile("^INFO\t")
        if not pattern.match(result):
            raise WebDriverException("Unsuccessful command executed: " + " ".join(args))

        return result
