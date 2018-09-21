package org.ensembl.hive;

public class NullParamException extends RuntimeException {
	public NullParamException(String paramName) {
		super(paramName);
	}

	private static final long serialVersionUID = 1L;
}
