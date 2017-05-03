#!/bin/bash

# This script is for deploying EnMasse into OpenShift. The target of
# installation can be an existing OpenShift deployment or an all-in-one
# container can be started.
#
# In either case, access to the `oc` command is required.
#
# example usage:
#
#    $ enmasse-deploy.sh -c 10.0.1.100 -o enmasse.10.0.1.100.xip.io
#
# this will deploy EnMasse into the OpenShift cluster running at 10.0.1.100
# and set the EnMasse webui route url to enmasse.10.0.1.100.xip.io.
# further it will use the user `developer` and project `myproject`, asking
# for a login when appropriate.
# for further parameters please see the help text.
if which oc &> /dev/null
then :
else
    echo "Cannot find oc command, please check path to ensure it is installed"
    exit 1
fi

function runcmd() {
    local cmd=$1
    local description=$2

    if [ -z $GUIDE ]; then
        eval $cmd
    else
        echo "$description:"
        echo ""
        echo "    $cmd"
        echo ""
    fi
}

function docmd() {
    local cmd=$1
    if [ -z $GUIDE ]; then
        $cmd
    fi
}

ENMASSE_TEMPLATE_MASTER_URL=https://raw.githubusercontent.com/EnMasseProject/enmasse/master/generated
TEMPLATE_NAME=enmasse
TEMPLATE_PARAMS=""

DEFAULT_OPENSHIFT_USER=developer
DEFAULT_OPENSHIFT_PROJECT=myproject
OC_ARGS=""

while getopts c:dgk:mo:p:s:t:u:yhv opt; do
    case $opt in
        c)
            OS_CLUSTER=$OPTARG
            ;;
        d)
            OS_ALLINONE=true
            ;;
        g)
            GUIDE=true
            ;;
        k)
            SERVER_KEY=$OPTARG
            ;;
        m)
            TEMPLATE_PARAMS="MULTIINSTANCE=true $TEMPLATE_PARAMS"
            ;;
        o)
            TEMPLATE_PARAMS="INSTANCE_MESSAGING_HOST=$OPTARG $TEMPLATE_PARAMS"
            ;;
        p)
            PROJECT=$OPTARG
            ;;
        s)
            SERVER_CERT=$OPTARG
            ;;
        t)
            ALT_TEMPLATE=$OPTARG
            ;;
        u)
            OS_USER=$OPTARG
            USER_REQUESTED=true
            ;;
        y)
            OC_ARGS="--insecure-skip-tls-verify=true"
            ;;
        v)
            set -x
            ;;
        h)
            echo "usage: enmasse-deploy.sh [options]"
            echo
            echo "deploy the EnMasse suite into a running OpenShift cluster"
            echo
            echo "optional arguments:"
            echo "  -h             show this help message"
            echo "  -c CLUSTER     OpenShift cluster url to login against (default: https://localhost:8443)"
            echo "  -d             create an all-in-one docker OpenShift on localhost"
            echo "  -k KEY         Server key file (default: none)"
            echo "  -m             Set multiinstance mode"
            echo "  -o HOSTNAME    Custom hostname for messaging endpoint (default: use autogenerated from template)"
            echo "  -p PROJECT     OpenShift project name to install EnMasse into (default: $DEFAULT_OPENSHIFT_PROJECT)"
            echo "  -s CERT        Server certificate file (default: none)"
            echo "  -t TEMPLATE    An alternative opan OpenShift template file to deploy EnMasse (default: curl'd from upstream)"
            echo "  -u USER        OpenShift user to run commands as (default: $DEFAULT_OPENSHIFT_USER)"
            echo
            exit
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit
            ;;
    esac
done

if [ -z "$OS_USER" ]
then
    OS_USER=$DEFAULT_OPENSHIFT_USER
fi

if [ -z "$PROJECT" ]
then
    PROJECT=$DEFAULT_OPENSHIFT_PROJECT
fi

if [ -n "$OS_ALLINONE" ]
then
    if [ -n "$OS_CLUSTER" ]
    then
        echo "Error: You have requested an all-in-one deployment AND specified a cluster address."
        echo "Please choose one of these options and restart."
        exit 1
    fi
    if [ -n "$USER_REQUESTED" ]
    then
        echo "Error: You have requested an all-in-one deployment AND specified an OpenShift user."
        echo "Please choose either all-in-one or a cluster deployment if you need to use a specific user."
        exit 1
    fi
    runcmd "sudo oc cluster up" "Start local OpenShift cluster"
fi


runcmd "oc login -u $OS_USER $OC_ARGS $OC_CLUSTER" "Login as $OS_USER"

AVAILABLE_PROJECTS=`docmd "oc projects -q"`

for proj in $AVAILABLE_PROJECTS
do
    if [ "$proj" == "$PROJECT" ]; then
        runcmd "oc project $proj" "Select project"
        break
    fi
done

CURRENT_PROJECT=`docmd "oc project -q"`
if [ "$CURRENT_PROJECT" != "$PROJECT" ]; then
    runcmd "oc new-project $PROJECT" "Create new project $PROJECT"
fi

runcmd "oc create sa enmasse-service-account -n $PROJECT" "Create service account for address controller"
runcmd "oc policy add-role-to-user view system:serviceaccount:${PROJECT}:default" "Add permissions for viewing OpenShift resources to default user"
runcmd "oc policy add-role-to-user edit system:serviceaccount:${PROJECT}:enmasse-service-account" "Add permissions for editing OpenShift resources to EnMasse service account"

if [ -n "$MULTIINSTANCE" ]; then
    echo "Please grant cluster-admin rights to system:serviceaccount:${PROJECT}:enmasse-service-account before creating instances: 'oadm policy add-cluster-role-to-user cluster-admin system:serviceaccount:${PROJECT}:enmasse-service-account'"
fi

if [ -z "$MULTIINSTANCE" ] && [ -n "$SERVER_KEY" ] && [ -n "$SERVER_CERT" ]
then
    runcmd "oc secret new ${PROJECT}-certs ${SERVER_CERT} ${SERVER_KEY}" "Create certificate secret"
    runcmd "oc secret add serviceaccount/default secrets/${PROJECT}-certs --for=mount" "Add certificate secret to default service account"
    TEMPLATE_PARAMS="INSTANCE_CERT_SECRET=${PROJECT}-certs ${TEMPLATE_PARAMS}"
fi

if [ -n "$ALT_TEMPLATE" ]
then
    ENMASSE_TEMPLATE=$ALT_TEMPLATE
else
    ENMASSE_TEMPLATE=${ENMASSE_TEMPLATE_MASTER_URL}/${TEMPLATE_NAME}-template.yaml
fi

runcmd "oc process -f $ENMASSE_TEMPLATE $TEMPLATE_PARAMS | oc create -n $PROJECT -f -" "Instantiate EnMasse template"
