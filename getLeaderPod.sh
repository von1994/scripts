#!/bin/bash

# dependenies: jq

configmap=${1-"mysql-operator-leader-election"}
namespace=${2-"default"}
kubectl get cm ${configmap} -n ${namespace} -o=jsonpath='{.metadata.annotations.control-plane\.alpha\.kubernetes\.io\/leader}' | jq .holderIdentity |sed 's/\"//g'| cut -d "_" -f 1
