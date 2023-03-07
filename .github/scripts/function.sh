#!/bin/bash


function checkDeploy() {
  TIMEOUT=30
  app=$1
  tag=$2
  namespace=$3
  cd $GITHUB_WORKSPACE
  echo "[INFO] check deployment $app tag=$tag on $namespace..."
  sleep $TIMEOUT
  healthcheckOK=0
  for (( i=1; i<=$TIMEOUT; i++ )); do
    podName=''
    podName=`kubectl get pod -l app=${app} -n $namespace | grep Running | grep -E '1/1|2/2|3/3' | head -n1 | awk '{print $1}'` || true
    if [[ ! -z $podName ]]; then
      podImage=`kubectl get pod $podName -n $namespace -o json | jq -re '.spec.containers[0].image'`
      echo "[INFO] Current $podName image is $podImage"
      if [[ ! -z $podImage ]] && [[ $podImage == *$tag ]]; then
        healthcheckOK=1
        break
      fi
    fi
  sleep 10
  echo "[INFO] Continue next loop..."
  done
  if [[ $healthcheckOK -eq 1 ]]; then
    echo "[INFO] Deployment $app tag=$tag is done......"
  else
    echo "[ERROR] Deployment $app tag=$tag is failure......"
    exit 1
  fi
}

function healthCheck() {
  TIMEOUT=30
  app=$1
  port=$2
  urlPath=$3
  namespace=$4
  cd $GITHUB_WORKSPACE
  echo "[INFO] Starting healthcheck http://$app:$port$urlPath at namespace=$namespace ..."
  healthcheckOK=0
  for (( i=1; i<=$TIMEOUT; i++ )); do
    #ret=`curl -o /dev/null -s -w "%{http_code}\n" "http://$APP:$PORT$URL_PATH"` || true
    cmd='ret=`curl -o /dev/null -s -w "%{http_code}\\n" '"'http://$app:$port$urlPath'"'` && exit $ret'
    randomStr=`date '+%Y%m%d-%H%M%S'`-`openssl rand -hex 4`
    echo "[INFO] randomStr=$randomStr"
    ret=0
    kubectl run curl-${randomStr} --rm -it -n $namespace --restart=Never --image="debu99/curl" -- bash -c "${cmd}" || ret=$?
    if [[ ${ret} -eq 200 ]]; then
      healthcheckOK=1
      echo "[INFO] $i - curl returns 200 from $1, continue to next step..."
      kubectl delete pod curl-${randomStr} --ignore-not-found -n $namespace || true
      kubectl get pod -n $namespace | grep $app || true
      break
    else
      echo "[INFO] $i - curl returns $((ret+256)) from $1, retrying..."
      kubectl delete pod curl-${randomStr} -n $namespace --ignore-not-found || true
      kubectl get pod  -n $namespace | grep $app || true
      sleep 5
    fi
  done
  if [[ $healthcheckOK -eq 1 ]]; then
    echo "[INFO] Done healthcheck......"
  else
    echo "[ERROR] Healthcheck failure......"
    exit 1
  fi
}