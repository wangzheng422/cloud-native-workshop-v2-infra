#!/bin/bash
#
# Prereqs: a running ocp 4 cluster, logged in as kubeadmin
#
MYDIR="$( cd "$(dirname "$0")" ; pwd -P )"
function usage() {
    echo "usage: $(basename $0) [-c/--count usercount] -m/--module-type module_type"
}

# Defaults
USERCOUNT=2
MODULE_TYPE=m1,m2,m3
REQUESTED_CPU=2
REQUESTED_MEMORY=4Gi
# REQUESTED_CPU=100m
# REQUESTED_MEMORY=1Gi
USER_PWD=openshift

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -c|--count)
    USERCOUNT="$2"
    shift # past argument
    shift # past value
    ;;
    -m|--module-type)
    MODULE_TYPE="$2"
    shift # past argument
    shift # past value
    ;;
    *)    # unknown option
    echo "Unknown option: $key"
    usage
    exit 1
    ;;
esac
done

echo -e "Start with CCNRD Dev Track Environment Deployment... \n"
start_time=$SECONDS

set -- "${POSITIONAL[@]}" # restore positional parameters
echo -e "USERCOUNT: $USERCOUNT"
echo -e "MODULE_TYPE: $MODULE_TYPE\n"

if [ ! "$(oc get clusterrolebindings)" ] ; then
  echo "not cluster-admin"
  exit 1
fi

##############
## add by wzh

oc patch -n openshift is jboss-eap72-openshift -p "{\"spec\":{\"tags\":[{ \"name\":\"1.0\",\"from\":{\"name\":\"registry.redhat.ren/registry.redhat.io/jboss-eap-7/eap72-openshift:1.0\"}}]}}"
oc patch -n openshift is postgresql -p "{\"spec\":{\"tags\":[{ \"name\":\"10\",\"from\":{\"name\":\"registry.redhat.ren/registry.redhat.io/rhscl/postgresql-10-rhel7:latest\"}}]}}"
oc patch -n openshift is postgresql -p "{\"spec\":{\"tags\":[{ \"name\":\"9.6\",\"from\":{\"name\":\"registry.redhat.ren/registry.redhat.io/rhscl/postgresql-96-rhel7:1-47\"}}]}}"
oc patch -n openshift is redhat-sso72-openshift -p "{\"spec\":{\"tags\":[{ \"name\":\"1.2\",\"from\":{\"name\":\"registry.redhat.ren/registry.redhat.io/redhat-sso-7/sso72-openshift:1.2\"}}]}}"
oc patch -n openshift is redhat-openjdk18-openshift -p "{\"spec\":{\"tags\":[{ \"name\":\"1.5\",\"from\":{\"name\":\"registry.redhat.ren/registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift:1.5\"}}]}}"
jenkins_image=grep "jenkins " /data/ocp4/release.txt  | awk '{print $2}' | sed 's/.*@sha256://'
oc patch -n openshift is jenkins -p "{\"spec\":{\"tags\":[{ \"name\":\"2\",\"from\":{\"name\":\"registry.redhat.ren/ocp4/openshift4@sha256:${jenkins_image}\"}}]}}"
oc patch -n openshift is jenkins -p "{\"spec\":{\"tags\":[{ \"name\":\"latest\",\"from\":{\"name\":\"registry.redhat.ren/ocp4/openshift4@sha256:${jenkins_image}\"}}]}}"


# oc import-image --all jboss-eap72-openshift -n openshift
# oc import-image --all postgresql -n openshift

htpasswd -c -B -b users.htpasswd admin redhat

for i in $(eval echo "{0..$USERCOUNT}") ; do
  htpasswd -b users.htpasswd user$i ${USER_PWD}
  echo -n .
  sleep 2
done

oc delete secret htpass-secret -n openshift-config
oc create secret generic htpass-secret --from-file=htpasswd=users.htpasswd -n openshift-config

# oc create secret generic htpass-secret --from-file=htpasswd=users.htpasswd -n openshift-config --dry-run -o yaml | oc apply -f -

cat << EOF > htpass.yaml 
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: my_htpasswd_provider
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
EOF
oc apply -f htpass.yaml 

# oc adm policy add-cluster-role-to-user cluster-admin admin

## end add by wzh
#################


# Make the admin as cluster admin
oc adm policy add-cluster-role-to-user cluster-admin $(oc whoami)

