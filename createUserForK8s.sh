#!/bin/bash

set +e
set -o noglob

#
# Set Colors
#

bold=$(tput bold)
underline=$(tput sgr 0 1)
reset=$(tput sgr0)

red=$(tput setaf 1)
green=$(tput setaf 76)
white=$(tput setaf 7)
tan=$(tput setaf 202)
blue=$(tput setaf 25)

#
# Headers and Logging
#

underline() { printf "${underline}${bold}%s${reset}\n" "$@"
}
h1() { printf "\n${underline}${bold}${blue}%s${reset}\n" "$@"
}
h2() { printf "\n${underline}${bold}${white}%s${reset}\n" "$@"
}
debug() { printf "${white}%s${reset}\n" "$@"
}
info() { printf "${white}➜ %s${reset}\n" "$@"
}
success() { printf "${green}✔ %s${reset}\n" "$@"
}
error() { printf "${red}✖ %s${reset}\n" "$@"
}
warn() { printf "${tan}➜ %s${reset}\n" "$@"
}
bold() { printf "${bold}%s${reset}\n" "$@"
}
note() { printf "\n${underline}${bold}${blue}Note:${reset} ${blue}%s${reset}\n" "$@"
}

# set -e
set +o noglob


#
# Create user
#

USER_NAME=$1
USER_NAMESPACE=${USER_NAME}
SERVICE_ACCOUNT_NAME=${USER_NAME}
FORCE=${2-false}

bold "Input user: ${USER_NAME}
Input namespace: ${USER_NAMESPACE}
Input serviceaccount: ${SERVICE_ACCOUNT_NAME}
Mode: $FORCE"

function checkResourceExist(){
  RESOURCE_TYPE=$1
  RESOURCE_NAME=$2
  NAMESPACE=$3
  if [ `kubectl get ${RESOURCE_TYPE} ${RESOURCE_NAME} -n ${NAMESPACE}|wc -l` -eq 2 ]
  then
    # resource already exists.
    info "Resources ${RESOURCE_TYPE}/${RESOURCE_NAME} already exists in ${NAMESPACE}"
    return 1
  fi
  # to be created.
  return 0
}

function createServiceaccount(){
  checkResourceExist "serviceaccount" ${SERVICE_ACCOUNT_NAME} ${USER_NAMESPACE}
  if [ $? -eq 1 ] && ! ${FORCE}
  then
    error "ServiceAccount ${SERVICE_ACCOUNT_NAME} already exists."
  elif [ $? -eq 0 ]
  then
    kubectl create serviceaccount ${SERVICE_ACCOUNT_NAME} -n ${USER_NAMESPACE}
    if [ $? -ne 0 ]
    then
      error "Creating serviceaccount ${SERVICE_ACCOUNT_NAME} failed."
    fi
    success "created serviceaccount ${SERVICE_ACCOUNT_NAME}"
  fi
}

function createRole(){
  checkResourceExist "role" ${USER_NAME} ${USER_NAMESPACE}
  if [ $? -eq 1 ] && ! ${FORCE}
  then
    error "Role ${USER_NAME} already exists."
  elif [ $? -eq 0 ]
  then
    kubectl create role ${USER_NAME} --verb="*" --resource="*" -n ${USER_NAMESPACE}
    if [ $? -ne 0 ]
    then
      error "Creating role ${USER_NAME} failed."
    fi
    success "created role ${USER_NAME}"
  fi
}

function createRolebinding(){
  checkResourceExist "rolebinding" ${USER_NAME} ${USER_NAMESPACE}
  if [ $? -eq 1 ] && ! ${FORCE}
  then
    error "Rolebinding ${USER_NAME} already exists."
  elif [ $? -eq 0 ]
  then
    kubectl create rolebinding ${USER_NAME} --role=${USER_NAME} --serviceaccount==${USER_NAMESPACE}:${SERVICE_ACCOUNT_NAME} -n ${USER_NAMESPACE}
    if [ $? -ne 0 ]
    then
      error "Creating rolebinding ${USER_NAME} failed."
    fi
    success "created rolebinding ${USER_NAME}"
  fi
}


