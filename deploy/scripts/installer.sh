#!/bin/bash
function showhelp {
    echo ""
    echo "#########################################################################################"
    echo "#                                                                                       #"
    echo "#                                                                                       #" 
    echo "#   This file contains the logic to deploy the different systems                        #" 
    echo "#   The script experts the following exports:                                           #" 
    echo "#                                                                                       #" 
    echo "#     ARM_SUBSCRIPTION_ID to specify which subscription to deploy to                    #" 
    echo "#     DEPLOYMENT_REPO_PATH the path to the folder containing the cloned sap-hana        #" 
    echo "#                                                                                       #" 
    echo "#   The script will persist the parameters needed between the executions in the         #" 
    echo "#   ~/.sap_deployment_automation folder                                                 #" 
    echo "#                                                                                       #" 
    echo "#                                                                                       #" 
    echo "#   Usage: installer.sh                                                                 #"
    echo "#    -p parameter file                                                                  #"
    echo "#    -i interactive true/false setting the value to false will not prompt before apply  #"
    echo "#    -h Show help                                                                       #"
    echo "#                                                                                       #" 
    echo "#   Example:                                                                            #" 
    echo "#                                                                                       #" 
    echo "#   [REPO-ROOT]deploy/scripts/install_deployer.sh \                                     #"
	echo "#      -p PROD-WEEU-DEP00-INFRASTRUCTURE.json \                                         #"
	echo "#      -i true                                                                          #" 
    echo "#                                                                                       #" 
    echo "#########################################################################################"
}

show_help=false

while getopts ":p:t:i:d:h" option; do
    case "${option}" in
        p) parameterfile=${OPTARG};;
        t) deployment_system=${OPTARG};;
        i) approve="--auto-approve";;
        h) showhelp
           exit 3
           ;;
        ?) echo "Invalid option: -${OPTARG}."
           exit 2
           ;; 
    esac
done

tfstate_resource_id=""
tfstate_parameter=""

deployer_tfstate_key=""
deployer_tfstate_key_parameter=""
deployer_tfstate_key_exists=false
landscape_tfstate_key=""
landscape_tfstate_key_parameter=""
landscape_tfstate_key_exists=false


# Read environment
readarray -d '-' -t environment<<<"$parameterfile"
readarray -d '-' -t -s 1 region<<<"$parameterfile"
key=`echo $parameterfile | cut -d. -f1`

if [ ! -f ${parameterfile} ]
then
    echo "#########################################################################################"
    echo "#                                                                                       #" 
    echo "#                  Parameter file" ${parameterfile} " does not exist!!! #"
    echo "#                                                                                       #" 
    echo "#########################################################################################"
    exit
fi

#Persisting the parameters across executions

automation_config_directory=~/.sap_deployment_automation/
generic_config_information=${automation_config_directory}config
library_config_information=${automation_config_directory}${environment}-${region}

if [ ! -d ${automation_config_directory} ]
then
    # No configuration directory exists
    mkdir $automation_config_directory
    if [ -n "$DEPLOYMENT_REPO_PATH" ]; then
        # Store repo path in ~/.sap_deployment_automation/config
        echo "DEPLOYMENT_REPO_PATH=${DEPLOYMENT_REPO_PATH}" >> $generic_config_information
        config_stored=true
    fi
    if [ -n "$ARM_SUBSCRIPTION_ID" ]; then
        # Store ARM Subscription info in ~/.sap_deployment_automation
        echo "ARM_SUBSCRIPTION_ID=${ARM_SUBSCRIPTION_ID}" >> $library_config_information
        arm_config_stored=true
    fi
else
    temp=`grep "DEPLOYMENT_REPO_PATH" $generic_config_information`
    if [ $temp ]
    then
        # Repo path was specified in ~/.sap_deployment_automation/config
        DEPLOYMENT_REPO_PATH=`echo $temp | cut -d= -f2`
        config_stored=true
    fi

    temp=`grep "REMOTE_STATE_RG" $library_config_information`
    if [  $temp ]
    then
        # Remmote state storage group was specified in ~/.sap_deployment_automation library config
        REMOTE_STATE_RG=`echo $temp | cut -d= -f2`
        config_stored=true
    fi

    temp=`grep "REMOTE_STATE_SA" $library_config_information`
    if [ $temp ]
    then
        # Remmote state storage group was specified in ~/.sap_deployment_automation library config
        REMOTE_STATE_SA=`echo $temp | cut -d= -f2`
        config_stored=true
    fi


    temp=`grep "tfstate_resource_id" $library_config_information`
    if [ $temp ]
    then
        echo "tfstate_resource_id specified"
        tfstate_resource_id=`echo $temp | cut -d= -f2`
        if [ $deployment_system != sap_deployer ]
        then
            tfstate_parameter=" -var tfstate_resource_id=${tfstate_resource_id}"
        fi
    fi

    temp=`grep "deployer_tfstate_key" $library_config_information`
    if [ $temp ]
    then
        # Deployer state was specified in ~/.sap_deployment_automation library config
        deployer_tfstate_key=`echo $temp | cut -d= -f2`
        if [ $deployment_system != sap_deployer ]
        then
            deployer_tfstate_key_parameter=" -var deployer_tfstate_key=${deployer_tfstate_key}"
        fi
        deployer_tfstate_key_exists=true

    fi

    temp=`grep "landscape_tfstate_key" $library_config_information`
    if [ $temp ]
    then
        # Landscape state was specified in ~/.sap_deployment_automation library config
        landscape_tfstate_key=`echo $temp | cut -d= -f2`

        if [ $deployment_system == sap_system ]
        then
            landscape_tfstate_key_parameter=" -var landscape_tfstate_key=${landscape_tfstate_key}"
        fi
        landscape_tfstate_key_exists=true
    fi