# Add view role of default namespace to all userXX
for i in $(eval echo "{0..$USERCOUNT}") ; do
  oc adm policy add-role-to-user view user$i -n default
  echo -n .
  sleep 2
done

# create labs-infra project
oc new-project labs-infra

# adjust limits for admin
oc get userquota/default
RESULT=$?
if [ $RESULT -eq 0 ]; then
  oc delete userquota/default
else
  echo -e "userquota already is deleted...\n"
fi

oc delete limitrange --all -n labs-infra

# get routing suffix
TMP_PROJ="dummy-$RANDOM"
oc new-project $TMP_PROJ
oc create route edge dummy --service=dummy --port=8080 -n $TMP_PROJ
ROUTE=$(oc get route dummy -o=go-template --template='{{ .spec.host }}' -n $TMP_PROJ)
HOSTNAME_SUFFIX=$(echo $ROUTE | sed 's/^dummy-'${TMP_PROJ}'\.//g')
MASTER_URL=$(oc whoami --show-server)
CONSOLE_URL=$(oc whoami --show-console)

echo -e "HOSTNAME_SUFFIX: $HOSTNAME_SUFFIX \n"

oc project labs-infra

# create templates for labs
oc create -f ${MYDIR}/../files/template-binary.json -n openshift
oc create -f ${MYDIR}/../files/template-prod.json -n openshift
oc create -f ${MYDIR}/../files/ccn-sso72-template.json -n openshift

# deploy rhamt
if [ -z "${MODULE_TYPE##*m1*}" ] ; then
  oc process -f ${MYDIR}/../files/web-template-empty-dir-executor.json \
      -p WEB_CONSOLE_REQUESTED_CPU=$REQUESTED_CPU \
      -p WEB_CONSOLE_REQUESTED_MEMORY=$REQUESTED_MEMORY \
      -p EXECUTOR_REQUESTED_CPU=$REQUESTED_CPU \
      -p EXECUTOR_REQUESTED_MEMORY=2Gi | oc create -n labs-infra  -f -
fi

# Setup Istio Service Mesh
if [ -z "${MODULE_TYPE##*m3*}" ] || [ -z "${MODULE_TYPE##*m4*}" ] ; then
  echo -e "Installing OpenShift Service Mesh..."
  echo -e "you have to follow offical docs to install service mesh first..."
  # oc apply -f ${MYDIR}/../files/clusterserviceversion-servicemeshoperator.v1.0.3.yaml
  # oc apply -f ${MYDIR}/../files/subscription-servicemeshoperator.yaml
  echo -e "Deploying Service Mesh Control Plane and Membber Roll..."
  oc new-project istio-system
  oc delete limitranges/istio-system-core-resource-limits -n istio-system
  # oc apply -f ${MYDIR}/../files/istio-installation.yaml
  # oc apply -f ${MYDIR}/../files/servicemeshmemberroll-default.yaml
fi

# Create coolstore & bookinfo projects for each user
echo -e "Creating coolstore & bookinfo projects for each user... \n"
for i in $(eval echo "{0..$USERCOUNT}") ; do
  if [ -z "${MODULE_TYPE##*m1*}" ] || [ -z "${MODULE_TYPE##*m2*}" ] || [ -z "${MODULE_TYPE##*m3*}" ] ; then
    oc new-project user$i-inventory
    oc adm policy add-scc-to-user anyuid -z default -n user$i-inventory
    oc adm policy add-scc-to-user privileged -z default -n user$i-inventory
    oc adm policy add-role-to-user admin user$i -n user$i-inventory
    oc new-project user$i-catalog
    oc adm policy add-scc-to-user anyuid -z default -n user$i-catalog
    oc adm policy add-scc-to-user privileged -z default -n user$i-catalog
    oc adm policy add-role-to-user admin user$i -n user$i-catalog
  fi
  if [ -z "${MODULE_TYPE##*m3*}" ] ; then
    oc new-project user$i-bookinfo
    oc adm policy add-scc-to-user anyuid -z default -n user$i-bookinfo
    oc adm policy add-scc-to-user privileged -z default -n user$i-bookinfo
    oc adm policy add-role-to-user admin user$i -n user$i-bookinfo
    # oc adm policy add-role-to-user view user$i -n istio-system

    oc new-project user$i-smcp
    oc adm policy add-scc-to-user anyuid -z default -n user$i-smcp
    oc adm policy add-scc-to-user privileged -z default -n user$i-smcp
    oc adm policy add-role-to-user admin user$i -n user$i-smcp
    cat ${MYDIR}/../files/istio-installation.yaml | sed "s/{{istio-system}}/user$i-smcp/g" | oc apply -f -
    cat ${MYDIR}/../files/servicemeshmemberroll-default.yaml | sed "s/{{istio-system}}/user$i-smcp/g" | sed "s/{{userXX-bookinfo}}/user$i-bookinfo/g" | sed "s/{{userXX-catalog}}/user$i-catalog/g" | sed "s/{{userXX-inventory}}/user$i-inventory/g" | oc apply -f -
  fi
  if [ -z "${MODULE_TYPE##*m4*}" ] ; then
    oc new-project user$i-cloudnativeapps
    oc adm policy add-scc-to-user anyuid -z default -n user$i-cloudnativeapps
    oc adm policy add-scc-to-user privileged -z default -n user$i-cloudnativeapps
    oc adm policy add-role-to-user admin user$i -n user$i-cloudnativeapps
    oc adm policy add-role-to-user view user$i -n istio-system
  fi
