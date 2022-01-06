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
import java.io.IOException;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.ensembl.hive.BaseRunnable;
import org.ensembl.hive.Job;
import org.slf4j.LoggerFactory;

public class TestRunnable extends BaseRunnable {

	public static final String ALPHA = "alpha";
	public static final String BETA = "beta";
	public static final String GAMMA = "gamma";

	@Override
	protected Map<String, Object> getParamDefaults() {
		return toMap(
		         ALPHA, 37,
		         BETA, 78
		       );
	}

	@Override
	protected void fetchInput(Job job) {
		warning("Fetch the world !", false);
		getLog().info("alpha is", job.paramRequired(ALPHA));
		getLog().info("beta is", job.paramRequired(BETA));
	}

	@Override
	protected void run(Job job) {
		warning("Run the world !", false);
		long s = numericParamToLong(job.getParameters().getParam(ALPHA)) + numericParamToLong(job.getParameters().getParam(BETA));
		getLog().info("set gamma to", s);
		job.getParameters().setParam(GAMMA, s);
	}

	@Override
	protected void writeOutput(Job job) {
		warning("Write to the world !", false);
		getLog().info("gamma is", job.paramRequired(GAMMA));
		dataflow(job.getParameters(), Arrays.asList(toMap("gamma", job.getParameters().getParam(GAMMA))), 2);
	}
}
