/*
 * Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
 * Copyright [2016-2021] EMBL-European Bioinformatics Institute
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

import java.lang.reflect.Constructor;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Main class for running a hive worker in Java
 * 
 * @author dstaines
 *
 */
public class CompileWrapper {

	public static void main(String[] args) throws Exception {


		if (args.length != 1) {
			System.err.println("Usage: java org.ensembl.hive.CompileWrapper <Runnable class>");
			System.exit(1);
		}

		Logger log = LoggerFactory.getLogger(CompileWrapper.class);
		log.info("Instantiating runnable module " + args[0]);
		Class<?> clazz = Class.forName(args[0]);
		if (!BaseRunnable.class.isAssignableFrom(clazz)) {
			log.error("Class " + args[0] + " must extend "
					+ BaseRunnable.class.getName());
			System.exit(2);
		}
		Constructor<?> ctor = clazz.getConstructor();
		BaseRunnable runnable = (BaseRunnable) (ctor.newInstance());
	}

}
