/*
 * Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
 * Copyright [2016-2024] EMBL-European Bioinformatics Institute
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
import java.lang.reflect.InvocationTargetException;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class Utils {

	public static BaseRunnable findRunnable(String runnableName)
	              throws ClassNotFoundException, NoSuchMethodException, InstantiationException, IllegalAccessException, InvocationTargetException {

		Logger log = LoggerFactory.getLogger(Utils.class);
		log.info("Instantiating runnable module " + runnableName);
		Class<?> clazz = Class.forName(runnableName);
		if (!BaseRunnable.class.isAssignableFrom(clazz)) {
			log.error("Class " + runnableName + " must extend " + BaseRunnable.class.getName());
			System.exit(2);
		}
		Constructor<?> ctor = clazz.getConstructor();
		return (BaseRunnable) (ctor.newInstance());
	}

}
