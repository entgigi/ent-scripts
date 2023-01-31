#!/bin/bash
#set -e

BSC_ERROR_CHECK_BIN=127

function errorMessage(){
  local _message="$1" _errorCode="$2"
  echo "$_message"
  exit "$_errorCode"
}

function checkBin() {
  local _binary="$1" _full_path

  echo "Checking binary '$_binary' ... "

  # Checks if the binary is available.
  _full_path=$( command -v "$_binary" )
  commandStatus=$?
  if [ $commandStatus -ne 0 ]; then
    errorMessage "Unable to find binary '$_binary'." $BSC_ERROR_CHECK_BIN
  else
    # Checks if the binary has "execute" permission.
    [ -x "$_full_path" ] && return 0

    errorMessage "Binary '$_binary' found but it does not have *execute* permission." $BSC_ERROR_CHECK_BIN
  fi
}

function usage() {
    echo "The parameters list:"
    echo "  --ns <namespace name>    : Default <ent>                       ; Use namespace for all installation"
    echo "  --version <vX.Y.Z>       : Default <v7.1.2>                    ; Select the version of Entando to install"
    echo "  --host <hostname>        : Default <ent.10.131.132.235.nip.io> ; Use hostname to configure entando"
    echo "  --path <web-app-context> : Default </entando-de-app>           ; The path to use for entando-de-app component"
    echo "  --dbms <postgresql,mysql>: Default <postgresql>                ; The dbms to install and to use"
    echo "  --ssl                    : Default no ssl                      ; Enable ssl certificate generation for selected host param and installation"
    echo "  --sentinel               : Default no redis                    ; Install and configure Redis with sentinel clusterization"
    echo "  --tomcat                 : Default eap                         ; use tomcat de-app image"
    echo "  --ab-app <docker-tag>    : Default tag from selected version   ; use the specified tag for app-builder image"
    echo "  --de-app <docker-tag>    : Default tag from selected version   ; use the specified tag for entando-de-app image"
    echo "  --cm-app <docker-tag>    : Default tag from selected version   ; use the specified tag for component-manager image"
    echo "  --help                   : print this help"
}


while [ "$#" -gt 0 ]; do
  case "$1" in
    "--ns") NS_OVERRIDE="$2";shift;;
    "--ssl") SSL_OVERRIDE="true";;
    "--version") VERSION_OVERRIDE="$2";shift;;
    "--sentinel") SENTINEL_OVERRIDE="true";;
    "--dbms") DBMS_OVERRIDE="$2";shift;;
    "--host") HOST_OVERRIDE="$2";shift;;
    "--path") ENT_PATH_OVERRIDE="$2";shift;;
    "--tomcat") DE_SERVLET_CONTAINER_OVERRIDE="tomcat";;
    "--ab-app") AB_APP_TAG="$2";shift;;
    "--de-app") DE_APP_TAG="$2";shift;;
    "--cm-app") CM_APP_TAG="$2";shift;;
    "--help") usage; exit 3;;
    "--"*) echo "Undefined argument \"$1\"" 1>&2; usage; exit 3;;
  esac
  shift
done

NS="${NS_OVERRIDE:-ent}"
SSL=${SSL_OVERRIDE:-false}
VERSION="${VERSION_OVERRIDE:-v7.1.2}"
SENTINEL=${SENTINEL_OVERRIDE:-false}
DBMS="${DBMS_OVERRIDE:-postgresql}"
HOST="${HOST_OVERRIDE:-ent.10.131.132.235.nip.io}"
ENT_PATH="${ENT_PATH_OVERRIDE:-/entando-de-app}"
DE_SERVLET_CONTAINER="${DE_SERVLET_CONTAINER_OVERRIDE:-eap}"

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "> NS:           $NS"
echo "> SSL:          $SSL"
echo "> VERSION:      $VERSION"
echo "> SENTINEL:     $SENTINEL"
echo "> DBMS:         $DBMS"
echo "> HOST:         $HOST"
echo "> ENT_PATH:     $ENT_PATH"
echo "> AB_APP_TAG:   $AB_APP_TAG"
echo "> DE_CONTAINER: $DE_SERVLET_CONTAINER"
echo "> DE_APP_TAG:   $DE_APP_TAG"
echo "> CM_APP_TAG:   $CM_APP_TAG"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

checkBin curl
checkBin yq
checkBin kubectl

#kubectx default

echo "==== Delete ns $NS ===="
RS=$(kubectl delete ns "${NS}")


echo "==== Create ns $NS ===="
kubectl create ns "${NS}"




if $SENTINEL
then
  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm -n "${NS}" install redis bitnami/redis \
     --values https://raw.githubusercontent.com/entando-ps/redis-sentinel/master/values.yaml \
     --set global.redis.password="testpassword" \
     --set auth.enabled=true \
     --set master.podSecurityContext.enabled=false \
     --set master.containerSecurityContext.enabled=false \
     --set replica.podSecurityContext.enabled=false \
     --set replica.containerSecurityContext.enabled=false \
     --set replica.persistence.size=1Gi \
     --set sentinel.containerSecurityContext.enabled=false

