#!/usr/bin/env bash

# Worker node standalone setup scripts
# 1. Install docker & docker-compose
# 2. Setup docker daemon and listen port 2375
# 3. Mount master artifacts into work node
# 4. Setup firewall
# 5. Download docker image to work node


#
# Change echo color
#
echo_r () {
	[ $# -ne 1 ] && return 0
	echo -e "\033[31m$1\033[0m"
}
echo_g () {
	[ $# -ne 1 ] && return 0
	echo -e "\033[32m$1\033[0m"
}
echo_y () {
	[ $# -ne 1 ] && return 0
	echo -e "\033[33m$1\033[0m"
}
echo_b () {
	[ $# -ne 1 ] && return 0
	echo -e "\033[34m$1\033[0m"
}

pull_image() {
	[ $# -ne 1 ] && return 0
	name=$1
	[[ "$(sudo docker images -q ${name} 2> /dev/null)" == "" ]] \
	&& echo_r "Not found ${name}, may need some time to pull it down..." \
	&& sudo docker pull ${name}
}

#
# Setup docker daemon and listen port 2375
#
MASTER_NODE=${MASTER_NODE:-"127.0.0.1"}
echo_r "MASTER_NODE is ${MASTER_NODE}"

# Install docker & docker-compose if necessary
echo_b "Make sure docker and docker-compose are installed"
command -v docker >/dev/null 2>&1 || { echo_r >&2 "No docker-engine found, try installing"; curl -sSL https://get.docker.com/ | sh; }
command -v docker-compose >/dev/null 2>&1 || { echo_r >&2 "No docker-compose found, try installing"; sudo pip install 'docker-compose>=1.17.0'; }
# run a container to monitor docker daemon
docker run -d -v /var/run/docker.sock:/var/run/docker.sock -p 127.0.0.1:2375:2375 bobrik/socat TCP-LISTEN:2375,fork UNIX-CONNECT:/var/run/docker.sock

#
# Mount master artifacts into work node
#
echo_b "Copy required fabric 1.0, 1.1 and 1.2 artifacts"
ARTIFACTS_DIR=/opt/cello
USER=`whoami`
USERGROUP=`id -gn`
echo_b "Checking local artifacts path ${ARTIFACTS_DIR}..."
[ ! -d ${ARTIFACTS_DIR} ] \
	&& echo_r "Local artifacts path ${ARTIFACTS_DIR} not existed, creating one" \
	&& sudo mkdir -p ${ARTIFACTS_DIR} \
	&& sudo chown -R ${USER}:${USERGROUP} ${ARTIFACTS_DIR}

if [ -z "$MASTER_NODE" ]; then
	echo_r "No master node addr is provided, will ignore nfs setup"
else
	echo_b "Mount NFS Server ${MASTER_NODE}"
	sudo mount -t nfs -o vers=4,loud ${MASTER_NODE}:/ ${ARTIFACTS_DIR}
fi


#
# Setup firewall
#
echo_b "Setup ip forward rules"
sudo sysctl -w net.ipv4.ip_forward=1



#
# Download docker image to work node
#
ARCH_1_0=`uname -m | sed 's|i686|x86|' | sed 's|x64|x86_64|'`
BASEIMAGE_RELEASE_1_0=0.3.2
BASE_VERSION_1_0=1.0.5
PROJECT_VERSION_1_0=1.0.5
IMG_TAG_1_0=1.0.5
HLF_VERSION_1_0=1.0.5

ARCH_1_1=$ARCH_1_0
BASEIMAGE_RELEASE_1_1=0.4.6
BASE_VERSION_1_1=1.1.0
PROJECT_VERSION_1_1=1.1.0
IMG_TAG_1_1=1.1.0
HLF_VERSION_1_1=1.1.0

ARCH_1_2=$ARCH_1_0
BASEIMAGE_RELEASE_1_2=0.4.10
BASE_VERSION_1_2=1.2.0
PROJECT_VERSION_1_2=1.2.0
IMG_TAG_1_2=1.2.0
HLF_VERSION_1_2=1.2.0  # TODO: should be the same with src/common/utils.py

if [ $ARCH_1_2 = "x86_64" ];then
ARCH_1_2="amd64"
fi

function downloadImages() {
    ARCH=$1
    IMG_TAG=$2
    BASEIMAGE_RELEASE=$3
    HLF_VERSION=$4

    echo_b "Downloading fabric images from DockerHub...with tag = ${IMG_TAG}... need a while"
    # TODO: we may need some checking on pulling result?
    for IMG in peer tools orderer ca ccenv; do
        HLF_IMG=hyperledger/fabric-${IMG}:$ARCH-$IMG_TAG
        if [ -z "$(docker images -q ${HLF_IMG} 2> /dev/null)" ]; then  # not exist
            docker pull ${HLF_IMG}
        else
            echo_g "${HLF_IMG} already exist locally"
        fi
    done

    HLF_IMG=hyperledger/fabric-baseimage:$ARCH-$BASEIMAGE_RELEASE
    [ -z "$(docker images -q ${HLF_IMG} 2> /dev/null)" ] && docker pull ${HLF_IMG}
    HLF_IMG=hyperledger/fabric-baseos:$ARCH-$BASEIMAGE_RELEASE
    [ -z "$(docker images -q ${HLF_IMG} 2> /dev/null)" ] && docker pull ${HLF_IMG}

    # Only useful for debugging
    # docker pull yeasy/hyperledger-fabric

    echo_b "===Re-tagging fabric images to *:${HLF_VERSION}* tag"
    for IMG in peer tools orderer ca; do
        HLF_IMG=hyperledger/fabric-${IMG}
        docker tag ${HLF_IMG}:$ARCH-$IMG_TAG ${HLF_IMG}:${HLF_VERSION}
    done

    IMG_TAG=$5
    echo_b "Downloading and retag images for kafka/zookeeper separately, as their img_tag format is different"
    for IMG in kafka zookeeper; do
        HLF_IMG=hyperledger/fabric-${IMG}
        if [ -z "$(docker images -q ${HLF_IMG}:${HLF_VERSION} 2> /dev/null)" ]; then  # not exist
            docker pull ${HLF_IMG}:$ARCH-$IMG_TAG
            docker tag ${HLF_IMG}:$ARCH-$IMG_TAG ${HLF_IMG}:${HLF_VERSION}
        else
            echo_g "${HLF_IMG}:$ARCH-$IMG_TAG already exist locally"
        fi
    done
    echo_g "Done, now worker node should have all required images, use 'docker images' to check"
}

downloadImages $ARCH_1_0 $IMG_TAG_1_0 $BASEIMAGE_RELEASE_1_0 $HLF_VERSION_1_0 $IMG_TAG_1_0            #kafka and zookeeper have the same IMG_TAG as peer in 1.0
downloadImages $ARCH_1_1 $IMG_TAG_1_1 $BASEIMAGE_RELEASE_1_1 $HLF_VERSION_1_1 $BASEIMAGE_RELEASE_1_1  #kafka and zookeeper have the same IMG_TAG as baseimage in 1.1
downloadImages $ARCH_1_2 $IMG_TAG_1_2 $BASEIMAGE_RELEASE_1_2 $HLF_VERSION_1_2 $BASEIMAGE_RELEASE_1_2  #kafka and zookeeper have the same IMG_TAG as baseimage in 1.2
docker pull mysql:5.7


#
# Setup done
#
echo_g "Setup done"