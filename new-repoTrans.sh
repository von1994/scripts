#!/usr/bin/env bash

function local_re_tag {
    old_images=`docker images | awk '{if ($1~/harbor.enmotech.com\/enmotech-ncm/) print $1":"$2}'`
    echo $old_images
    new_images=`echo ${old_images} | sed 's@harbor.enmotech.com/enmotech-ncm@harbor.enmotech.com\/library@g'`
    echo $new_images
    for i in "${!old_images[@]}"
    do
        docker tag ${old_images[$i]} ${new_images[$i]}
        if [ "$?" == "0" ]; then
            echo "docker tag ${old_images[$i]} ${new_images[$i]} successfully!"
        fi
    done
}
#wait_pull_images=(
#	gcr.io/istio-release/proxyv2:1.0.2
#	gcr.io/istio-release/citadel:1.0.2
#	gcr.io/istio-release/galley:1.0.2
#	gcr.io/istio-release/grafana:1.0.2
#	gcr.io/istio-release/mixer:1.0.2
#	gcr.io/istio-release/pilot:1.0.2
#	gcr.io/istio-release/proxy_init:1.0.2
#	gcr.io/istio-release/servicegraph:1.0.2
#	gcr.io/istio-release/sidecar_injector:1.0.2
#)

docker_cmd=`which docker`

function pull_image {
    ${docker_cmd} pull $1
    if [ "$?" == "0" ]; then
        info "pulled image $1 successfully!"
    else
        error "some error occured, pulling image $1 failed!please check the repo name."
    fi
}

function push_image {
    ${docker_cmd} push $1
    if [ "$?" == "0" ]; then
        info "pushed image $1 successfully!"
    else
        error "some error occured, pushing image $1 failed!please check the repo name."
    fi
}

function rename_image {
    old_name=$1
    new_name=$2
    ${docker_cmd} tag ${old_name} ${new_name}
    push_image ${new_name}
}

function error {
    #echo -e "\e[31m $@ \e[0m"
    echo $@
}

function info {
    #echo -e "\e[32m $@ \e[0m"
    echo $@
}

#to_images=(${from_image[@]/gcr.io/harbor.allseeingsecurity.net})

function pull_and_rename {
    for image in ${wait_pull_images[@]}
    do
    	info handling image: ${image}
    	pull_image ${image}
        rename_image ${image} 
    done
}

function pull_and_rename {
    for image in ${wait_pull_images[@]}
    do
    	info handling image: ${image}
        rename_image ${image}
    done
}

local_re_tag
