---
layout: global
title: HDFS on Kubernetes Integration Tests
---

# Running the integration tests

Note that the integration test framework is currently being heavily revised and
is subject to change.

The integration tests consists of 4 scripts under the `tests` dir:

  - `setup.sh`: Downloads and starts minikube. Also downlods tools such as
    kubectl, helm, etc.
  - `run.sh`: Launches the HDFS helm charts on the started minikube instance
    and tests the resulting HDFS cluster using a HDFS client.
  - `cleanup.sh`: Shuts down the HDFS cluster so that run.sh can be executed
    again if necessary.
  - `teardown.sh`: Stops the minikube instance so that setup.sh can be executed
    again if necessary.

You can execute these scripts in the listed order to run the integration tests.
These scripts do not require any command line options for the basic
functionality. So an example execution would look lile:

```
   $ tests/setup.sh
   $ tests/run.sh
   $ tests/cleanup.sh
   $ tests/teardown.sh
```
   
## Re-running tests

As a contributor of this project, you may have to re-run the tests after
modifying some helm chart code. Among the four steps, `setup.sh` takes the most
time. You may want to avoid that unless it's necessary.

After executing `run.sh` first time, execute only `cleanup.sh`.
Skip `teardown.sh`. The minikube instance will be still up and running.

Then modify helm charts as you want and execute `run.sh` again. Repeat.

Some data are stored in the minikube instance. For instance, the downloaded
docker images and the persistent volume data, In some cases, you may want to
clean them up. Then you can run `teardown.sh` and `setup.sh` again to
purge them.

## Travis CI support

We use [Travis CI](https://travis-ci.org/) to run the integration tests.
See `.travis.yml` under the top directory. We trigger Travis builds against
new pull requests to this repo.

You may want to enable Travis in your own fork before sending pull requests.
You can trigger Travis builds on your branches in your fork.
For details, see https://docs.travis-ci.com/.
