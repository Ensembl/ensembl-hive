package org.ensembl.hive.longmult;

import java.io.FileDescriptor;
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

	@Override
	protected Map<String, Object> getParamDefaults() {
		return toMap(TAKE_TIME, 0);
	}

	@Override
	protected void fetchInput(Job job) {
		getLog().debug("Fetching b_multiplier");
		String bMultiplier = numericParamToStr(job.paramRequired(B_MULTIPLIER)
				.toString());
		getLog().debug("b_multiplier=" + bMultiplier);
		// split the multiplier by digits and store each digit in a hash
		List<Map<String, Object>> subTasks = Arrays
				.asList(bMultiplier.split("(?!^)")).stream()
				.filter(c -> c.matches("[2-9]")).distinct().map(c -> toMap(DIGIT, c))
				.collect(Collectors.toList());
		getLog().debug("subTasks=" + subTasks);
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
		getLog().debug("Writing output " + subTasks + " on branch 2");
		dataflow(job.getParameters(), (List)subTasks, 2);
	}

}