ENVIRONMENTS_TAG=$(cat<<EOF
environmentVariables:  
  - name: REDIS_ACTIVE 
    value: 'true'
  - name: REDIS_SESSION_ACTIVE
    value: 'true'
  - name: REDIS_PASSWORD 
    value: 'testpassword'
  - name: REDIS_ADDRESSES 
    value: 'redis-node-0.redis-headless.${NS}.cluster.local:26379,redis-node-1.redis-headless.${NS}.svc.cluster.local:26379'
EOF
)
  echo "$ENVIRONMENTS_TAG"
  echo "==== Installed sentinel ===="
fi

if $SSL
then
  SSL_DOMAIN=$(echo -n "${HOST}"|cut -d'.' -f2-)
  generate-wildcard-certificate.sh "$SSL_DOMAIN"
  kubectl -n "${NS}" create secret generic secret-ca --from-file=ca0.crt="${SSL_DOMAIN}.crt"
  kubectl -n "${NS}" create secret tls secret-tls --cert="${SSL_DOMAIN}.crt" --key="${SSL_DOMAIN}.key"
  SSL_CONFIG_TLS="entando.tls.secret.name: secret-tls"
  SSL_CONFIG_CA="entando.ca.secret.name: secret-ca"
  echo "==== Generated ca and tls for domain $SSL_DOMAIN in dir $(pwd) ===="
fi

echo "==== Apply entando CRD cluster version $VERSION ===="
curl -sL "https://raw.githubusercontent.com/entando/entando-releases/$VERSION/dist/ge-1-1-6/namespace-scoped-deployment/cluster-resources.yaml" | kubectl apply -f -

echo "==== Create Operator config ===="
kubectl apply -n "${NS}" -f - <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: entando-operator-config
data:
  entando.pod.completion.timeout.seconds: "2000"
  entando.pod.readiness.timeout.seconds: "2000"
  entando.k8s.operator.gc.controller.pods: 'false'
  $SSL_CONFIG_TLS
  $SSL_CONFIG_CA
EOF

echo "==== Apply entando operator version $VERSION ===="
curl -sL "https://raw.githubusercontent.com/entando/entando-releases/$VERSION/dist/ge-1-1-6/namespace-scoped-deployment/namespace-resources.yaml"| kubectl -n "${NS}" apply -f -


curl -sL "https://raw.githubusercontent.com/entando/entando-releases/$VERSION/dist/ge-1-1-6/namespace-scoped-deployment/namespace-resources.yaml"| yq 'select(.metadata.name == "entando-docker-image-info")' > /tmp/config-map-images.yml

if [[ -n "$AB_APP_TAG" ]]
then
  AB_APP="{\"version\":\"${AB_APP_TAG}\",\"executable-type\":\"n/a\",\"registry\":\"registry.hub.docker.com\",\"organization\":\"entando\",\"repository\":\"app-builder\"}" yq -i '.data.app-builder-6-4 = strenv(AB_APP_EAP)' /tmp/config-map-images.yml
fi

if [[ -n "$DE_APP_TAG" ]]
then
  DE_APP_EAP="{\"version\":\"${DE_APP_TAG}\",\"executable-type\":\"jvm\",\"registry\":\"registry.hub.docker.com\",\"organization\":\"entando\",\"repository\":\"entando-de-app-${DE_SERVLET_CONTAINER}\"}" yq -i '.data.entando-de-app-eap-6-4 = strenv(DE_APP_EAP)' /tmp/config-map-images.yml
fi

if [[ -n "$CM_APP_TAG" ]]
then
  CM_APP="{\"version\":\"${CM_APP_TAG}\",\"executable-type\":\"jvm\",\"registry\":\"registry.hub.docker.com\",\"organization\":\"entando\",\"repository\":\"entando-component-manager\"}" yq -i '.data.entando-component-manager-6-4 = strenv(CM_APP)' /tmp/config-map-images.yml
fi


kubectl -n "${NS}" apply -f config-map-images.yml


echo "==== Wait 10 secs for operator ===="
sleep 10

echo "==== Create EntandoApp ns:$NS hostname:$HOST path:$ENT_PATH ===="
ENTANDO_APP=$(cat <<EOF
---
apiVersion: entando.org/v1
kind: EntandoApp
metadata:
  namespace: $NS
  name: ent
spec:
  ${ENVIRONMENTS_TAG:-environmentVariables: null}  
  dbms: $DBMS
  ingressHostName: $HOST
  ingressPath: $ENT_PATH
  standardServerImage: eap
  replicas: 1
EOF
)

echo "$ENTANDO_APP"

echo "$ENTANDO_APP" | kubectl apply -n "${NS}" -f -