#
# Validate namespace exists or not
#

function validateNamespace(){
  if [ `kubectl get ns |grep ${USER_NAMESPACE}|wc -l` -eq 0 ]
  then
    info "Namespace ${USER_NAMESPACE} doesn't exist."
    kubectl create ns ${USER_NAMESPACE}
    if [ $? != 0 ]
    then
      error "Creating namespace ${USER_NAMESPACE} failed."
      exit 1
    fi
    success "created namespace ${USER_NAMESPACE}"
  else
    if ! ${FORCE}
    then
      warn "Cannot create new namespace ${USER_NAMESPACE}, exit"
      exit 1
    fi
    underline "Namespace already exists, won't create."
  fi 
}


#
# Generate kubeconfig
#

function generateKubecfg(){
  CONTEXT=$(kubectl config current-context)
  NAMESPACE=${USER_NAMESPACE}
  
  NEW_CONTEXT=${USER_NAME}
  KUBECONFIG_FILE="kubeconfig-${SERVICE_ACCOUNT_NAME}"
  
  
  SECRET_NAME=$(kubectl get serviceaccount ${SERVICE_ACCOUNT_NAME} \
    --context ${CONTEXT} \
    --namespace ${NAMESPACE} \
    -o jsonpath='{.secrets[0].name}')
  TOKEN_DATA=$(kubectl get secret ${SECRET_NAME} \
    --context ${CONTEXT} \
    --namespace ${NAMESPACE} \
    -o jsonpath='{.data.token}')
  
  TOKEN=$(echo ${TOKEN_DATA} | base64 -d)
  
  # Create dedicated kubeconfig
  # Create a full copy
  kubectl config view --raw > ${KUBECONFIG_FILE}.full.tmp
  # Switch working context to correct context
  kubectl --kubeconfig ${KUBECONFIG_FILE}.full.tmp config use-context ${CONTEXT}
  # Minify
  kubectl --kubeconfig ${KUBECONFIG_FILE}.full.tmp \
    config view --flatten --minify > ${KUBECONFIG_FILE}.tmp
  # Rename context
  kubectl config --kubeconfig ${KUBECONFIG_FILE}.tmp \
    rename-context ${CONTEXT} ${NEW_CONTEXT}
  # Create token user
  kubectl config --kubeconfig ${KUBECONFIG_FILE}.tmp \
    set-credentials ${CONTEXT}-${NAMESPACE}-token-user \
    --token ${TOKEN}
  # Set context to use token user
  kubectl config --kubeconfig ${KUBECONFIG_FILE}.tmp \
    set-context ${NEW_CONTEXT} --user ${CONTEXT}-${NAMESPACE}-token-user
  # Set context to correct namespace
  kubectl config --kubeconfig ${KUBECONFIG_FILE}.tmp \
    set-context ${NEW_CONTEXT} --namespace ${NAMESPACE}
  # Flatten/minify kubeconfig
  kubectl config --kubeconfig ${KUBECONFIG_FILE}.tmp \
    view --flatten --minify > ${KUBECONFIG_FILE}
  # Remove tmp
  rm ${KUBECONFIG_FILE}.full.tmp
  rm ${KUBECONFIG_FILE}.tmp
  
  success "generated kubeconfig"
}

function destroy(){
  kubectl delete sa ${SERVICE_ACCOUNT_NAME} -n ${USER_NAMESPACE}
  kubectl delete role ${USER_NAME} -n ${USER_NAMESPACE}
  kubectl delete rolebinding ${USER_NAME} -n ${USER_NAMESPACE}
  kubectl delete ns ${USER_NAMESPACE}
}

function main(){
  validateNamespace
  createServiceaccount
  createRole
  createRolebinding
  generateKubecfg 
}

main
