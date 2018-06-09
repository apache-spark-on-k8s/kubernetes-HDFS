---
layout: global
title: HDFS on Kubernetes Integration Tests
---

# Running the integration tests

Note that the integration test framework is currently being heavily revised and
is subject to change.

The integration tests consists of 4 scripts under the `tests` dir:

  - `setup.sh`: Downloads and starts minikube. Also downloads tools such as
    kubectl, helm, etc.
  - `run.sh`: Launches the HDFS helm charts on the started minikube instance
    and tests the resulting HDFS cluster using a HDFS client.
  - `cleanup.sh`: Shuts down the HDFS cluster so that run.sh can be executed
    again if necessary.
  - `teardown.sh`: Stops the minikube instance so that setup.sh can be executed
    again if necessary.

You can execute these scripts in the listed order to run the integration tests.
These scripts do not require any command line options for the basic
functionality. So an example execution would look like:

```
   $ tests/setup.sh
   $ tests/run.sh
   $ tests/cleanup.sh
   $ tests/teardown.sh
```

# Travis CI support

The repo uses [Travis CI](https://travis-ci.org/) to run the integration tests.
See `.travis.yml` under the top directory. Each new pull request will trigger
a Travis build to test the PR.

You may want to enable Travis in your own fork before sending pull requests.
You can trigger Travis builds on branches in your fork.
For details, see https://docs.travis-ci.com/.
   
# Advanced usage

## Re-running tests

As a contributor of this project, you may have to re-run the tests after
modifying some helm chart code. Among the four steps, `setup.sh` takes the most
time. You may want to avoid that unless it's necessary.

So run `setup.sh` first, followed by `run.sh`:

```
   $ tests/setup.sh
   $ tests/run.sh
```

Then, execute only `cleanup.sh`. i.e. Skip `teardown.sh`. The minikube instance
will be still up and running.

```
   $ tests/cleanup.sh
```

Then modify helm charts as you want and execute `run.sh` again.

```
   $ tests/run.sh
```

Now repeat the `cleanup` and `run` cycle, while modifying helm charts as you
want in between.

```
   $ tests/cleanup.sh
   ... modify your code ...
   $ tests/run.sh
```

Some data are stored in the minikube instance. For example, the downloaded
docker images and the persistent volume data, In some cases, you may want to
clean them up. You can run `teardown.sh` and `setup.sh` again to
purge them.

## Running only particular test cases.

`run.sh` will enumerate all the test cases under `tests/cases` dir. You may
want to run only a particular test case say `tests/cases/_basic.sh`. You
can specify to `CASES` env var to cover the test case only:

```
   $ CASES=_basic.sh tests/run.sh
```

`CASES` can be also set for `cleanup.sh`.

```
   $ CASES=_basic.sh tests/cleanup.sh
```

## Checking the helm chart diff from the dry-run

Before running `helm install` commands, `run.sh` will also conduct dry-run
and check the expanded K8s resource yaml content from the debug information.
The repo has gold files checked in, and the expanded yaml content will be
compared against the gold files.

To ensure your change produces no diff, you can set the `CRASH_ON_DIFF` env
var.

```
   $ DRY_RUN_ONLY=true CRASH_ON_DIFF=true tests/run.sh
```

To promote your yaml output to new golds, you can set the `BLESS_DIFF` env
var.

```
   $ DRY_RUN_ONLY=true BLESS_DIFF=true tests/run.sh
```