fi

if [ ! -n "$DEPLOYMENT_REPO_PATH" ]; then
    echo ""
    echo ""
    echo "#########################################################################################"
    echo "#                                                                                       #" 
    echo "#   Missing environment variables (DEPLOYMENT_REPO_PATH)!!!                             #"
    echo "#                                                                                       #" 
    echo "#   Please export the folloing variables:                                               #"
    echo "#      DEPLOYMENT_REPO_PATH (path to the repo folder (sap-hana))                        #"
    echo "#      ARM_SUBSCRIPTION_ID (subscription containing the state file storage account)     #"
    echo "#      REMOTE_STATE_RG (resource group name for storage account containing state files) #"
    echo "#      REMOTE_STATE_SA (storage account for state file)                                 #"
    echo "#                                                                                       #" 
    echo "#########################################################################################"
    exit 4
fi

if [ ! -n "$ARM_SUBSCRIPTION_ID" ]; then
    echo ""
    echo "#########################################################################################"
    echo "#                                                                                       #" 
    echo "#   Missing environment variables (ARM_SUBSCRIPTION_ID)!!!                              #"
    echo "#                                                                                       #" 
    echo "#   Please export the folloing variables:                                               #"
    echo "#      DEPLOYMENT_REPO_PATH (path to the repo folder (sap-hana))                        #"
    echo "#      ARM_SUBSCRIPTION_ID (subscription containing the state file storage account)     #"
    echo "#      REMOTE_STATE_RG (resource group name for storage account containing state files) #"
    echo "#      REMOTE_STATE_SA (storage account for state file)                                 #"
    echo "#                                                                                       #" 
    echo "#########################################################################################"
    exit 3
fi

if [ ! -n "$REMOTE_STATE_RG" ]; then
    echo ""
    echo "#########################################################################################"
    echo "#                                                                                       #" 
    echo "#   Missing environment variables (REMOTE_STATE_RG)!!!                                  #"
    echo "#   Please export the folloing variables:                                               #"
    echo "#      DEPLOYMENT_REPO_PATH (path to the repo folder (sap-hana))                        #"
    echo "#      ARM_SUBSCRIPTION_ID (subscription containing the state file storage account)     #"
    echo "#      REMOTE_STATE_RG (resource group name for storage account containing state files) #"
    echo "#      REMOTE_STATE_SA (storage account for state file)                                 #"
    echo "#                                                                                       #" 
    echo "#########################################################################################"
    exit 5
fi

if [ ! -n "$REMOTE_STATE_SA" ]; then
    echo ""
    echo "#########################################################################################"
    echo "#                                                                                       #" 
    echo "#   Missing environment variables (REMOTE_STATE_SA)!!!                                  #"
    echo "#   Please export the folloing variables:                                               #"
    echo "#      DEPLOYMENT_REPO_PATH (path to the repo folder (sap-hana))                        #"
    echo "#      ARM_SUBSCRIPTION_ID (subscription containing the state file storage account)     #"
    echo "#      REMOTE_STATE_RG (resource group name for storage account containing state files) #"
    echo "#      REMOTE_STATE_SA (storage account for state file)                                 #"
    echo "#                                                                                       #" 
    echo "#########################################################################################"
    exit 6
fi

terraform_module_directory=${DEPLOYMENT_REPO_PATH}deploy/terraform/run/${deployment_system}/

if [ ! -d ${terraform_module_directory} ]
then
    echo "#########################################################################################"
    echo "#                                                                                       #" 
    echo "#   Incorrect system deployment type specified :" ${deployment_system} "       #"
    echo "#                                                                                       #" 
    echo "#     Valid options are:                                                                #"
    echo "#       sap_deployer                                                                    #"
    echo "#       sap_library                                                                     #"
    echo "#       sap_landscape                                                                   #"
    echo "#       sap_system                                                                      #"
    echo "#                                                                                       #" 
    echo "#########################################################################################"
    echo ""
    exit 7
fi

ok_to_proceed=false
new_deployment=false

if [ -f backend.tf ]
then
    rm backend.tf
fi

terraform init -upgrade=true -reconfigure --backend-config "subscription_id=${ARM_SUBSCRIPTION_ID}" \
--backend-config "resource_group_name=${REMOTE_STATE_RG}" \
--backend-config "storage_account_name=${REMOTE_STATE_SA}" \
--backend-config "container_name=tfstate" \
--backend-config "key=${key}.terraform.tfstate" \
$terraform_module_directory

