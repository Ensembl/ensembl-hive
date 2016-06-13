package org.ensembl.hive;

import java.io.FileDescriptor;
import java.lang.reflect.Constructor;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import sun.misc.SharedSecrets;

/**
 * Main class for running a hive worker in Java
 * 
 * @author dstaines
 *
 */
public class Wrapper {

	public static void main(String[] args) throws Exception {


		if (args.length != 4) {
			System.err.println("Usage: java org.ensembl.hive.Wrapper <Runnable class> <input pipe> <output pipe> <debug>");
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

		Logger log = LoggerFactory.getLogger(Wrapper.class);
		log.info("Instantiating runnable module " + args[0]);
		Class<?> clazz = Class.forName(args[0]);
		if (!BaseRunnable.class.isAssignableFrom(clazz)) {
			log.error("Class " + args[0] + " must extend "
					+ BaseRunnable.class.getName());
			System.exit(2);
		}
		Constructor<?> ctor = clazz.getConstructor();
//		log.debug("Initializing runnable module " + clazz.getName() + " from " + args[1] + " and " + args[2]);

        FileDescriptor inputDescriptor = new FileDescriptor();
        sun.misc.SharedSecrets.getJavaIOFileDescriptorAccess().set(inputDescriptor, Integer.parseInt(args[1]));

        FileDescriptor outputDescriptor = new FileDescriptor();
        sun.misc.SharedSecrets.getJavaIOFileDescriptorAccess().set(outputDescriptor, Integer.parseInt(args[2]));

		BaseRunnable runnable = (BaseRunnable) (ctor.newInstance());
        runnable.setFileDescriptors(inputDescriptor, outputDescriptor);
		runnable.processLifeCycle();

	}

}
