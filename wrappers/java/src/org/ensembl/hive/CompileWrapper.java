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
