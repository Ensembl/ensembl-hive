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

package org.ensembl.hive.longmult;

import static org.ensembl.hive.longmult.DigitFactory.A_MULTIPLIER;
import static org.ensembl.hive.longmult.DigitFactory.B_MULTIPLIER;
import static org.ensembl.hive.longmult.DigitFactory.PARTIAL_PRODUCT;
import static org.ensembl.hive.longmult.DigitFactory.TAKE_TIME;
import static org.ensembl.hive.longmult.DigitFactory.sleep;

import java.io.FileDescriptor;
import java.io.IOException;
import java.util.Arrays;
import java.util.Map;

import org.apache.commons.lang3.StringUtils;
import org.ensembl.hive.BaseRunnable;
import org.ensembl.hive.Job;

public class AddTogether extends BaseRunnable {

	@Override
	protected Map<String, Object> getParamDefaults() {
		return toMap(TAKE_TIME, 0, PARTIAL_PRODUCT, DEFAULT_PARAMS);
	}

	@Override
	protected void fetchInput(Job job) {
		Long a_multiplier = numericParamToLong(job.paramRequired(A_MULTIPLIER));
		Map<String, Object> partialProduct = (Map<String, Object>) job
				.getParameters().getParam(PARTIAL_PRODUCT);
		System.out.println(partialProduct);
		partialProduct.put("0", new Long(0));
		partialProduct.put("1", new Long(a_multiplier));
	}

	@Override
	protected void run(Job job) {
		Long b_multiplier = numericParamToLong(job.paramRequired(B_MULTIPLIER));
		Map<String, Object> partialProduct = (Map<String, Object>) job
				.getParameters().getParam(PARTIAL_PRODUCT);
		job.getParameters().setParam("result",
				add_together(b_multiplier.toString(), partialProduct));
		sleep(job);
	}

	private Object add_together(String b_multiplier,
			Map<String, Object> partialProduct) {

		// create accu to write digits to (work out potential length
		int accuLen = 1 + b_multiplier.length()
				+ numericParamToStr(partialProduct.get("1")).length();
		getLog().debug(
				"Adding " + b_multiplier + " to " + partialProduct
						+ ": expected " + accuLen);
		int[] accu = new int[accuLen];
		for (int i = 0; i < accuLen; i++) {
			accu[i] = 0;
		}

		// split and reverse the digits in b_multiplier
		char[] b_digits = StringUtils.reverse(b_multiplier).toCharArray();

		// iterate over each digit in b_digits
		for (int i = 0; i < b_digits.length; i++) {
			// for each digit
			char b_digit = b_digits[i];
			getLog().debug("i=" + i + ", b_digit=" + b_digit);

			// get the corresponding partial product for that digit
			char[] p_digits = StringUtils.reverse(
					numericParamToStr(partialProduct.get(String
							.valueOf(b_digit)))).toCharArray();
			// iterate over digits in the product
			for (int j = 0; j < p_digits.length; j++) {
				char p_digit = p_digits[j];
				getLog().debug(
						"j=" + j + ", p_digit="
								+ Character.getNumericValue(p_digit) + ", i+j="
								+ (i + j));
				// add to accumulator
				getLog().debug("[" + i + "+" + j + "] before=" + accu[i + j]);
				accu[i + j] = accu[i + j] + Character.getNumericValue(p_digit);
				getLog().debug("[" + i + "+" + j + "] after=" + accu[i + j]);
			}
		}
		// do the carrying
		int carry = 0;
		for (int i = 0; i < accu.length; i++) {
			getLog().debug(
					"Dealing with digit " + i + " of " + accu.length + ": "
							+ accu[i] + ", carry=" + carry);
			int val = carry + accu[i];
			accu[i] = val % 10;
			carry = val / 10;
			getLog().debug(
					"Finished dealing with digit " + i + " of " + accu.length
							+ ": " + accu[i] + ", carry=" + carry);
		}

		getLog().debug("result=" + Arrays.toString(accu));
		// turn accumulator array back into a string and reversing it
		StringBuilder sb = new StringBuilder();
		for (int i = accu.length - 1; i >= 0; i--) {
			sb.append(accu[i]);
		}

		return Long.parseLong(sb.toString());
	}

	@Override
	protected void writeOutput(Job job) {
		dataflow(
				job.getParameters(),
				Arrays.asList(toMap("result",
						job.getParameters().getParam("result"))), 1);
	}

}
