#!/bin/bash

########################################################################################################################
### 
### Configuration script for JMeter environment in OpenShift.
### Contributed By: CK Gan (chgan@redhat.com)
### Complete setup guide and documentation at https://github.com/chengkuangan/jmeter-container
### 
########################################################################################################################

APPS_NAMESPACE="kafka-jmeter"
APPS_PROJECT_DISPLAYNAME="Kafka Load Testing"
OC_USER=""
PROCEED_INSTALL="no"

KAFKA_CLUSTER_NAME="kafka-cluster"
KAFKA_TEMPLATE_FILENAME="kafka-persistent.yaml"
PARTITION_REPLICA_NUM=3
TOPIC_PARTITION_NUM="3"
KAFKA_TOPIC="jmeter-kafka"
KAFKA_VERSION="2.5.0"
KAFKA_LOGFORMAT_VERSION="2.5"


RED='\033[1;31m'
NC='\033[0m' # No Color
GREEN='\033[1;32m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
YELLOW='\033[1;33m'

function init(){
    
    set echo off
    OC_USER="$(oc whoami)"
    set echo on
    
    if [ $? -ne 0 ] || [ "$OC_USER" = "" ]; then
        echo
        printWarning "Please login to Openshift before proceed ..."
        echo
        exit 0
    fi
    echo
    printHeader "--> Creating temporary directory ../tmp"
    mkdir ../tmp

    printHeader "--> Create OpenShift required projects if not already created"

    oc new-project $APPS_NAMESPACE
    
}

#function validates(){
    #if [ $PARTITION_REPLICA_NUM < 2 ]; then
    #    printWarning "PARTITION_REPLICA_NUM must be at least 2."
    #    exit 0
    #fi
#}

function printTitle(){
    HEADER=$1
    echo -e "${RED}$HEADER${NC}"
}

function printHeader(){
    HEADER=$1
    echo -e "${YELLOW}$HEADER${NC}"
}

function printLink(){
    LINK=$1
    echo -e "${GREEN}$LINK${NC}"
}

function printCommand(){
    COMMAND=$1
    echo -e "${GREEN}$COMMAND${NC}"
}

function printWarning(){
    WARNING=$1
    echo -e "${RED}$WARNING${NC}"
}

function printError(){
    ERROR=$1
    echo -e "${RED}$ERROR${NC}"
}

function printVariables(){
    echo 
    printHeader "The following is the parameters enter..."
    echo
    echo "APPS_NAMESPACE = $APPS_NAMESPACE"
    echo "APPS_PROJECT_DISPLAYNAME = $APPS_PROJECT_DISPLAYNAME"
    echo "OC_USER = $OC_USER"
    echo "KAFKA_CLUSTER_NAME = $KAFKA_CLUSTER_NAME"
    echo "KAFKA_TEMPLATE_FILENAME = $KAFKA_TEMPLATE_FILENAME"
    echo "PARTITION_REPLICA_NUM = $PARTITION_REPLICA_NUM"
    echo "TOPIC_PARTITION_NUM = $TOPIC_PARTITION_NUM"
    echo "KAFKA_TOPIC = $KAFKA_TOPIC"
    echo "KAFKA_VERSION = $KAFKA_VERSION" 
    echo "KAFKA_LOGFORMAT_VERSION = $KAFKA_LOGFORMAT_VERSION"
    echo

}

