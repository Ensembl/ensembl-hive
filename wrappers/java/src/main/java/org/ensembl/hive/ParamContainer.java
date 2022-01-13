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

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Set;
import java.util.stream.Collectors;

import org.apache.commons.lang3.StringUtils;

/**
 * Class for handling eHive parameter expansions. Does not currently support
 * code evaluation in the same way Perl and Python do
 * 
 * @author dstaines
 *
 */
public class ParamContainer {

	private static final String EXPR_END = ")expr#";
	private static final String EXPR_START = "#expr(";
	private final Map<String, Object> unsubParameters;
	private final Map<String, Object> params = new HashMap<>();
	// track substitution to ensure we don't get into loops
	private final Set<String> subInProgress = new HashSet<>();

	public ParamContainer(Map<String, Object> unsubParameters) {
		this.unsubParameters = unsubParameters;
	}

	/**
	 * Getter. Performs the parameter substitution and return the value of a parameter
	 * 
	 * @param paramName The name of the parameter
	 * @return          The (substituted) value of this parameter
	 */
	public Object getParam(String paramName) {
		validateParamName(paramName);
		return getParamRecurse(paramName);
	}

	/**
	 * Equivalent of getParam that assumes "param_name" is a valid parameter
	 * name and hence, doesn't have to raise ParamNameException
	 * 
	 * @param paramName The name of the parameter
	 * @return          The (substituted) value of this parameter
	 */
	private Object getParamRecurse(String paramName) {
		if (!params.containsKey(paramName)) {
			Object value = paramSubstitute(unsubParameters.get(paramName));
			params.put(paramName, value);
			return value;
		} else {
			return params.get(paramName);
		}
	}

	public Map<String, Object> getParams() {
		return params;
	}

	public Map<String, Object> getUnsubParameters() {
		return unsubParameters;
	}

	/**
	 * Returns a boolean. It checks both substituted and unsubstituted
	 * parameters
	 * 
	 * @param paramName The name of the parameter
	 * @return          Whether there is a parameter with this name
	 */
	public boolean hasParam(String paramName) {
		validateParamName(paramName);
		return params.containsKey(paramName)
				|| unsubParameters.containsKey(paramName);
	}

	private Object paramSubstitute(Object input) {
		if (input == null) {
			return null;
		}
		Class<? extends Object> clazz = input.getClass();
		if (List.class.isAssignableFrom(clazz)) {
			// perform substitution on each member in the list
			return ((List<Object>) input).stream().map(o -> paramSubstitute(o))
					.collect(Collectors.toList());
		} else if (Map.class.isAssignableFrom(clazz)) {
			// substitute keys and values for each entry in set
			return ((Map) input)
					.entrySet()
					.stream()
					.collect(
							Collectors.toMap(
									entry -> paramSubstitute(((Entry) entry)
											.getKey()),
									entry -> paramSubstitute(((Entry) entry)
											.getValue())));
		} else if (String.class.isAssignableFrom(clazz)) {
			String param = (String) input;
			// check if it is a single expression statement
			if (param.startsWith(EXPR_START) && param.endsWith(EXPR_END)
					&& StringUtils.countMatches(param, EXPR_START) == 1
					&& StringUtils.countMatches(param, EXPR_END) == 1) {
				// return substituteOneHashPair(paramSub,true);
				throw new UnsupportedOperationException(
						"#expr expansion not currently supported");
			} else if (param.startsWith("#") && param.endsWith("#")
					&& StringUtils.countMatches(param, "#") == 1) {
				if (param.length() <= 2) {
					return input;
				} else {
					String paramSub = param.substring(1, param.length() - 1);
					return substituteOneHashPair(paramSub, false);
				}
			} else {
				return substituteAllHashPairs(param);
			}
		} else if (Number.class.isAssignableFrom(clazz)) {
			return input;
		} else {
			throw new ParamSubstitutionException("Cannot substitute " + input);
		}
	}

	/**
	 * Setter. Set the new value of a parameter
	 * 
	 * @param paramName The name of the parameter
	 * @param value     Its new value
	 */
	public void setParam(String paramName, Object value) {
		validateParamName(paramName);
		params.put(paramName, value);
	}

	private Object substituteAllHashPairs(String input) {
		// TODO: needs to be implemented as well
		return input;
	}

	/**
	 * Run the parameter substitution for a single pair of hashes. We can only
	 * currently handle #param# - expr and functions require dynamic evaluation
	 * of code
	 * 
	 * @param input     The string that has to be substituted
	 * @param isExpr	Whether @input is an expression that has to be evaluated (currently ignored)
	 * @return          The result of the substitution
	 */
	private Object substituteOneHashPair(String input, boolean isExpr) {

		// check if we are already handling this
		if (subInProgress.contains(input)) {
			throw new ParamInfiniteLoopException(input);
		}

		subInProgress.add(input);

		// TODO figure out a way to deal with expr
		// the only thing we can sanely deal with in Java is straight name
		// replacement
		Object val = getParamRecurse(input);

		subInProgress.remove(input);

		return val;
	}

	private void validateParamName(String paramName) {
		if (paramName == null || paramName.length() == 0) {
			throw new ParamNameException("Empty paramName " + paramName);
		}
	}

}
