#!/bin/bash
#
# Prereqs: a running ocp 4 cluster, logged in as kubeadmin
#
MYDIR="$( cd "$(dirname "$0")" ; pwd -P )"
function usage() {
    echo "usage: $(basename $0)"
}

if [ ! "$(oc get clusterrolebindings)" ] ; then
  echo "not cluster-admin"
  exit 1
fi

oc delete project labs-infra istio-system knative-eventing knative-serving
oc delete template coolstore-monolith-binary-build coolstore-monolith-pipeline-build ccn-sso72 -n openshift

oc delete -n istio-system -f ${MYDIR}/../files/istio-installation.yaml
oc delete -n istio-system -f ${MYDIR}/../files/servicemeshmemberroll-default.yaml
oc delete -f ${MYDIR}/../files/clusterserviceversion-elasticsearch-operator.4.2.1-201910221723.yaml
oc delete -f ${MYDIR}/../files/subscription-elasticsearch-operator.yaml
oc delete -f ${MYDIR}/../files/clusterserviceversion-jaeger-operator.v1.13.1.yaml
oc delete -f ${MYDIR}/../files/subscription-jaeger-product.yaml
oc delete -f ${MYDIR}/../files/clusterserviceversion-kiali-operator.v1.0.7.yaml
oc delete -f ${MYDIR}/../files/subscription-kiali-ossm.yaml
oc delete -f ${MYDIR}/../files/clusterserviceversion-servicemeshoperator.v1.0.2.yaml
oc delete -f ${MYDIR}/../files/subscription-servicemeshoperator.yaml
oc delete -f ${MYDIR}/../files/clusterserviceversion-serverless-operator.v1.1.0.yaml
oc delete -f ${MYDIR}/../files/subscription-serverless-operator.yaml
oc delete -f ${MYDIR}/../files/clusterserviceversion-knative-eventing-operator.v0.9.0.yaml
oc delete -f ${MYDIR}/../files/subscription-knative-eventing-operator.yaml
oc delete -f ${MYDIR}/../files/knativeserving-knative-serving.yaml 
oc delete -f ${MYDIR}/../files/clusterserviceversion-amqstreams.v1.3.0.yaml
oc delete -f ${MYDIR}/../files/subscription-amq-streams.yaml
oc delete -f ${MYDIR}/../files/clusterserviceversion-knative-kafka-operator.v0.9.0.yaml
oc delete -f ${MYDIR}/../files/sub3cription-knative-kafka-operator.yaml
oc delete -f ${MYDIR}/../files/clusterserviceversion-openshift-pipelines-operator.v0.7.0.yaml
oc delete -f ${MYDIR}/../files/subscription-openshift-pipelines-operator.yaml

# delete user projects
for proj in $(oc get projects -o name | grep 'user*' | cut -d/ -f2) ; do
  oc delete project $proj
done

# scale back down
for i in $(oc get machinesets -n openshift-machine-api -o name | grep worker| cut -d'/' -f 2) ; do
  echo "Scaling $i to 1 replica"
  oc patch -n openshift-machine-api machineset/$i -p '{"spec":{"replicas": 1}}' --type=merge
done