## ==================================================
## ---- Common steps to confighure Prometheus 
## ==================================================
function configurePrometheus(){

    echo
    printHeader "--> Configure Prometheus for $APPS_NAMESPACE namespace ... "
    echo
    
    echo
    echo "Creating the cluster-monitoring-config configmap ... "
    echo
    oc apply -f ../templates/cluster-monitoring-config.yaml  -n openshift-monitoring
    
    catchError "Error creating clustermonitoring-config configmap."

    echo
    echo "Configuring Grafana for $APPS_NAMESPACE namespace ... "
    echo
    cp ../templates/grafana-sa.yaml ../tmp/grafana-sa.yaml
    catchError "Error copying ../templates/grafana-sa.yaml."
    sed -i -e "s/myproject/$APPS_NAMESPACE/" ../tmp/grafana-sa.yaml
    catchError "Error sed ../tmp/grafana-sa.yaml."
    oc apply -f ../tmp/grafana-sa.yaml -n $APPS_NAMESPACE
    catchError "Error oc applying ../tmp/grafana-sa.yaml."

    GRAFANA_SA_TOKEN="$(oc serviceaccounts get-token grafana-serviceaccount -n $APPS_NAMESPACE)"
    catchError "Error get-token for grafana-serviceaccount"
    cp ../templates/datasource.yaml ../tmp/datasource.yaml
    catchError "Error copying ../templates/datasource.yaml."
    sed -i -e "s/GRAFANA-ACCESS-TOKEN/$GRAFANA_SA_TOKEN/" ../tmp/datasource.yaml
    catchError "Error sed for ../tmp/datasource.yaml"
    oc create configmap grafana-config --from-file=../tmp/datasource.yaml -n $APPS_NAMESPACE
    catchError "Error create configmap grafana-config"
    oc apply -f ../templates/grafana.yaml -n $APPS_NAMESPACE
    catchError "Error applying ../templates/grafana.yaml"
    oc create route edge grafana --service=grafana -n $APPS_NAMESPACE
    catchError "Error create route edge grafana"
}

function catchError(){
    if [ $? -ne 0 ]; then
        echo
        printError "Error running the command ... Please see the previous command line."
        echo
        printError $1
        removeTempDirs
        exit 0
    fi
}

function configurePrometheus4JMeter(){

    echo
    printHeader "--> Configure Prometheus for JMeter ... "
    echo
    
    cp ../templates/jmeter/prometheus/jmeter-service-monitor.yml ../tmp/jmeter-service-monitor.yml
    catchError "Error copying ../templates/jmeter/prometheus/jmeter-service-monitor.yml"
    sed -i -e "s/myproject/$APPS_NAMESPACE/" ../tmp/jmeter-service-monitor.yml
    catchError "Error sed ../tmp/jmeter-service-monitor.yml"
    oc apply -f ../tmp/jmeter-service-monitor.yml  -n $APPS_NAMESPACE
    catchError "Error applying ../tmp/jmeter-service-monitor.yml"
}

function configurePrometheus4Kafka(){

    echo
    printHeader "--> Configuring Prometheus for Kafka in namespace $APPS_NAMESPACE ... "
    echo
    
    cp ../templates/kafka/prometheus/strimzi-pod-monitor.yaml ../tmp/strimzi-pod-monitor.yaml
    catchError "Error copying ../templates/kafka/prometheus/strimzi-pod-monitor.yaml"
    sed -i -e "s/myproject/$APPS_NAMESPACE/" ../tmp/strimzi-pod-monitor.yaml
    catchError "Error sed ../tmp/strimzi-pod-monitor.yaml"
    oc apply -f ../tmp/strimzi-pod-monitor.yaml  -n $APPS_NAMESPACE
    catchError "Error applying ../tmp/strimzi-pod-monitor.yaml"
    oc apply -f ../templates/kafka/prometheus/prometheus-rules.yaml  -n $APPS_NAMESPACE
    catchError "Error applyting ../templates/kafka/prometheus/prometheus-rules.yaml"
}

