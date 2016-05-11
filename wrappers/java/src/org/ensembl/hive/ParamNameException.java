package org.ensembl.hive;

public class ParamNameException extends RuntimeException {
	public ParamNameException(String paramName) {
		super(paramName);
	}

	private static final long serialVersionUID = 1L;
}