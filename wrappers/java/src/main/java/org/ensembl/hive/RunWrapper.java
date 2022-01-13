/*
 * Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
 * Copyright [2016-2022] EMBL-European Bioinformatics Institute
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *      http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.ensembl.hive;

import java.io.FileDescriptor;
import java.lang.reflect.Constructor;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.ensembl.hive.Utils;

/**
 * Main class for running a hive worker in Java
 * 
 * @author dstaines
 *
 */
public class RunWrapper {

	public static void main(String[] args) throws Exception {

		if (args.length != 4) {
			System.err.println("Usage: java org.ensembl.hive.RunWrapper <Runnable class> <input pipe> <output pipe> <debug>");
			System.exit(1);
		}

		int d = 0;
		try {
			d = Integer.parseInt(args[3]);
		} catch (NumberFormatException e) {
			System.err.println("The debug level '" + args[3] + "' is not an integer. Aborting");
			System.exit(1);
		}
		// set the debug level accordingly
		if (d < 0) {
			System.err.println("The debug level must be positive. Aborting");
			System.exit(1);

		} else if (d == 0) {
			System.setProperty(org.slf4j.impl.SimpleLogger.DEFAULT_LOG_LEVEL_KEY, "WARN");

		} else if (d == 1) {
			System.setProperty(org.slf4j.impl.SimpleLogger.DEFAULT_LOG_LEVEL_KEY, "INFO");

		} else if (d == 2) {
			System.setProperty(org.slf4j.impl.SimpleLogger.DEFAULT_LOG_LEVEL_KEY, "DEBUG");

		} else  {
			System.setProperty(org.slf4j.impl.SimpleLogger.DEFAULT_LOG_LEVEL_KEY, "TRACE");

		}

		BaseRunnable runnable = Utils.findRunnable(args[0]);

		Constructor<FileDescriptor> fdctor = FileDescriptor.class.getDeclaredConstructor(Integer.TYPE);
		fdctor.setAccessible(true);
		FileDescriptor inputDescriptor = fdctor.newInstance(Integer.parseInt(args[1]));
		FileDescriptor outputDescriptor = fdctor.newInstance(Integer.parseInt(args[2]));
		fdctor.setAccessible(false);
        runnable.setFileDescriptors(inputDescriptor, outputDescriptor);

		runnable.processLifeCycle();
	}

}