function deployKafka(){
    echo
    printHeader "--> Modifying ../templates/kafka/$KAFKA_TEMPLATE_FILENAME"
    echo
    
    cp ../templates/kafka/$KAFKA_TEMPLATE_FILENAME ../tmp/$KAFKA_TEMPLATE_FILENAME
    catchError "Error copying ../templates/kafka/$KAFKA_TEMPLATE_FILENAME"
    sed -i -e "s/version:.*/version: $KAFKA_VERSION/" ../tmp/$KAFKA_TEMPLATE_FILENAME
    catchError "Error sed ../tmp/$KAFKA_TEMPLATE_FILENAME"
    sed -i -e "s/log.message.format.version:.*/log.message.format.version: \"$KAFKA_LOGFORMAT_VERSION\"/" ../tmp/$KAFKA_TEMPLATE_FILENAME
    catchError "Error sed ../tmp/$KAFKA_TEMPLATE_FILENAME"
    sed -i -e "s/kafka-sizing/$APPS_NAMESPACE/" ../tmp/$KAFKA_TEMPLATE_FILENAME
    catchError "Error sed ../tmp/$KAFKA_TEMPLATE_FILENAME"
    sed -i -e "s/my-cluster/$KAFKA_CLUSTER_NAME/" ../tmp/$KAFKA_TEMPLATE_FILENAME
    catchError "Error sed ../tmp/$KAFKA_TEMPLATE_FILENAME"
    sed -i -e "s/transaction.state.log.min.isr:.*/transaction.state.log.min.isr: $(($PARTITION_REPLICA_NUM-1))/" ../tmp/$KAFKA_TEMPLATE_FILENAME
    catchError "Error sed ../tmp/$KAFKA_TEMPLATE_FILENAME"
    sed -i -e "s/min.insync.replicas:.*/min.insync.replicas: $(($PARTITION_REPLICA_NUM-1))/" ../tmp/$KAFKA_TEMPLATE_FILENAME
    catchError "Error sed ../tmp/$KAFKA_TEMPLATE_FILENAME"
    echo 
    printHeader "--> Deploying AMQ Streams (Kafka) Cluster now ... Using ../templates/kafka/$KAFKA_TEMPLATE_FILENAME ..."
    oc apply -f ../tmp/$KAFKA_TEMPLATE_FILENAME -n $APPS_NAMESPACE
    catchError "Error applying ../tmp/$KAFKA_TEMPLATE_FILENAME"
    
}

function createKafkaTopic(){
    echo
    printHeader "--> Creating Kafka Topic ..."
    echo
    cp ../templates/kafka/kafka-topic.yaml ../tmp/kafka-topic.yaml
    catchError "Error copying ../templates/kafka/kafka-topic.yaml"
    sed -i -e "s/mytopic/$KAFKA_TOPIC/" ../tmp/kafka-topic.yaml
    catchError "Error sed ../tmp/kafka-topic.yaml"
    sed -i -e "s/mycluster/$KAFKA_CLUSTER_NAME/" ../tmp/kafka-topic.yaml
    catchError "Error sed ../tmp/kafka-topic.yaml"
    sed -i -e "s/partitions:.*/partitions: $TOPIC_PARTITION_NUM/" ../tmp/kafka-topic.yaml
    catchError "Error sed ../tmp/kafka-topic.yaml"
    sed -i -e "s/replicas:.*/replicas: $PARTITION_REPLICA_NUM/" ../tmp/kafka-topic.yaml
    catchError "Error sed ../tmp/kafka-topic.yaml"
    oc apply -f ../tmp/kafka-topic.yaml -n $APPS_NAMESPACE
    catchError "Error applying ../tmp/kafka-topic.yaml"
    echo
}

function deployKafkaRelated(){
    deployKafka
    createKafkaTopic
    configurePrometheus4Kafka
}

function deployJMeterRelated(){
    configurePrometheus4JMeter
}

# ----- Remove all tmp content after completed.
function removeTempDirs(){
    echo
    printHeader "--> Removing ../tmp directory ... "
    echo
    rm -rf ../tmp
}

