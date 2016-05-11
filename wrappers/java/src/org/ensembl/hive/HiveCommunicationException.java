package org.ensembl.hive;

/**
 * Unchecked exception indicating a problem with Hive parent-child communication
 * @author dstaines
 *
 */
public class HiveCommunicationException extends RuntimeException {

	private static final long serialVersionUID = 1L;


	public HiveCommunicationException(String message) {
		super(message);
	}

	public HiveCommunicationException(String message, Throwable cause) {
		super(message, cause);
	}

}