cat <<EOF > backend.tf
####################################################
# To overcome terraform issue                      #
####################################################
terraform {
    backend "azurerm" {}
}

EOF

outputs=`terraform output`
if echo $outputs | grep "No outputs"; then
    ok_to_proceed=true
    new_deployment=true
    echo "#########################################################################################"
    echo "#                                                                                       #" 
    echo "#                                   New deployment                                      #"
    echo "#                                                                                       #" 
    echo "#########################################################################################"
else
    echo ""
    echo "#########################################################################################"
    echo "#                                                                                       #" 
    echo "#                           Existing deployment was detected                            #"
    echo "#                                                                                       #" 
    echo "#########################################################################################"
    echo ""

    deployed_using_version=`terraform output automation_version`
    if [ ! -n "$deployed_using_version" ]; then
        echo ""
        echo "#########################################################################################"
        echo "#                                                                                       #" 
        echo "#    The environment was deployed using an older version of the Terrafrom templates     #"
        echo "#                                                                                       #" 
        echo "#                               !!! Risk for Data loss !!!                              #"
        echo "#                                                                                       #" 
        echo "#        Please inspect the output of Terraform plan carefully before proceeding        #"
        echo "#                                                                                       #" 
        echo "#########################################################################################"

        read -p "Do you want to continue Y/N?"  ans
        answer=${ans^^}
        if [ $answer == 'Y' ]; then
            ok_to_proceed=true
        else
            exit 1
        fi
    else
        
        echo ""
        echo "#########################################################################################"
        echo "#                                                                                       #" 
        echo "# Terraform templates version:" $deployed_using_version "were used in the deployment "
        echo "#                                                                                       #" 
        echo "#########################################################################################"
        echo ""
        #Add version logic here
    fi
fi

echo ""
echo "#########################################################################################"
echo "#                                                                                       #" 
echo "#                             Running Terraform plan                                    #"
echo "#                                                                                       #" 
echo "#########################################################################################"
echo ""

terraform plan -var-file=${parameterfile} $tfstate_parameter $landscape_tfstate_key_parameter $deployer_tfstate_key_parameter $terraform_module_directory > plan_output.log

if ! $new_deployment; then
    if grep "No changes" plan_output.log ; then
        echo ""
        echo "#########################################################################################"
        echo "#                                                                                       #" 
        echo "#                           Infrastructure is up to date                                #"
        echo "#                                                                                       #" 
        echo "#########################################################################################"
        echo ""
        rm plan_output.log
        
        if [ $deployment_system == sap_deployer ]
        then
            if [ $deployer_tfstate_key_exists == false ]
            then
                echo "Saving the deployer state file name"
                echo "deployer_tfstate_key=${key}.terraform.tfstate" >> $library_config_information
                deployer_tfstate_key_exists=true
            fi
        fi
        if [ $deployment_system == sap_landscape ]
        then
            if [ $landscape_tfstate_key_exists == false ]
            then
                echo "landscape_tfstate_key=${key}.terraform.tfstate" >> $library_config_information
                landscape_tfstate_key_exists=true
            fi
        fi
        exit 0
    fi
    if ! grep "0 to change, 0 to destroy" plan_output.log ; then
        echo ""
        echo "#########################################################################################"
        echo "#                                                                                       #" 
        echo "#                               !!! Risk for Data loss !!!                              #"
        echo "#                                                                                       #" 
        echo "#        Please inspect the output of Terraform plan carefully before proceeding        #"
        echo "#                                                                                       #" 
        echo "#########################################################################################"
        echo ""
        read -n 1 -r -s -p $'Press enter to continue...\n'

        cat plan_output.log
        read -p "Do you want to continue with the deployment Y/N?"  ans
        answer=${ans^^}
        if [ $answer == 'Y' ]; then
            ok_to_proceed=true
        else
            exit 1
        fi
    else
        ok_to_proceed=true
    fi
fi

if [ $ok_to_proceed ]; then

    rm plan_output.log

    echo ""
    echo "#########################################################################################"
    echo "#                                                                                       #" 
    echo "#                             Running Terraform apply                                   #"
    echo "#                                                                                       #" 
    echo "#########################################################################################"
    echo ""

    terraform apply ${approve} -var-file=${parameterfile} $tfstate_parameter $landscape_tfstate_key_parameter $deployer_tfstate_key_parameter $terraform_module_directory
fi

if [ $deployment_system == sap_deployer ]
then
echo $deployer_tfstate_key_exists
    if [ $deployer_tfstate_key_exists == false ]
    then
        echo "deployer_tfstate_key=${key}.terraform.tfstate" >> $library_config_information
    fi
fi

if [ $deployment_system == sap_landscape ]
then
    if [ $landscape_tfstate_key_exists == false ]
    then
        echo "landscape_tfstate_key=${key}.terraform.tfstate" >> $library_config_information
    fi
fi