# ----- read user inputs for installation parameters
function readInput(){
    INPUT_VALUE=""
    echo
    printHeader "Please provides the following parameter values. (Enter q to quit)"
    echo
    while [ "$INPUT_VALUE" != "q" ]
    do  
    
        printf "Namespace [$APPS_NAMESPACE]:"
        read INPUT_VALUE
        if [ "$INPUT_VALUE" != "" ] && [ "$INPUT_VALUE" != "q" ]; then
            APPS_NAMESPACE="$INPUT_VALUE"
        fi
        
        checkQuitInput $INPUT_VALUE

        printf "Kafka Cluster Name [$KAFKA_CLUSTER_NAME]:"
        read INPUT_VALUE
        if [ "$INPUT_VALUE" != "" ] && [ "$INPUT_VALUE" != "q" ]; then
            KAFKA_CLUSTER_NAME="$INPUT_VALUE"
        fi

        checkQuitInput $INPUT_VALUE

        printf "Kafka Version [$KAFKA_VERSION]:"
        read INPUT_VALUE
        if [ "$INPUT_VALUE" != "" ] && [ "$INPUT_VALUE" != "q" ]; then
            KAFKA_VERSION="$INPUT_VALUE"
        fi

        checkQuitInput $INPUT_VALUE

        printf "Kafka Log Format Version [$KAFKA_LOGFORMAT_VERSION]:"
        read INPUT_VALUE
        if [ "$INPUT_VALUE" != "" ] && [ "$INPUT_VALUE" != "q" ]; then
            KAFKA_LOGFORMAT_VERSION="$INPUT_VALUE"
        fi

        checkQuitInput $INPUT_VALUE

        printf "No of Partition [$TOPIC_PARTITION_NUM]:"
        read INPUT_VALUE
        if [ "$INPUT_VALUE" != "" ] && [ "$INPUT_VALUE" != "q" ]; then
            TOPIC_PARTITION_NUM="$INPUT_VALUE"
        fi

        checkQuitInput $INPUT_VALUE

        printf "No of Replica per Partition [$PARTITION_REPLICA_NUM]:"
        read INPUT_VALUE
        if [ "$INPUT_VALUE" != "" ] && [ "$INPUT_VALUE" != "q" ]; then
            PARTITION_REPLICA_NUM="$INPUT_VALUE"
        fi

        checkQuitInput $INPUT_VALUE

        printf "Kafka Topic [$KAFKA_TOPIC]:"
        read INPUT_VALUE
        if [ "$INPUT_VALUE" != "" ] && [ "$INPUT_VALUE" != "q" ]; then
            KAFKA_TOPIC="$INPUT_VALUE"
        fi

        checkQuitInput $INPUT_VALUE

        #if [ "$INPUT_VALUE" = "q" ]; then
        #    removeTempDirs
        #    exit 0
        #fi        
        INPUT_VALUE="q"
    done
}

function checkQuitInput(){
    local input=$1
    if [ "$input" = "q" ]; then
        removeTempDirs
        exit 0
    fi   
}

# Check if a resource exist in OCP
check_resource() {
  local kind=$1
  local name=$2
  oc get $kind $name -o name >/dev/null 2>&1
  if [ $? != 0 ]; then
    echo "false"
  else
    echo "true"
  fi
}

function printCmdUsage(){
    echo 
    echo "This is script to configure Prometheus and Grafana for JMeter on OpenShift."
    echo
    echo "Command usage: ./deploy.sh <options>"
    echo 
    echo "-h            Show complete help info."
    echo "-i            Deploy the environment for Kafka load testing."
    #echo "-j            Configure Prometheus and Grafana for JMeter."
    #echo "-k            Deploy Kafka cluster, and configure Prometheus & Grafana for Kafka."
    echo 
}

function printHelp(){
    printCmdUsage
    echo "This script is designed for OpenShift 4.5 and above."
    echo
    printHeader "Refer to the following website for the complete and updated guide ..."
    echo
    printLink "https://github.com/chengkuangan/jmeter-container"
    echo
}

function printResult(){
    echo 
    echo "=============================================================================================================="
    echo 
    printTitle "The Prometheus and Grafana environment is configured successfully for JMeter on OpenShift @ $APPS_NAMESPACE"
    echo
    echo "=============================================================================================================="
    echo
}

function processArguments(){

    if [ $# -eq 0 ]; then
        printCmdUsage
        exit 0
    fi

    while (( "$#" )); do
      if [ "$1" == "-h" ]; then
        printHelp
        exit 0
      # Proceed to install
      elif [ "$1" == "-i" ]; then
        PROCEED_INSTALL="yes"
        shift
      else
        echo "Unknown argument: $1"
        printCmdUsage
        exit 0
      fi
      shift
    done
}

function showConfirmToProceed(){
    echo
    printWarning "Press ENTER (OR Ctrl-C to cancel) to proceed..."
    read bc
}

processArguments $@
readInput
printVariables

if [ "$PROCEED_INSTALL" != "yes" ]; then
    removeTempDirs
    exit 0
fi

init
showConfirmToProceed
configurePrometheus
deployKafkaRelated
deployJMeterRelated
removeTempDirs
printResult