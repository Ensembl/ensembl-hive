## Requirements

- Filling out the template is required. Any pull request that does not include enough information to be reviewed in a timely manner may be closed at the maintainers' discretion;
- Review the [development guidelines](https://ensembl-hive.readthedocs.io/en/master/dev/development_guidelines.html#ehive-development-in-a-nutshell) for eHive; remember in particular:
    - Do not modify code without testing for regression.
    - Provide simple unit tests to test the changes.
    - If you change the database schema, please follow the instructions [for schema changes in the developer guidelines](https://ensembl-hive.readthedocs.io/en/master/dev/development_guidelines.html#schema-changes).
    - If you change the schema, meadow, or guest language interfaces, please follow the scheme [for internal versioning in the developer guidelines](https://ensembl-hive.readthedocs.io/en/master/dev/development_guidelines.html#internal-versioning).
    - The PR must not fail unit testing.

## Use case

_Describe the problem. Please provide an example representing the motivation behind the need for having these changes in place._

## Description

_Using one or more sentences, describe the proposed changes and how they are implemented._

## Possible Drawbacks

_If applicable, describe any possible undesirable consequence of the changes._

## Testing

_Have you added/modified unit tests to test the changes?_

_If so, do the tests pass/fail?_

_Have you run the entire test suite and no regression was detected?_
