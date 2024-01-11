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

package org.ensembl.hive.longmult;

import static org.ensembl.hive.longmult.DigitFactory.A_MULTIPLIER;
import static org.ensembl.hive.longmult.DigitFactory.PARTIAL_PRODUCT;
import static org.ensembl.hive.longmult.DigitFactory.TAKE_TIME;
import static org.ensembl.hive.longmult.DigitFactory.sleep;
import static org.ensembl.hive.longmult.DigitFactory.numericParamToLong;

import java.io.FileDescriptor;
import java.io.IOException;
import java.util.Arrays;
import java.util.Map;

import org.apache.commons.lang3.StringUtils;
import org.ensembl.hive.BaseRunnable;
import org.ensembl.hive.Job;

/**
 * Runnable to multiply a number by a digit
 * 
 * @author dstaines
 *
 */
public class PartMultiply extends BaseRunnable {

	@Override
	protected Map<String, Object> getParamDefaults() {
		return toMap(TAKE_TIME, 0);
	}

	@Override
	protected void fetchInput(Job job) {
	}

	@Override
	protected void run(Job job) {
		Long aMultiplier = numericParamToLong(job.paramRequired(A_MULTIPLIER));
		getLog().debug("a_multiplier = " + aMultiplier);
		Long digit = numericParamToLong(job.paramRequired("digit"));
		getLog().debug("digit = " + digit);
		String recMult = recMultiply(aMultiplier.toString(), digit.toString(),
				"0");
		job.getParameters().setParam("partial_product", Long.parseLong(recMult));
		sleep(job);
	}

	private String recMultiply(String aMultiplier, String digit, String carry) {

		getLog().debug("Rec Mult " + aMultiplier + "/" + digit + "/" + carry);
		if (StringUtils.isEmpty(aMultiplier)) {
			if (carry == null) {
				getLog().debug("returning empty");
				return StringUtils.EMPTY;
			} else {
				getLog().debug("returning carry " + carry);
				return carry;
			}
		}

		String prefix;
		String lastDigit; 
		if (aMultiplier.length() > 1) {
			lastDigit = aMultiplier.substring(aMultiplier.length() - 1);
			prefix = aMultiplier.substring(0, aMultiplier.length() - 1);
		} else {
			prefix = StringUtils.EMPTY;
			lastDigit = aMultiplier;
		}
		getLog().debug("Prefix = " + prefix + ", lastDigit = " + lastDigit);
		Integer thisProduct = (Integer.parseInt(lastDigit) * Integer
				.parseInt(digit)) + Integer.parseInt(carry);
		Integer thisResult = thisProduct % 10;
		Integer thisCarry = thisProduct / 10;

		getLog().debug(
				"Invoking with " + prefix + "/" + digit + "/" + thisCarry);
		String result = recMultiply(prefix, digit, thisCarry.toString());
		getLog().debug("Got " + result + " - adding " + thisResult);
		result = result + thisResult;
		getLog().debug("Returning " + result);

		return result;
	}

	@Override
	protected void writeOutput(Job job) {
		dataflow(
				job.getParameters(),
				Arrays.asList(toMap(PARTIAL_PRODUCT,
						job.getParameters().getParam(PARTIAL_PRODUCT))), 1);
	}

}
