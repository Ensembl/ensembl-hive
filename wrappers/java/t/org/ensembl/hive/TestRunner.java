package org.ensembl.hive;

import org.junit.runner.JUnitCore;
import org.junit.runner.Result;
import org.junit.runner.notification.Failure;

import org.ensembl.hive.ParamContainerTest;

public class TestRunner {
	public static void main(String[] args) {
		Result result = JUnitCore.runClasses(org.ensembl.hive.ParamContainerTest.class);
		for (Failure failure : result.getFailures()) {
			System.out.println(failure.toString());
		}
		if (result.wasSuccessful()) {
			System.out.println("All tests passed.");
		} else {
			System.exit(1);
		}
	}
}

