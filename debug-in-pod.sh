#!/bin/bash

function e() {
   set -eu
   ns=${2-"default"}
   pod=`kubectl -n $ns describe pod $1 | grep -Eo 'docker://.*$' | head -n 1 | sed 's/docker:\/\/\(.*\)$/\1/'`
   pid=`docker inspect -f {{.State.Pid}} $pod`
   echo "enter pod netns and mntns successfully for $ns/$1 ."
   nsenter -n --target $pid -m
}

e $1 $2
