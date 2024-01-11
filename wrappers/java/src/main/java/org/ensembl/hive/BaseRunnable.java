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

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.FileDescriptor;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.Reader;
import java.io.Writer;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Base class implementing the runnable lifecycle
 * 
 * @author dstaines
 *
 */
public abstract class BaseRunnable {

	private static final String BRANCH_NAME_OR_CODE_KEY = "branch_name_or_code";
	private static final String OUTPUT_IDS_KEY = "output_ids";
	private static final String DATAFLOW_TYPE = "DATAFLOW";
	private static final String WORKER_TEMP_DIRECTORY_TYPE = "WORKER_TEMP_DIRECTORY";
	private static final String UNSUBSTITUTED_KEY = "unsubstituted";
	private static final String SUBSTITUTED_KEY = "substituted";
	private static final String PARAMS_KEY = "params";
	private static final String JOB_KEY = "job";
	private static final String COMPLETE_KEY = "complete";
	private static final String IS_ERROR_KEY = "is_error";
	private static final String MESSAGE_KEY = "message";
	private static final String WARNING_KEY = "WARNING";
	private static final String TRANSIENT_ERROR_KEY = "transient_error";
	private static final String LETHAL_FOR_WORKER_KEY = "lethal_for_worker";
	private static final String AUTOFLOW_KEY = "autoflow";
	private static final String EXECUTE_WRITES_KEY = "execute_writes";
	private static final String DEBUG_KEY = "debug";
	private static final String INPUT_JOB_KEY = "input_job";
	private static final String RESPONSE_KEY = "response";
	private static final String EVENT_KEY = "event";
	private static final String CONTENT_KEY = "content";
	private static final String VERSION_TYPE = "VERSION";
	private static final String PARAM_DEFAULT_TYPE = "PARAM_DEFAULTS";
	private static final String JOB_END_TYPE = "JOB_END";
	private static final String OK = "OK";

	public final static String VERSION = "5.0";

	protected final static Map<String, Object> DEFAULT_PARAMS = new HashMap<>();

	/**
	 * Utility method for building a hash from key-value pairs
	 * 
	 * @param o  A list with an even number of elemements
	 * @return   A hash that associates its key to its next value in the list
	 */
	protected static Map<String, Object> toMap(Object... o) {
		if (o.length % 2 != 0) {
			throw new IllegalArgumentException(
					"Even number of arguments expected");
		}
		Map<String, Object> map = new HashMap<>();
		for (int i = 0; i < o.length; i += 2) {
			map.put(o[i].toString(), o[i + 1]);
		}
		return map;
	}

	private BufferedReader input;
	private BufferedWriter output;
	private ObjectMapper mapper;

	private int debug = 0;
	private String workerTempDirectory;

	private Logger log;
	private boolean autoFlow;

	protected Logger getLog() {
		if (log == null) {
			log = LoggerFactory.getLogger(this.getClass());
		}
		return log;
	}

/*
	private BaseRunnable(Reader input, Writer output) throws IOException {
		this.input = new BufferedReader(input);
		this.output = new BufferedWriter(output);
		this.mapper = new ObjectMapper();
	}

	private BaseRunnable(InputStream input, OutputStream output)
			throws IOException {
		this(new InputStreamReader(input), new OutputStreamWriter(output));
	}

    public BaseRunnable(FileDescriptor inputDescriptor, FileDescriptor outputDescriptor) throws IOException {
        this(new FileInputStream(inputDescriptor), new FileOutputStream(outputDescriptor));
    }
*/

