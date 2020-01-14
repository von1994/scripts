#!/bin/bash

#
# run cmd on master nodes: kubectl proxy --port=8001 --address=127.0.0.1
# or on work nodes: https://127.0.0.1:6443(redirect by nginx-proxy)

badNamespace=`kubectl get ns|awk '/Terminating/{print $1}'`
for ns in ${badNamespace[@]};do
  kubectl get ns $ns -ojson > tmp.json
  sed -i "/^.*\"kubernetes\"$/d" tmp.json
  curl -k -H "Content-Type: application/json" -X PUT --data-binary @tmp.json http://127.0.0.1:8001/api/v1/namespaces/$ns/finalize
done