done

# Install Custom Resource Definitions, Knative Serving, Knative Eventing
if [ -z "${MODULE_TYPE##*m4*}" ] ; then
  echo -e "Installing OpenShift Serverless..."
  oc apply -f ${MYDIR}/../files/clusterserviceversion-serverless-operator.v1.3.0.yaml
  oc apply -f ${MYDIR}/../files/subscription-serverless-operator.yaml
  oc new-project knative-serving
  oc apply -f ${MYDIR}/../files/knativeserving-knative-serving.yaml

  echo -e "Installing Knative Eventing..."
  oc apply -f ${MYDIR}/../files/clusterserviceversion-knative-eventing-operator.v0.10.0.yaml
  oc apply -f ${MYDIR}/../files/subscription-knative-eventing-operator.yaml

echo -e "Creating Role, Group, and assign Users"
for i in $(eval echo "{0..$USERCOUNT}") ; do
cat <<EOF | oc apply -n user$i-cloudnativeapps -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: workshop-student$i
rules:
  - apiGroups: ["serving.knative.dev"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["eventing.knative.dev"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["sources.eventing.knative.dev"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["messaging.knative.dev"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["networking.internal.knative.dev"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["autoscaling.internal.knative.dev"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["caching.internal.knative.dev"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["tekton.dev"]
    resources: ["*"]
    verbs: ["*"]
EOF
sleep 2
oc policy add-role-to-user workshop-student$i user$i --role-namespace=user$i-cloudnativeapps -n user$i-cloudnativeapps
done

# Install AMQ Streams operator for all namespaces
oc apply -f ${MYDIR}/../files/clusterserviceversion-amqstreams.v1.3.0.yaml
oc apply -f ${MYDIR}/../files/subscription-amq-streams.yaml

# Install Knative Kafka operator for all namespaces
oc apply -f ${MYDIR}/../files/clusterserviceversion-knative-kafka-operator.v0.10.0.yaml
oc apply -f ${MYDIR}/../files/subscription-knative-kafka-operator.yaml

# Wait for Kafka CRD to be a thing
echo -e "Waiting for Kafka CRD"
while [ true ] ; do
  if [ "$(oc explain kafka -n knative-eventing)" ] ; then
    break
  fi
  echo -n .
  sleep 10
done

# Install Kafka cluster in Knative-eventing
echo -e "Install Kafka cluster in Knative-eventing"
cat <<EOF | oc create -f -
apiVersion: kafka.strimzi.io/v1beta1
kind: Kafka
metadata:
  name: my-cluster
  namespace: knative-eventing
spec:
  kafka:
    version: 2.3.0
    replicas: 3
    listeners:
      plain: {}
      tls: {}
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      log.message.format.version: '2.3'
    storage:
      type: ephemeral
  zookeeper:
    replicas: 3
    storage:
      type: ephemeral
  entityOperator:
    topicOperator: {}
    userOperator: {}
EOF

# Create KnativeEventingKafka in Knative-eventing
cat <<EOF | oc create -f -
apiVersion: eventing.knative.dev/v1alpha1
kind: KnativeEventingKafka
metadata:
  name: knative-eventing-kafka
  namespace: knative-eventing
spec:
  bootstrapServers: 'my-cluster-kafka-bootstrap.knative-eventing:9092'
  setAsDefaultChannelProvisioner: false
EOF

#Install OpenShift pipeline operator for all namespaces
echo -e "Installing Tekton pipelines"
oc apply -f ${MYDIR}/../files/clusterserviceversion-openshift-pipelines-operator.v0.8.2.yaml
oc apply -f ${MYDIR}/../files/subscription-openshift-pipelines-operator.yaml

echo -e "Creating new test-pipeline projects"
for i in $(eval echo "{0..$USERCOUNT}") ; do
  oc new-project user$i-cloudnative-pipeline
  oc delete limitranges user0-cloudnativeapps-core-resource-limits -n user$i-cloudnativeapps
  oc delete limitranges user$i-cloudnative-pipeline-core-resource-limits -n user$i-cloudnative-pipeline
  oc adm policy add-role-to-user admin user$i -n user$i-cloudnative-pipeline
done

for i in $(eval echo "{0..$USERCOUNT}") ; do
  oc adm policy add-role-to-user view user$i -n knative-serving
done

# here is the end if you want
fi

# deploy guides
for MODULE in $(echo $MODULE_TYPE | sed "s/,/ /g") ; do
  MODULE_NO=$(echo $MODULE | cut -c 2)
  oc -n labs-infra new-app registry.redhat.ren/quay.io/osevg/workshopper --name=guides-$MODULE \
      -e MASTER_URL=$MASTER_URL \
      -e CONSOLE_URL=$CONSOLE_URL \
      -e ECLIPSE_CHE_URL=http://codeready-labs-infra.$HOSTNAME_SUFFIX \
      -e KEYCLOAK_URL=http://keycloak-labs-infra.$HOSTNAME_SUFFIX \
      -e ROUTE_SUBDOMAIN=$HOSTNAME_SUFFIX \
      -e CONTENT_URL_PREFIX="http://gogs.redhat.ren:10080/root/cloud-native-workshop-v2$MODULE-guides/raw/master/" \
      -e WORKSHOPS_URLS="http://gogs.redhat.ren:10080/root/cloud-native-workshop-v2$MODULE-guides/raw/master/_cloud-native-workshop-module$MODULE_NO.yml" \
      -e GIT_URL="http://gogs.redhat.ren:10080/root" \
      -e CHE_USER_NAME=userXX \
      -e CHE_USER_PASSWORD=${USER_PWD} \
      -e OPENSHIFT_USER_NAME=userXX \
      -e OPENSHIFT_USER_PASSWORD=${USER_PWD} \
      -e RHAMT_URL=http://rhamt-web-console-labs-infra.$HOSTNAME_SUFFIX \
      -e LOG_TO_STDOUT=true
  oc -n labs-infra expose svc/guides-$MODULE
done

# update Jenkins templates and create Jenkins project
if [ -z "${MODULE_TYPE##*m2*}" ] ; then
  oc replace -f ${MYDIR}/../files/jenkins-ephemeral.yml -n openshift
  oc get project jenkins
  RESULT=$?
  if [ $RESULT -eq 0 ]; then
    echo -e "jenkins project already exists..."
  elif [ -z "${MODULE_TYPE##*m2*}" ] ; then
    echo -e "Creating Jenkins project..."
    oc new-project jenkins --display-name='Jenkins' --description='Jenkins CI Engine'
    oc new-app --template=jenkins-ephemeral -l app=jenkins -p JENKINS_SERVICE_NAME=jenkins -p DISABLE_ADMINISTRATIVE_MONITORS=true
    oc set resources dc/jenkins --limits=cpu=1,memory=2Gi --requests=cpu=1,memory=512Mi
  fi
fi

# Configure RHAMT Keycloak
if [ -z "${MODULE_TYPE##*m1*}" ] ; then
  echo -e "Waiting for rhamt to be running... \n"
  while [ 1 ]; do
    STAT=$(curl -s -w '%{http_code}' -o /dev/null http://rhamt-web-console-labs-infra.$HOSTNAME_SUFFIX)
    if [ "$STAT" = 200 ] ; then
      break
    fi
    echo -n .
    sleep 10
  done
  echo -e "Getting access token to update RH-SSO theme \n"
  RESULT_TOKEN=$(curl -k -X POST https://secure-rhamt-web-console-labs-infra.$HOSTNAME_SUFFIX/auth/realms/master/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d 'password=password' \
  -d 'grant_type=password' \
  -d 'client_id=admin-cli' | jq -r '.access_token')

  echo -e "Updating a master realm with RH-SSO theme \n"
  RES=$(curl -s -w '%{http_code}' -o /dev/null  -k -X PUT https://secure-rhamt-web-console-labs-infra.$HOSTNAME_SUFFIX/auth/admin/realms/master/ \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $RESULT_TOKEN" \
  -d '{ "displayName": "rh-sso", "displayNameHtml": "<strong>Red Hat</strong><sup>®</sup> Single Sign On", "loginTheme": "rh-sso", "adminTheme": "rh-sso", "accountTheme": "rh-sso", "emailTheme": "rh-sso", "accessTokenLifespan": 6000 }')

  if [ "$RES" = 204 ] ; then
    echo -e "Updated a master realm with RH-SSO theme successfully...\n"
  else
    echo -e "Failure to update a master realm with RH-SSO theme with $RES\n"
  fi

  echo -e "Creating RH-SSO users \n"
  for i in $(eval echo "{0..$USERCOUNT}") ; do
    RES=$(curl -s -w '%{http_code}' -o /dev/null  -k -X POST https://secure-rhamt-web-console-labs-infra.$HOSTNAME_SUFFIX/auth/admin/realms/rhamt/users \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer $RESULT_TOKEN" \
    -d '{ "username": "user'"$i"'", "enabled": true, "disableableCredentialTypes": [ "password" ] }')
    if [ "$RES" = 200 ] || [ "$RES" = 201 ] || [ "$RES" = 409 ] ; then
      echo -e "Created RH-SSO user$i successfully...\n"
    else
      echo -e "Failure to create RH-SSO user$i with $RES\n"
    fi
  done

  echo -e "Retrieving RH-SSO user's ID list \n"
  USER_ID_LIST=$(curl -k -X GET https://secure-rhamt-web-console-labs-infra.$HOSTNAME_SUFFIX/auth/admin/realms/rhamt/users/ \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $RESULT_TOKEN")
  echo -e "USER_ID_LIST: $USER_ID_LIST \n"

  echo -e "Getting access token to reset passwords \n"
  export RESULT_TOKEN=$(curl -k -X POST https://secure-rhamt-web-console-labs-infra.$HOSTNAME_SUFFIX/auth/realms/master/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d 'password=password' \
  -d 'grant_type=password' \
  -d 'client_id=admin-cli' | jq -r '.access_token')
  echo -e "RESULT_TOKEN: $RESULT_TOKEN \n"

  echo -e "Reset passwords for each RH-SSO user \n"
  for i in $(jq '. | keys | .[]' <<< "$USER_ID_LIST"); do
    USER_ID=$(jq -r ".[$i].id" <<< "$USER_ID_LIST")
    USER_NAME=$(jq -r ".[$i].username" <<< "$USER_ID_LIST")
    if [ "$USER_NAME" != "rhamt" ] ; then
      RES=$(curl -s -w '%{http_code}' -o /dev/null -k -X PUT https://secure-rhamt-web-console-labs-infra.$HOSTNAME_SUFFIX/auth/admin/realms/rhamt/users/$USER_ID/reset-password \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "Authorization: Bearer $RESULT_TOKEN" \
        -d '{ "type": "password", "value": "'"$USER_PWD"'", "temporary": true}')
      if [ "$RES" = 204 ] ; then
        echo -e "user$i password is reset successfully...\n"
      else
        echo -e "Failure to reset user$i password with $RES\n"
      fi
    fi
  done
fi

oc delete project $TMP_PROJ

# Install CodeReady Workspace
echo -e "Installing CodeReady Workspace...\n"

oc project labs-infra
# oc create sa codeready-operator

cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: codeready-operator
rules:
  - apiGroups:
      - extensions/v1beta1
    resources:
      - ingresses
    verbs:
      - '*'
  - apiGroups:
      - route.openshift.io
    resources:
      - routes
    verbs:
      - '*'
  - apiGroups:
      - rbac.authorization.k8s.io
    resources:
      - roles
      - rolebindings
      - clusterroles
      - clusterrolebindings
    verbs:
      - '*'
  - apiGroups:
      - ''
    resources:
      - pods
      - services
      - serviceaccounts
      - endpoints
      - persistentvolumeclaims
      - events
      - configmaps
      - secrets
      - pods/exec
      - pods/log
    verbs:
      - '*'
  - apiGroups:
      - ''
    resources:
      - namespaces
    verbs:
      - get
  - apiGroups:
      - apps
    resources:
      - deployments
    verbs:
      - '*'
  - apiGroups:
      - monitoring.coreos.com
    resources:
      - servicemonitors
    verbs:
      - get
      - create
  - apiGroups:
      - org.eclipse.che
    resources:
      - '*'
    verbs:
      - '*'
EOF

# oc create clusterrole codeready-operator --resource=oauthclients --verb=get,create,delete,update,list,watch
# oc create clusterrolebinding codeready-operator --clusterrole=codeready-operator --serviceaccount=${NAMESPACE}:codeready-operator

# oc apply -f ${MYDIR}/../files/clusterserviceversion-crwoperator.v2.0.0.yaml
oc apply -f ${MYDIR}/../files/codeready-operator-group.yaml
oc apply -f ${MYDIR}/../files/clusterserviceversion-crwoperator.v1.2.2.yaml
oc apply -f ${MYDIR}/../files/subscription-codeready-workspaces.yaml

# Wait for checluster to be a thing
echo "Waiting for CheCluster CRDs"
while [ true ] ; do
  if [ "$(oc explain checluster)" ] ; then
    break
  fi
  echo -n .
  sleep 10
done

oc apply -f ${MYDIR}/../files/checluster-codeready.yaml

# Wait for che to be up again after creating checluster
echo "Waiting for Che to come up again after creating checluster..."
while [ 1 ]; do
  STAT=$(curl -s -w '%{http_code}' -o /dev/null http://codeready-labs-infra.$HOSTNAME_SUFFIX/dashboard/)
  if [ "$STAT" = 200 ] ; then
    break
  fi
  echo -n .
  sleep 10
done

# workaround for PVC problem
oc apply -f ${MYDIR}/../files/cm-custom-codeready.yaml

oc scale -n labs-infra deployment/codeready --replicas=0
sleep 10
oc scale -n labs-infra deployment/codeready --replicas=1

# Wait for che to be back up
echo "Waiting for Che to come back up..."
while [ 1 ]; do
  STAT=$(curl -s -w '%{http_code}' -o /dev/null http://codeready-labs-infra.$HOSTNAME_SUFFIX/dashboard/)
  if [ "$STAT" = 200 ] ; then
    break
  fi
  echo -n .
  sleep 10
done

# get keycloak admin password
KEYCLOAK_USER="$(oc set env deployment/keycloak --list -n labs-infra|grep SSO_ADMIN_USERNAME | cut -d= -f2)"
KEYCLOAK_PASSWORD="$(oc set env deployment/keycloak --list -n labs-infra|grep SSO_ADMIN_PASSWORD | cut -d= -f2)"

# Wait for che to be back up
echo "Waiting for keycloak to come up..."
while [ 1 ]; do
  STAT=$(curl -s -w '%{http_code}' -o /dev/null http://keycloak-labs-infra.$HOSTNAME_SUFFIX/auth/)
  if [ "$STAT" = 200 ] ; then
    break
  fi
  echo -n .
  sleep 10
done

SSO_TOKEN=$(curl -s -d "username=${KEYCLOAK_USER}&password=${KEYCLOAK_PASSWORD}&grant_type=password&client_id=admin-cli" \
  -X POST http://keycloak-labs-infra.$HOSTNAME_SUFFIX/auth/realms/master/protocol/openid-connect/token | \
  jq  -r '.access_token')

# Import realm
wget http://gogs.redhat.ren:10080/root/cloud-native-workshop-v2-infra/raw/dev-ocp-4.2/files/ccnrd-realm.json
curl -v -H "Authorization: Bearer ${SSO_TOKEN}" -H "Content-Type:application/json" -d @ccnrd-realm.json \
  -X POST "http://keycloak-labs-infra.$HOSTNAME_SUFFIX/auth/admin/realms"
rm -rf cnrd-realm.json

## MANUALLY add ProtocolMapper to map User Roles to "groups" prefix for JWT claims
echo "Keycloak credentials: $KEYCLOAK_USER / $KEYCLOAK_PASSWORD"

# Create Che users
for i in $(eval echo "{0..$USERCOUNT}") ; do
    USERNAME=user${i}
    FIRSTNAME=User${i}
    LASTNAME=Developer
    curl -v -H "Authorization: Bearer ${SSO_TOKEN}" -H "Content-Type:application/json" -d '{"username":"user'${i}'","enabled":true,"emailVerified": true,"firstName": "User'${i}'","lastName": "Developer","email": "user'${i}'@no-reply.com", "credentials":[{"type":"password","value":"'${USER_PWD}'","temporary":false}]}' -X POST "http://keycloak-labs-infra.${HOSTNAME_SUFFIX}/auth/admin/realms/codeready/users"
done

# Import stack definition
SSO_CHE_TOKEN=$(curl -s -d "username=admin&password=admin&grant_type=password&client_id=admin-cli" \
  -X POST http://keycloak-labs-infra.$HOSTNAME_SUFFIX/auth/realms/codeready/protocol/openid-connect/token | \
  jq  -r '.access_token')

wget http://gogs.redhat.ren:10080/root/cloud-native-workshop-v2-infra/raw/dev-ocp-4.2/files/stack-ccn.json
STACK_RESULT=$(curl -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' \
    --header "Authorization: Bearer ${SSO_CHE_TOKEN}" -d @stack-ccn.json \
    "http://codeready-labs-infra.$HOSTNAME_SUFFIX/api/stack")
rm -rf stack-ccn.json

STACK_ID=$(echo $STACK_RESULT | jq -r '.id')
echo -e "STACK_ID: $STACK_ID"

# Give all users access to the stack
echo -e "Giving all users access to the stack...\n"
curl -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' \
    --header "Authorization: Bearer ${SSO_CHE_TOKEN}" -d '{"userId": "*", "domainId": "stack", "instanceId": "'"$STACK_ID"'", "actions": [ "read", "search" ]}' \
    "http://codeready-labs-infra.$HOSTNAME_SUFFIX/api/permissions"

# import stack image
oc create -n openshift -f ${MYDIR}/../files/stack.imagestream.yaml
sleep 5
oc import-image --all quarkus-stack -n openshift

# Checking if che is up
echo "Checking if che is up..."
while [ 1 ]; do
  STAT=$(curl -s -w '%{http_code}' -o /dev/null http://codeready-labs-infra.$HOSTNAME_SUFFIX/dashboard/)
  if [ "$STAT" = 200 ] ; then
    break
  fi
  echo -n .
  sleep 10
done

# Pre-create workspaces for users
for i in $(eval echo "{0..$USERCOUNT}") ; do
    SSO_CHE_TOKEN=$(curl -s -d "username=user${i}&password=${USER_PWD}&grant_type=password&client_id=admin-cli" \
        -X POST http://keycloak-labs-infra.${HOSTNAME_SUFFIX}/auth/realms/codeready/protocol/openid-connect/token | jq  -r '.access_token')

    TMPWORK=$(mktemp)
    sed 's/WORKSPACENAME/WORKSPACE'${i}'/g' ${MYDIR}/../files/workspace.json > $TMPWORK

    curl -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' \
    --header "Authorization: Bearer ${SSO_CHE_TOKEN}" -d @${TMPWORK} \
    "http://codeready-labs-infra.${HOSTNAME_SUFFIX}/api/workspace?start-after-create=true&namespace=user${i}"
    rm -f $TMPWORK
done

# Recheck if SMMR, SMCP already is created
if [ -z "${MODULE_TYPE##*m3*}" ] || [ -z "${MODULE_TYPE##*m4*}" ] ; then
  oc get ServiceMeshControlPlane -n istio-system
  RESULT=$?
  if [ $RESULT -eq 0 ]; then
    oc apply -f ${MYDIR}/../files/istio-installation.yaml
    oc apply -f ${MYDIR}/../files/servicemeshmemberroll-default.yaml
  else
    echo -e "SMMR, SMCP already is created...\n"
  fi
fi

POD_NUM=$(printf "%.0f\n" ${USERCOUNT}/2)
oc scale -n labs-infra dc/rhamt-web-console-executor --replicas=${POD_NUM}

end_time=$SECONDS
elapsed_time_sec=$(( end_time - start_time ))
elapsed_time_min=$(printf '%dh:%dm:%ds\n' $(($elapsed_time_sec/3600)) $(($elapsed_time_sec%3600/60)) $(($elapsed_time_sec%60)))
echo "Total of $elapsed_time_min seconds elapsed for CCNRD Dev Track Environment Deployment"