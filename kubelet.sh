#!/bin/sh

date_echo() {
    echo `date "+%H:%M:%S-%Y-%m-%d"` $1
}

date_echo "Starting to fix the possible issue..."

# fix orphaned pod, umount the mntpoint;
fix_orphanedPod(){
    secondPart=`echo $item | awk -F"Orphaned pod" '{print $2}'`
    podid=`echo $secondPart | awk -F"\"" '{print $2}'`

    # not process if the volume directory is not exist.
    if [ ! -d /var/lib/kubelet/pods/$podid/volumes/ ]; then
        continue
    fi
    # umount subpath if exist
    if [ -d /var/lib/kubelet/pods/$podid/volume-subpaths/ ]; then
        mountpath=`mount | grep /var/lib/kubelet/pods/$podid/volume-subpaths/ | awk '{print $3}'`
        for mntPath in $mountpath;
        do
             date_echo "Fix subpath Issue:: umount subpath $mntPath"
             umount $mntPath
             idleTimes=0
        done
    fi

    volumeTypes=`ls /var/lib/kubelet/pods/$podid/volumes/`
    for volumeType in $volumeTypes;
    do
         subVolumes=`ls -A /var/lib/kubelet/pods/$podid/volumes/$volumeType`
         if [ "$subVolumes" != "" ]; then
             date_echo "/var/lib/kubelet/pods/$podid/volumes/$volumeType contents volume: $subVolumes"
             for subVolume in $subVolumes;
             do
                 if [ "$volumeType" == "kubernetes.io~csi" ]; then
                     # check subvolume path is mounted or not
                     findmnt /var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume/mount
                     if [ "$?" != "0" ]; then
                         date_echo "/var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume/mount is not mounted, just need to remove"
                         content=`ls -A /var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume/mount`
                         # if path is empty, just remove the directory.
                         if [ "$content" = "" ]; then
                             rmdir /var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume/mount
                             rm -f /var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume/vol_data.json
                             rmdir /var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume
                         # if path is not empty, do nothing.
                         else
                             date_echo "/var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume/mount is not mounted, but not empty"
                             idleTimes=0
                         fi
                     # is mounted, umounted it first.
                     else
                         date_echo "Fix Orphaned Issue:: /var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume/mount is mounted, umount it"
                         umount /var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume/mount
                     fi
                 else
                     # check subvolume path is mounted or not
                     findmnt /var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume
                     if [ "$?" != "0" ]; then
                         date_echo "/var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume is not mounted, just need to remove"
                         content=`ls -A /var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume`
                         # if path is empty, just remove the directory.
                         if [ "$content" = "" ]; then
                             rmdir /var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume
                         # if path is not empty, do nothing.
                         else
                             date_echo "/var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume is not mounted, but not empty"
                             idleTimes=0
                         fi
                     # is mounted, umounted it first.
                     else
                         date_echo "Fix Orphaned Issue:: /var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume is mounted, umount it"
                         umount /var/lib/kubelet/pods/$podid/volumes/$volumeType/$subVolume
                     fi
                 fi
             done
         fi
         rm -rf /var/lib/kubelet/pods/$podid
         date_echo "remove /var/lib/kubelet/pods/$podid"
    done
}


idleTimes=0
IFS=$'\r\n'
#LONGRUNNING="True"
while :
do
    for item in `tail /var/log/messages`;
    do
        ## orphaned pod process
        if [[ $item == *"Orphaned pod"* ]] && [[ $item == *"but volume paths are still present on disk"* ]]; then
            fix_orphanedPod $item
        fi
    done

    idleTimes=`expr $idleTimes + 1`
    if [ "$idleTimes" = "10" ] && [ "$LONGRUNNING" != "True" ]; then
        break
    fi
    sleep 5
done

date_echo "Finish Process......"