    public void setFileDescriptors(FileDescriptor inputDescriptor, FileDescriptor outputDescriptor) throws IOException {
		this.input = new BufferedReader(new InputStreamReader(new FileInputStream(inputDescriptor)));
		this.output = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(outputDescriptor)));
		this.mapper = new ObjectMapper();
    }

	public void processLifeCycle() {
		init();
		boolean run = true;
		while (run) {
			Object responseO = readMessage();
			getLog().debug("Received response: " + responseO);
			if (Map.class.isAssignableFrom(responseO.getClass())) {
				Map response = (Map) responseO;
				// handle the job
				Object inputJob = response.get(INPUT_JOB_KEY);
				getLog().debug("Received input job: " + inputJob);
				if (inputJob == null) {
					// empty job, so exit with no response needed
					getLog().info("No further job received - worker exiting");
					run = false;
				} else {
					// job, so respond OK and process it
					sendOK();
					getLog().debug(
							"Building job with " + String.valueOf(inputJob));
					Job job = new Job((Map) inputJob);
					getLog().info("Processing job " + job.getDbID());
					// process some other configs
					this.debug = (Integer) response.get(DEBUG_KEY);
					try {
						runLifeCycle(job,
								numericParamToLong(response
										.get(EXECUTE_WRITES_KEY)) == 1);
						getLog().info("Job completed");
						job.setComplete(true);
					} catch (HiveCommunicationException e) {
						// we can't do anything here except let it bubble up
						getLog().error("Caught exception ", e);
						throw e;
					} catch (Throwable e2) {
						// log everything else
						getLog().error("Job failed", e2);
						job.setComplete(false);
						getLog().equals(e2);
					}
					finishJob(job);
				}
			} else {
				String msg = "Unexpected object of class "
						+ responseO.getClass() + " received";
				getLog().error(msg);
				throw new HiveCommunicationException(msg);
			}
		}

		try {
			getLog().trace("Closing input pipe");
			input.close();
			getLog().trace("Closing output pipe");
			output.close();
		} catch (IOException e) {
			throw new HiveCommunicationException("Could not close pipes", e);
		}
	}

	private void finishJob(Job job) {
		sendMessageAndWait(
				JOB_END_TYPE,
				toMap(COMPLETE_KEY,
						job.isComplete(),
						JOB_KEY,
						toMap(AUTOFLOW_KEY, job.isAutoflow(),
								LETHAL_FOR_WORKER_KEY, job.isLethalForWorker(),
								TRANSIENT_ERROR_KEY, job.isTransientError()),
						PARAMS_KEY,
						toMap(SUBSTITUTED_KEY, job.getParameters().getParams(),
								UNSUBSTITUTED_KEY, job.getParameters()
										.getUnsubParameters())));
	}

	protected void runLifeCycle(Job job, boolean executeWrites) {

		if (job.getRetryCount() > 0) {
			getLog().info("Executing preCleanUp");
			preCleanUp(job);
		}
		getLog().info("Executing fetchInput");
		fetchInput(job);
		getLog().info("Executing run");
		run(job);
		if (executeWrites) {
			getLog().info("Executing writeOutput");
			writeOutput(job);
			getLog().info("Executing postHealthcheck");
			postHealthcheck(job);
		}
		getLog().info("Executing postCleanUp");
		postCleanUp(job);
		getLog().info("Execution complete");

	}

	protected void init() {
		getLog().debug("Initialising");
		sendMessageAndWait(VERSION_TYPE, VERSION);
		sendMessageAndWait(PARAM_DEFAULT_TYPE, getParamDefaults());
		getLog().debug("Initialisation complete");
	}

	protected Map<String, Object> getParamDefaults() {
		return DEFAULT_PARAMS;
	}

	protected void preCleanUp(Job job) {
	}

	protected abstract void fetchInput(Job job);

	protected abstract void run(Job job);

	protected void postHealthcheck(Job job) {
	}

	protected void postCleanUp(Job job) {
	}

	protected abstract void writeOutput(Job job);

	/**
	 * Store a message in the log_message table with is_error indicating whether
	 * the warning is actually an error or not
	 * 
	 * @param message The message string
	 * @param isError Directly maps to the log_message.is_error columns
	 */
	protected void warning(String message, boolean isError) {
		sendMessageAndWait(WARNING_KEY,
				toMap(MESSAGE_KEY, message, IS_ERROR_KEY, isError));
	}

	/**
	 * Dataflows the output_id(s) on a given branch (default 1). Returns
	 * whatever the Perl side returns
	 *
	 * @param params    The current Parameters structure of job
	 * @param outputIds Collection of hashes representing the parameters of the new jobs
	 * @return          Structure received from the parent
	 */
	protected Map<String, Object> dataflow(ParamContainer params,
			Collection<Object> outputIds) {
		return dataflow(params, outputIds, 1);
	}

	/**
	 * Dataflows the output_id(s) on a given branch (default 1). Returns
	 * whatever the Perl side returns
	 * 
	 * @param params    The current Parameters structure of job
	 * @param outputIds        Collection of hashes representing the parameters of the new jobs
	 * @param branchNameOrCode Branch number
	 * @return                 Structure received from the parent
	 */
	protected Map<String, Object> dataflow(ParamContainer params,
			Collection<Object> outputIds, int branchNameOrCode) {
		if (branchNameOrCode == 1) {
			this.autoFlow = false;
		}
		sendEventMessage(
				DATAFLOW_TYPE,
				toMap(OUTPUT_IDS_KEY,
						outputIds,
						BRANCH_NAME_OR_CODE_KEY,
						branchNameOrCode,
						PARAMS_KEY,
						toMap(SUBSTITUTED_KEY, params.getParams(),
								UNSUBSTITUTED_KEY, params.getUnsubParameters())));
		return this.readMessage();
	}

	/**
	 * Returns the full path of the temporary directory created by the worker.
	 * Runnables can override this to return the name they would like to use
	 * 
	 * @return directory name
	 */
	protected String workerTempDirectory() {
		if (workerTempDirectory == null) {
			sendEventMessage(WORKER_TEMP_DIRECTORY_TYPE, null);
			workerTempDirectory = (String) (readMessageAndRespond()
					.get(RESPONSE_KEY));
		}
		return workerTempDirectory;
	}

	/**
	 * Send a message and wait for OK from the parent
	 * 
	 * @param event   Type of the event
	 * @param content Content of the event
	 */
	protected void sendMessageAndWait(String event, Object content) {
		sendEventMessage(event, content);
		Map<String, Object> response = readMessage();
		if (response == null || !OK.equals(response.get(RESPONSE_KEY))) {
			throw new HiveCommunicationException("Expected response " + OK
					+ ": got response " + response);
		}
	}

	/**
	 * Send an event-based message to the parent
	 * 
	 * @param event   Type of the event
	 * @param content Content of the event
	 */
	protected void sendEventMessage(String event, Object content) {
		try {
			sendMessage(mapper.writeValueAsString(wrapContent(event, content)));
		} catch (JsonProcessingException e) {
			String msg = "Problem writing event " + event + " as json";
			getLog().error(msg, e);
			throw new HiveCommunicationException(msg, e);
		}
	}

	/**
	 * Send a piece of JSON to the parent
	 * 
	 * @param json The JSON string to send
	 */
	private void sendMessage(String json) {
		getLog().trace("Writing output: " + json);
		try {
			output.write(json);
			output.write('\n');
			output.flush();
		} catch (IOException e) {
			String msg = "Could not send message to parent process";
			getLog().error(msg, e);
			throw new HiveCommunicationException(msg, e);
		}
	}

	/**
	 * Read a JSON message from the parent
	 * 
	 * @return A Map structure representing the JSON string read from the parent
	 */
	protected Map<String, Object> readMessage() {
		try {
			log.trace("Reading input");
			String json = input.readLine();
			log.trace("Parsing " + json);
			return (Map<String, Object>) (mapper.readValue(json, Map.class));
		} catch (IOException e) {
			String msg = "Could not read message from parent process";
			log.error(msg, e);
			throw new HiveCommunicationException(msg, e);
		}
	}

	protected Map<String, Object> readMessageAndRespond() {
		Map<String, Object> msg = readMessage();
		sendOK();
		return msg;
	}

	protected void sendOK() {
		try {
			sendMessage(mapper.writeValueAsString(toMap(RESPONSE_KEY, OK)));
		} catch (JsonProcessingException e) {
			String msg = "Problem writing OK response as json";
			getLog().error(msg, e);
			throw new HiveCommunicationException(msg, e);
		}
	}

	/**
	 * Utility method to pack an event and a piece of content into a JSON
	 * message for sending to the parent
	 * 
	 * @param event   The name (type) of the event
	 * @param content Its content
	 * @return        A hash ready to be sent to the parent
	 */
	private Map<String, Object> wrapContent(String event, Object content) {
		return toMap(EVENT_KEY, event, CONTENT_KEY, content);
	}

	/**
	 * Helper method for dealing with numbers that have been passed around
	 * through JSON and may be of different types
	 * 
	 * @param param The source object. Currently only numeric and string types are handled
	 * @return      A Long with the same representation as @param
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
			// cast to long first
			return String.valueOf(((Double) param).longValue());
		} else {
			return String.valueOf(param);
		}
	}

}
