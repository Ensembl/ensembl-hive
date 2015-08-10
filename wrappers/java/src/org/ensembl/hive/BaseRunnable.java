package org.ensembl.hive;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.Reader;
import java.io.Writer;
import java.util.HashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.google.gson.Gson;
import com.google.gson.internal.LinkedTreeMap;

/**
 * Base class implementing the runnable lifecycle
 * 
 * @author dstaines
 *
 */
public abstract class BaseRunnable {

	private static final String OK = "OK";

	private static final String RESPONSE_KEY = "response";

	private static final String CONTENT_KEY = "content";

	private static final String VERSION_TYPE = "VERSION";

	private static final String EVENT_KEY = "event";

	public final static String VERSION = "0.1";

	protected final BufferedReader input;
	protected final BufferedWriter output;
	protected final Gson gson;

	private Logger log;

	protected Logger getLog() {
		if (log == null) {
			log = LoggerFactory.getLogger(this.getClass());
		}
		return log;
	}

	public BaseRunnable(Reader input, Writer output) throws IOException {
		this.input = new BufferedReader(input);
		this.output = new BufferedWriter(output);
		this.gson = new Gson();
		init();
	}

	public BaseRunnable(InputStream input, OutputStream output)
			throws IOException {
		this(new InputStreamReader(input), new OutputStreamWriter(output));
	}

	public BaseRunnable(File inputFile, File outputFile) throws IOException {
		this(new FileInputStream(inputFile), new FileOutputStream(outputFile));
	}

	protected void init() throws IOException {
		getLog().debug("Initialising");
		Map<String, Object> map = new HashMap<String, Object>();
		map.put(EVENT_KEY, VERSION_TYPE);
		map.put(CONTENT_KEY, VERSION);
		sendMessage(map);
		Map response = readMessage();
		Object responseVal = response.get(RESPONSE_KEY);
		if (!OK.equals(responseVal)) {
			throw new HiveCommunicationException("Expected response " + OK
					+ ": got response " + responseVal);
		}
		getLog().debug("Initialisation complete");
	}

	protected void sendMessage(Object message) {
		String json = gson.toJson(message);
		log.trace("Writing output: " + json);
		try {
			output.write(json);
			output.write('\n');
			output.flush();
		} catch (IOException e) {
			String msg = "Could not send message to parent process";
			log.error(msg, e);
			throw new HiveCommunicationException(msg, e);
		}
	}

	protected Map readMessage() {
		try {
			log.trace("Reading input");
			String json = input.readLine();
			log.trace("Parsing " + json);
			return gson.fromJson(json, LinkedTreeMap.class);
		} catch (IOException e) {
			String msg = "Could not read message from parent process";
			log.error(msg, e);
			throw new HiveCommunicationException(msg, e);
		}
	}

	public abstract ParamContainer paramDefaults();

	public abstract void fetchInput();

	public abstract void run();

	public abstract void writeOutput();

}
