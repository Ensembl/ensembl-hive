package org.ensembl.hive;

import java.io.File;
import java.lang.reflect.Constructor;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Main class for running a hive worker in Java
 * 
 * @author dstaines
 *
 */
public class Wrapper {

	public static void main(String[] args) throws Exception {

		System.setProperty(org.slf4j.impl.SimpleLogger.DEFAULT_LOG_LEVEL_KEY,
				"TRACE");

		Logger log = LoggerFactory.getLogger(Wrapper.class);

		if (args.length != 3) {
			log.error("Usage: java org.ensembl.hive.Wrapper <Runnable class> <input pipe> <output pipe>");
			System.exit(1);
		}
		log.info("Instantiating runnable module " + args[0]);
		Class<?> clazz = Class.forName(args[0]);
		if (!BaseRunnable.class.isAssignableFrom(clazz)) {
			log.error("Class " + args[0] + " must extend "
					+ BaseRunnable.class.getName());
			System.exit(2);
		}
		Constructor<?> ctor = clazz.getConstructor(File.class, File.class);
		log.debug("Initializing runnable module " + clazz.getName() + " from "
				+ args[1] + "/" + args[2]);
		BaseRunnable runnable = (BaseRunnable) (ctor.newInstance(new File(
				args[1]), new File(args[2])));
		log.info("Executing fetchInput");
		runnable.fetchInput();
		log.info("Executing run");
		runnable.run();
		log.info("Executing writeOutput");
		runnable.writeOutput();
		log.info("Execution complete");
	}

}
