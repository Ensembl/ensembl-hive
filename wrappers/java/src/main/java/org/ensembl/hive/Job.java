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

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Bean wrapping information about a job
 * 
 * @author dstaines
 *
 */
public class Job {
	
	private final transient ObjectMapper mapper = new ObjectMapper();
	
	private final Logger log = LoggerFactory.getLogger(this.getClass());

	private static final String INPUT_ID_KEY = "input_id";

	private static final String DB_ID_KEY = "dbID";

	private static final String RETRY_COUNT_KEY = "retry_count";

	private static final String PARAMETERS_KEY = "parameters";

	private final ParamContainer parameters;
	private final int retryCount;
	private final int dbID;
	private final String inputId;

	private boolean autoflow = true;
	private boolean lethalForWorker = false;
	private boolean transientError = true;
	private boolean complete = false;

	public Job(Map<String, Object> jobParams) {
		log.debug("Building job with params with "+String.valueOf(jobParams.get(PARAMETERS_KEY)));
		this.parameters = new ParamContainer(
				(Map<String, Object>) (jobParams.get(PARAMETERS_KEY)));;
		this.retryCount = Double.valueOf(
				jobParams.get(RETRY_COUNT_KEY).toString()).intValue();
		this.dbID = Double.valueOf(jobParams.get(DB_ID_KEY).toString())
				.intValue();
		this.inputId = (String) (jobParams.get(INPUT_ID_KEY));
	}

	public Job(ParamContainer parameters, int retryCount, int dbID,
			String inputId) {
		super();
		this.parameters = parameters;
		this.retryCount = retryCount;
		this.dbID = dbID;
		this.inputId = inputId;
	}

	public int getDbID() {
		return dbID;
	}

	public String getInputId() {
		return inputId;
	}

	public ParamContainer getParameters() {
		return parameters;
	}

	public int getRetryCount() {
		return retryCount;
	}

	public boolean isAutoflow() {
		return autoflow;
	}

	public void setAutoflow(boolean autoflow) {
		this.autoflow = autoflow;
	}

	public boolean isLethalForWorker() {
		return lethalForWorker;
	}

	public void setLethalForWorker(boolean lethalForWorker) {
		this.lethalForWorker = lethalForWorker;
	}

	public boolean isTransientError() {
		return transientError;
	}

	public void setTransientError(boolean transientError) {
		this.transientError = transientError;
	}

	public String toString() {
		try {
			return mapper.writeValueAsString(this);
		} catch (JsonProcessingException e) {
			throw new RuntimeException("Could not write job as JSON", e);
		}
	}

	public boolean isComplete() {
		return complete;
	}

	public void setComplete(boolean complete) {
		this.complete = complete;
	}

	/**
	 * Returns the value of the parameter "param_name" or raises an exception if
	 * anything wrong happens. The exception is marked as non-transient.
	 * 
	 * @param paramName The name of the parameter
	 * @return          The value of the parameter
	 */
	public Object paramRequired(String paramName) {
		boolean e = isTransientError();
		setTransientError(false);
		Object v = getParameters().getParam(paramName);
		if (v == null) {
			throw new NullParamException(paramName);
		}
		setTransientError(e);
		return v;
	}
}
