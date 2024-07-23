#!/bin/bash

# This check makes sure that the install manifests for a manual install (in install/deploy/)
# are in sync with the OLM install manifests (in manifests/)

repo_base="$( dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )")"
repo_name=$(basename "${repo_base}")
cd "${repo_base}"
if ! [ -x bin/json2yaml -a -x bin/yaml2json ]; then
  echo "Missing test utilities bin/json2yaml and/or bin/yaml2json. 'make build-testutil' must be run first"
  exit 1
fi
if [ "$NO_DOCKER" = "1" -o -n "$IS_CONTAINER" ]; then
  exitcode=0
  outdir="$(mktemp --tmpdir -d manifest-diff.XXXXXXXXXX)"
  trap "rm -rf '${outdir}'" EXIT

  # Step 1: Compare RBAC from install/deploy/02_vpa-rbac.yaml with RBAC from $csvfile
  csvfile="manifests/stable/vertical-pod-autoscaler.clusterserviceversion.yaml"
  rbacfile="install/deploy/02_vpa-rbac.yaml"
  out1="${outdir}/rbac-from-02_vpa-rbac.yaml"
  out2="${outdir}/rbac-from-$(basename "$csvfile")"
  sed -f hack/yamls2list.sed "$rbacfile" | bin/yaml2json | jq -f hack/filter-rbac.jq | bin/json2yaml > "$out1"
  bin/yaml2json "$csvfile" | jq -f hack/filter-rbac.jq | bin/json2yaml > "$out2"
  if ! diff -q "$out1" "$out2"; then
    echo
    echo "Sorted/normalized $rbacfile:"
    echo
    cat "$out1"
    echo
    echo "Sorted/normalized $csvfile:"
    echo
    cat "$out2"
    echo
    echo diff -u "$out1" "$out2"
    echo
    diff -u "$out1" "$out2"
    echo
    echo "$0 failed. Permissions not equivalent in $rbacfile and $csvfile"
    echo "If changes are made to $rbacfile, equivalent changes should be made to $csvfile (and vice-versa)."
    echo
    exitcode=1
  fi

  # Step 2: Compare the VPA controller CRD in install/deploy/ with the one from manifests/
  crdfile="manifests/stable/vertical-pod-autoscaler-controller.crd.yaml"
  if ! diff -wu install/deploy/01_vpacontroller.crd.yaml "$crdfile"; then
    echo
    echo "$0 failed. CRDs don't match: install/deploy/01_vpacontroller.crd.yaml and $crdfile"
    echo "If changes are made to install/deploy/01_vpacontroller.crd.yaml, equivalent changes should be made to $crdfile (and vice-versa)."
    echo
    exitcode=1
  fi

  # Step 3: Compare the VPA CRD in install/deploy/ with the one from manifests/
  crdfile="manifests/stable/vpa-v1.crd.yaml"
  if ! diff -wu install/deploy/05_vpa-crd.yaml "$crdfile"; then
    echo
    echo "$0 failed. CRDs don't match: install/deploy/05_vpa-crd.yaml and $crdfile"
    echo "If changes are made to install/deploy/05_vpa-crd.yaml, equivalent changes should be made to $crdfile (and vice-versa)."
    echo
    exitcode=1
  fi

  # Step 4: Compare the VPA Checkpoint CRD in install/deploy/ with the one from manifests/
  crdfile="manifests/stable/vpacheckpoint-v1.crd.yaml"
  if ! diff -wu install/deploy/06_vpacheckpoint-crd.yaml "$crdfile"; then
    echo
    echo "$0 failed. CRDs don't match: install/deploy/06_vpacheckpoint-crd.yaml and $crdfile"
    echo "If changes are made to install/deploy/06_vpacheckpoint-crd.yaml, equivalent changes should be made to $crdfile (and vice-versa)."
    echo
    exitcode=1
  fi

  exit $exitcode
else
  podman run --rm \
    -it \
    --env IS_CONTAINER=TRUE \
    --volume "${repo_base}:/go/src/github.com/openshift/${repo_name}:z" \
    --workdir "/go/src/github.com/openshift/${repo_name}" \
    registry.ci.openshift.org/openshift/release:rhel-9-release-golang-1.22-openshift-4.17 \
    ./hack/manifest-diff.sh "${@}"
fi;
