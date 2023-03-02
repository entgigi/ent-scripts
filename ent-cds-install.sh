#!/bin/bash

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
    echo "  --ns <namespace name>                : Default <ent>                       ; Use namespace for all installation"
    echo "  --app <app name>                     : Default <quickstart>                ; Use app name to generate valid name resource"
    echo "  --proto <protocol>                   : Default <http>                      ; Use protocol to make requests to endpoint"
    echo "  --primary                            : Default no primary                  ; Enable primary for label and installation"
    echo "  --tn <tenant1>                       : no Default                          ; Select the name to use for tenant, ignored if set primary"
    echo "  --host <hostname>                    : Default <10.131.132.235.nip.io> ; Use hostname to configure entando"
    echo "  --cors-domain <domain>               : Default <nip.io>                    ; Use domain to configure cors for cds"
    echo "  --client-id <kc client id>           : Default <quickstart>                ; Use client id inside REST calls"
    echo "  --client-secret <kc client secret>   : no Default                          ; Use client secret inside REST calls"
    echo "  --filename <file name>               : Default <entando-data.tar.gz>       ; Use file name for upload and decompress to CDS"
    echo "  --filepath <file path>               : Default </tmp/entando-data.tar.gz>  ; Use file path for upload to CDS"
    echo "  --ingress-class <ingress class>      : no Default                          ; Use ingress class (e.g. nginx) inside ingress"
    echo "  --help                               : print this help"
}



while [ "$#" -gt 0 ]; do
  case "$1" in
    "--ns") NS_OVERRIDE="$2";shift;;
    "--app") APP_OVERRIDE="$2";shift;;
    "--proto") PROTO_OVERRIDE="$2";shift;;
    "--tn") TN_OVERRIDE="$2";shift;;    
    "--primary") 
         PRIMARY_OVERRIDE="true"
         TN_OVERRIDE="primary"
         ;;
    "--host") HOST_OVERRIDE="$2";shift;;
    "--cors-domain") CORS_OVERRIDE="$2";shift;;
    "--client-id") CLIENT_ID_OVERRIDE="$2";shift;;
    "--client-secret") CLIENT_SECRET_OVERRIDE="$2";shift;;
    "--filename") FILE_NAME_OVERRIDE="$2";shift;;
    "--filepath") FILE_PATH_OVERRIDE="$2";shift;;
    "--ingress-class") INGRESS_CLASS="$2";shift;;
    "--help") usage; exit 3;;
    "--"*) echo "Undefined argument \"$1\"" 1>&2; usage; exit 3;;
  esac
  shift
done

NS="${NS_OVERRIDE:-ent}"
APP="${APP_OVERRIDE:-quickstart}"
PROTO="${PROTO_OVERRIDE:-http}"
PRIMARY="${PRIMARY_OVERRIDE:-false}"
TN="${TN_OVERRIDE}"
HOST="${HOST_OVERRIDE:-10.131.132.143.nip.io}"
CORS="${CORS_OVERRIDE:-nip.io}"
CLIENT_ID="${CLIENT_ID_OVERRIDE:-quickstart}"
CLIENT_SECRET="${CLIENT_SECRET_OVERRIDE}"
FILE_NAME="${FILE_NAME_OVERRIDE:-entando-data.tar.gz}"
FILE_PATH="${FILE_PATH_OVERRIDE:-/tmp/entando-data.tar.gz}"

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "> NS:             $NS"
echo "> APP:            $APP"
echo "> PROTO:          $PROTO"
echo "> PRIMARY:        $PRIMARY"
echo "> TN:             $TN"
echo "> HOST:           $HOST"
echo "> CORS:           $CORS"
echo "> CLIENT_ID:      $CLIENT_ID"
echo "> CLIENT_SECRET:  $CLIENT_SECRET"
echo "> FILE_NAME:      $FILE_NAME"
echo "> FILE_PATH:      $FILE_PATH"
echo "> INGRESS_CLASS:  $INGRESS_CLASS"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"



if [[ -n "$INGRESS_CLASS" ]]
then
  INGRESS_CLASS_FIELD="ingressClassName: ${INGRESS_CLASS}"
fi


[ -z "$TN" ] && errorMessage "You must select primary o tenant name" -1
[ -z "$CLIENT_SECRET" ] && errorMessage "You must set client secret" -1

checkBin curl
checkBin jq
checkBin kubectl

echo ""
echo "==== Delete CDS manifests in namespace $NS ===="

echo "Delete ingress $APP-cds-ingress"
kubectl -n "${NS}" delete ingress $APP-cds-ingress

echo "Delete deployment $APP-cds-$TN-deployment"
kubectl -n "${NS}" delete deployment $APP-cds-$TN-deployment

echo "Delete svc $APP-cds-$TN-service"
kubectl -n "${NS}" delete svc $APP-cds-$TN-service

echo "Delete pvc $APP-cds-$TN-pvc"
kubectl -n "${NS}" delete pvc $APP-cds-$TN-pvc

echo "Delete secret $APP-kc-pk-secret"
kubectl -n "${NS}" delete secrets $APP-kc-pk-secret

set -e

