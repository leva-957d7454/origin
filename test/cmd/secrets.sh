#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

OS_ROOT=$(dirname "${BASH_SOURCE}")/../..
source "${OS_ROOT}/hack/lib/init.sh"
os::log::stacktrace::install
trap os::test::junit::reconcile_output EXIT

# Cleanup cluster resources created by this test
(
  set +e
  oc delete all,templates,secrets --all
  exit 0
) &>/dev/null


os::test::junit::declare_suite_start "cmd/secrets"
# This test validates secret interaction
os::cmd::expect_failure_and_text 'oc secrets new foo --type=blah makefile=Makefile' 'error: unknown secret type "blah"'
os::cmd::expect_success 'oc secrets new foo --type=blah makefile=Makefile --confirm'
os::cmd::expect_success_and_text 'oc get secrets/foo -o jsonpath={.type}' 'blah'

os::cmd::expect_success 'oc secrets new-dockercfg dockercfg --docker-username=sample-user --docker-password=sample-password --docker-email=fake@example.org'
# can't use a go template here because the output needs to be base64 decoded.  base64 isn't installed by default in all distros
os::cmd::expect_success "oc describe secrets/dockercfg | grep 'dockercfg:' | awk '{print \$2}' > ${HOME}/dockerconfig"
os::cmd::expect_success 'oc secrets new from-file .dockercfg=${HOME}/dockerconfig'
# check to make sure the type was correctly auto-detected
os::cmd::expect_success_and_text 'oc get secret/from-file --template="{{ .type }}"' 'kubernetes.io/dockercfg'
# make sure the -o works correctly
os::cmd::expect_success_and_text 'oc secrets new-dockercfg dockercfg --docker-username=sample-user --docker-password=sample-password --docker-email=fake@example.org -o yaml' 'kubernetes.io/dockercfg'
os::cmd::expect_success_and_text 'oc secrets new from-file .dockercfg=${HOME}/dockerconfig -o yaml' 'kubernetes.io/dockercfg'
# check to make sure malformed names fail as expected
os::cmd::expect_failure_and_text 'oc secrets new bad-name .docker=cfg=${HOME}/dockerconfig' "error: Key names or file paths cannot contain '='."

workingdir="$( mktemp -d )"
os::cmd::expect_success_and_text "oc extract secret/dockercfg --to '${workingdir}'" '.dockercfg'
os::cmd::expect_success_and_text "cat '${workingdir}/.dockercfg'" 'sample-user'
os::cmd::expect_failure_and_text "oc extract secret/dockercfg --to '${workingdir}'" 'error: .dockercfg: file exists, pass --confirm to overwrite'
os::cmd::expect_failure_and_text "oc extract secret/dockercfg secret/dockercfg --to '${workingdir}'" 'error: .dockercfg: file exists, pass --confirm to overwrite'
os::cmd::expect_success_and_text "oc extract secret/dockercfg secret/dockercfg --to '${workingdir}' --confirm" '.dockercfg'
os::cmd::expect_success_and_text "oc extract secret/dockercfg --to '${workingdir}' --confirm" '.dockercfg'
os::cmd::expect_success "oc extract secret/dockercfg --to '${workingdir}' --confirm | xargs rm"

# attach secrets to service account
# single secret with prefix
os::cmd::expect_success 'oc secrets add deployer dockercfg'
# don't add the same secret twice
os::cmd::expect_success 'oc secrets add serviceaccounts/deployer dockercfg secrets/from-file'
# make sure we can add as as pull secret
os::cmd::expect_success 'oc secrets add deployer dockercfg from-file --for=pull'
# make sure we can add as as pull secret and mount secret at once
os::cmd::expect_success 'oc secrets add serviceaccounts/deployer secrets/dockercfg secrets/from-file --for=pull,mount'

GIT_CONFIG_PATH=$(create_gitconfig)
CA_CERT_PATH=$(create_valid_file ca.pem)
PRIVATE_KEY_PATH=$(create_valid_file id_rsa)

os::cmd::expect_success 'oc secrets new-basicauth basicauth --username=sample-user --password=sample-password --gitconfig=$GIT_CONFIG_PATH --ca-cert=$PRIVATE_KEY_PATH'
# check to make sure two mutual exclusive flags return error as expected
os::cmd::expect_failure_and_text 'oc secrets new-basicauth bad-file --password=sample-password --prompt' 'error: must provide either --prompt or --password flag'
# check to make sure incorrect .gitconfig path fail as expected
os::cmd::expect_failure_and_text 'oc secrets new-basicauth bad-file --username=user --gitconfig=/bad/path' 'error: open /bad/path: no such file or directory'

os::cmd::expect_success 'oc secrets new-sshauth sshauth --ssh-privatekey=$PRIVATE_KEY_PATH --ca-cert=$PRIVATE_KEY_PATH'
# check to make sure incorrect SSH private-key path fail as expected
os::cmd::expect_failure_and_text 'oc secrets new-sshauth bad-file --ssh-privatekey=/bad/path' 'error: open /bad/path: no such file or directory'

# attach secrets to service account
# single secret with prefix
os::cmd::expect_success 'oc secrets add serviceaccounts/deployer secrets/basicauth'
# don't add the same secret twice
os::cmd::expect_success 'oc secrets add serviceaccounts/deployer secrets/basicauth secrets/sshauth'
# make sure we can add as as pull secret
os::cmd::expect_success 'oc secrets add serviceaccounts/deployer secrets/basicauth secrets/sshauth --for=pull'
# make sure we can add as as pull secret and mount secret at once
os::cmd::expect_success 'oc secrets add serviceaccounts/deployer secrets/basicauth secrets/sshauth --for=pull,mount'

# command alias
os::cmd::expect_success 'oc secret --help'
os::cmd::expect_success 'oc secret new --help'
os::cmd::expect_success 'oc secret new-dockercfg --help'
os::cmd::expect_success 'oc secret new-basicauth --help'
os::cmd::expect_success 'oc secret new-sshauth --help'
os::cmd::expect_success 'oc secret add --help'

echo "secrets: ok"
os::test::junit::declare_suite_end
