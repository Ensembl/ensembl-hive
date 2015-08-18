package org.ensembl.hive.longmult;

import java.io.File;
import java.io.IOException;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.ensembl.hive.BaseRunnable;
import org.ensembl.hive.Job;
import org.slf4j.LoggerFactory;

public class DigitFactory extends BaseRunnable {

	public static final String SUB_TASKS = "sub_tasks";
	public static final String TAKE_TIME = "take_time";
	public static final String A_MULTIPLIER = "a_multiplier";
	public static final String B_MULTIPLIER = "b_multiplier";
	public static final String DIGIT = "digit";
	public static final String PARTIAL_PRODUCT = "partial_product";

	public DigitFactory(File inputFile, File outputFile) throws IOException {
		super(inputFile, outputFile);
	}

	@Override
	protected Map<String, Object> getParamDefaults() {
		return toMap(TAKE_TIME, 0);
	}

	@Override
	protected void fetchInput(Job job) {
		getLog().info("Fetching b_multiplier");
		String bMultiplier = numericParamToStr(job.paramRequired(B_MULTIPLIER)
				.toString());
		getLog().info("b_multiplier=" + bMultiplier);
		// split the multiplier by digits and store each digit in a hash
		List<Map<String, Object>> subTasks = Arrays
				.asList(bMultiplier.split("(?!^)")).stream()
				.filter(c -> c.matches("[2-9]")).map(c -> toMap(DIGIT, c))
				.collect(Collectors.toList());
		getLog().info("subTasks=" + subTasks);
		job.getParameters().setParam(SUB_TASKS, subTasks);
	}

	@Override
	protected void run(Job job) {
		sleep(job);
	}

	protected static void sleep(Job job) {
		try {
			Long time = numericParamToLong(job.getParameters().getParam(
					TAKE_TIME));
			LoggerFactory.getLogger(DigitFactory.class.getPackage().getName())
					.info("Sleeping for " + time + "s");
			Thread.sleep(1000 * time);
		} catch (InterruptedException e) {
			// swallow exception
		}
	}

	@Override
	protected void writeOutput(Job job) {
		Object subTasks = job.getParameters().getParam(SUB_TASKS);
		getLog().info("Writing output " + subTasks + " on branch 2");
		dataflow(job.getParameters(), (List)subTasks, 2);
	}

	/**
	 * Helper method for dealing with numbers that have been passed around
	 * through JSON and may be of different types
	 * 
	 * @param param
	 * @return
	 */
	public static Long numericParamToLong(Object param) {
		if (Long.class.isAssignableFrom(param.getClass())) {
			return (Long) param;
		} else if (Integer.class.isAssignableFrom(param.getClass())) {
			return Long.valueOf((Integer) param);
		} else if (Double.class.isAssignableFrom(param.getClass())) {
			return ((Double) param).longValue();
		} else if (String.class.isAssignableFrom(param.getClass())) {
			return Long.parseLong((String) param);
		} else {
			throw new UnsupportedOperationException(
					"Cannot extract integer from object of type "
							+ param.getClass());
		}
	}

	public static String numericParamToStr(Object param) {
		if (Double.class.isAssignableFrom(param.getClass())) {
			// cast to int first
			return String.valueOf(((Double) param).longValue());
		} else {
			return String.valueOf(param);
		}
	}

}