echo ""
echo "==== Fetch keycloak pubkey ===="
KC_PUB_KEY=$(curl -s --request GET $PROTO://$APP.$HOST/auth/realms/entando | jq -r .public_key)
echo "kc public key:$KC_PUB_KEY"

CDS_MANIFESTS=$(cat <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: $APP-kc-pk-secret
  namespace: $NS
type: Opaque
stringData:
  KC_PUBLIC_KEY: "-----BEGIN PUBLIC KEY-----\n$KC_PUB_KEY\n-----END PUBLIC KEY-----\n"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    deployment: $APP-cds-$TN-deployment
  name: $APP-cds-$TN-pvc
  namespace: $NS
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    limits:
      storage: 1Gi
    requests:
      storage: 1Gi
  #storageClassName: standard
---
apiVersion: v1
kind: Service
metadata:
  name: $APP-cds-$TN-service
  namespace: $NS
  labels:
    app: $APP-cds-$TN-service
spec:
  ports:
    - port: 8080
      name: internal-port
      protocol: TCP
      targetPort: 8080
    - port: 8081
      name: public-port
      protocol: TCP
      targetPort: 8081
  selector:
    app: $APP-cds-$TN-deployment
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP-cds-$TN-deployment
  namespace: $NS
  labels:
    app: $APP-cds-$TN-deployment
spec:
  selector:
    matchLabels:
      app: $APP-cds-$TN-deployment
  template:
    metadata:
      labels:
        app: $APP-cds-$TN-deployment
    spec:
      containers:
        - readinessProbe:
            httpGet:
              port: 8081
              path: /health/health_check
              scheme: HTTP
            failureThreshold: 1
            initialDelaySeconds: 5
            periodSeconds: 5
            successThreshold: 1
            timeoutSeconds: 5
          env:
            - name: RUST_LOG
              value: actix_web=info,actix_server=info,actix_web_middleware_keycloak_auth=trace
            - name: KEYCLOAK_PUBLIC_KEY
              valueFrom:
                secretKeyRef:
                  key: KC_PUBLIC_KEY
                  name: $APP-kc-pk-secret
            - name: CORS_ALLOWED_ORIGIN
              value: All
            - name: CORS_ALLOWED_ORIGIN_END_WITH
              value: "$CORS"
          name: cds
          image: docker.io/entando/cds:1.0.4
          imagePullPolicy: IfNotPresent
          livenessProbe:
            httpGet:
              scheme: HTTP
              port: 8081
              path: /health/health_check
            timeoutSeconds: 5
            successThreshold: 1
            periodSeconds: 30
            initialDelaySeconds: 5
            failureThreshold: 1
          ports:
            - containerPort: 8080
              name: internal-port
            - containerPort: 8081
              name: public-port
          resources:
            limits:
              cpu: 1000m
              memory: 500Mi
            requests:
              cpu: 500m
              memory: 500Mi
          volumeMounts:
            - mountPath: /entando-data
              name: cds-data-volume
      volumes:
        - name: cds-data-volume
          persistentVolumeClaim:
            claimName: $APP-cds-$TN-pvc
            readOnly: false
  replicas: 1
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $APP-cds-ingress
  namespace: $NS
  annotations:
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Scheme \$scheme;
      proxy_set_header X-Forwarded-Proto \$scheme;
      add_header Content-Security-Policy upgrade-insecure-requests;
    nginx.ingress.kubernetes.io/proxy-body-size: "150m"
    nginx.org/client-max-body-size: "150m"
spec:
  $INGRESS_CLASS_FIELD
  rules:
    - host: cds-$APP.$HOST
      http:
        paths:
          - backend:
              service:
                name: $APP-cds-$TN-service
                port:
                  number: 8081
            pathType: Prefix
            path: /$TN
          - backend:
              service:
                name: $APP-cds-$TN-service
                port:
                  number: 8080
            pathType: Prefix
            path: /api/v1/
#  tls:
#    - hosts:
#        - cds-$APP.$HOST
#      secretName: cds-tls
---
EOF
)

echo "CDS manifests" 
echo "$CDS_MANIFESTS"

echo "$CDS_MANIFESTS" | kubectl apply -n "${NS}" -f -

echo ""
echo "==== Wait 60 secs for cds $TN ===="
sleep 60

echo ""
echo "==== Retrieve access token ===="
ACCESS_TOKEN=$(curl -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET"  -X POST $PROTO://$APP.$HOST/auth/realms/entando/protocol/openid-connect/token -s | jq -r .access_token)
echo $ACCESS_TOKEN

echo ""
echo "==== upload file $FILE_NAME in http://cds-$APP.$HOST/api/v1/upload/ ===="

curl --location --request POST "http://cds-$APP.$HOST/api/v1/upload/" \
     --header "Authorization: Bearer $ACCESS_TOKEN" \
     --form 'path="archives"' \
     --form 'protected="false"' \
     --form "filename=\"$FILE_NAME\"" \
     --form "file=@\"$FILE_PATH\""



echo ""
echo ""
echo "==== decompress file $FILE_NAME http://cds-$APP.$HOST/api/v1/utils/decompress/$FILE_NAME ===="

curl --location -X GET "http://cds-$APP.$HOST/api/v1/utils/decompress/$FILE_NAME" \
     --header "Authorization: Bearer $ACCESS_TOKEN" 

echo ""
echo ""
echo "==== end ===="

