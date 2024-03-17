#!/bin/bash
# 俄亥俄州 us-east-2
##################################################################################################
# 查找支持AMD SEV-SNP的实例类型
# M6a： | | | m6a.large m6a.xlarge m6a.2xlarge m6a.4xlarge m6a.8xlarge
# C6a： | | | c6a.large c6a.xlarge c6a.2xlarge c6a.4xlarge c6a.8xlarge c6a.12xlarge c6a.16xlarge
# R6a： | | | r6a.large r6a.xlarge r6a.2xlarge r6a.4xlarge
#
# 云服务器区域
# 目前仅支持美国东部（ 俄亥俄州 us-east-2 ）和欧洲地区（ 爱尔兰 eu-west-1 ）区域
#################################################################################################
#
# 脚本路径
script_name="$0"
script_path=$(dirname "$script_name")
#
# 节点主机的配置
IMAGE_ID=ami-0cd3c7f72edd5b06d          #   选择的镜像，此处为 Amazon Linux 2023
USER=ec2-user                           #   亚马逊Linux默认用户为ec2-user
INSTANCE_TYPE=m6a.xlarge                #   节点选择的实例
KEY_NAME=Mercury                        #   密钥组
KEY_FILE=$script_path/Mercury.pem       #   密钥文件
SECURITY=sg-0491bfb2d28087f26           #   安全分组，决定防火墙规则
REGION=us-east-2                        #   节点地域
#
PUBLIC_IP_TXT=$script_path/public_ip.txt
INSTANCE_TXT=$script_path/instance_id.txt

# deploy server and save their information
deploy_function() {
    local enable=$1
    local num=$2

    echo "Starting $num $enable server in $REGION"

    new_instance_info=$(aws ec2 run-instances \
        --image-id $IMAGE_ID \
        --instance-type $INSTANCE_TYPE \
        --key-name $KEY_NAME \
        --security-group-ids $SECURITY \
        --associate-public-ip-address \
        --count $num \
        --region $REGION \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=\"Mercury-instance\"}]" \
        --cpu-options AmdSevSnp=$enable \
        --output json)
    echo "$new_instance_info" | jq '.' > east/createResult.json
    rm east/createResult.json

    # Wait until all the instances are ready, although 30s may not be enough
    # You will need this, otherwise you may not get enough IP Address and Instance ID
    echo "Wait for 30s, until the server initalized"
    sleep 30

    # Get all the instance's public IP address
    public_ip=$(aws ec2 describe-instances   \
            --filters "Name=tag:Name,Values=Mercury-instance" "Name=instance-state-name,Values=running" \
            --query "Reservations[*].Instances[*].PublicIpAddress"   \
            --region $REGION \
            --output=text)
    public_ip_arr=(`echo $public_ip | tr ',' ' '`)
    echo "${public_ip_arr[@]}" > $PUBLIC_IP_TXT 

    # Get all the instance's instanceID
    instance_id=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=Mercury-instance" "Name=instance-state-name,Values=running" \
            --query "Reservations[*].Instances[*].InstanceId" \
            --region $REGION \
            --output=text)
    instance_id_num=(`echo $instance_id | tr ',' ' '`)
    echo "${instance_id_num[@]}" > $INSTANCE_TXT
}

# deploy server and make sure they are reachable
deploy_server_function() {
    local totalNum=$2
    local currentNum=0
    while [ "$totalNum" -ne "$currentNum" ]
    do
        desireNum=$((totalNum - currentNum))
        deploy_function $1 "$desireNum"

        currentNum=0
        read -ra public_ip_addrs <<< $(cat $PUBLIC_IP_TXT)
        read -ra instance_ids <<< $(cat $INSTANCE_TXT)
        local num=${#public_ip_addrs[@]}
        for (( j=0; j<$num; j++)) do
            ping -c 4 ${public_ip_addrs[j]} > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "Remote server in $REGION ${public_ip_addrs[j]} reachable"
                ((currentNum++))
            else
                echo "Remote server in $REGION ${public_ip_addrs[j]} unreachable"
                instance_id=${instance_ids[j]}
                aws ec2 terminate-instances --instance-ids "$instance_id" --region $REGION >> east/terminateResult.json 
                rm east/terminateResult.json
            fi
        done
        wait
        echo "Successfully started $currentNum reachable server in $REGION"
    done
}

# Terminate all instances
terminate_server_function() {    
    read -ra instance_ids <<< $(cat $INSTANCE_TXT)
    for instance_id in "${instance_ids[@]}"; do
        aws ec2 terminate-instances --instance-ids "$instance_id" --region $REGION >> east/terminateResult.json &
    done
    rm east/terminateResult.json
}

# Copy host's ssh pub key to remote host
change_ssh_function() {
    local ssh_pub_key <<< $(cat ~/.ssh/id_rsa.pub)

    read -ra public_ip_addrs <<< $(cat $PUBLIC_IP_TXT)
    for public_ip in "${public_ip_addrs[@]}"; do
        ssh -i $KEY_FILE $USER@$public_ip "echo $ssh_pub_key >> ~/.ssh/authorized_keys"
        # ssh-copy-id $USER@$public_ip:~ &
    done
    wait

    echo ""
    echo "Finish changing all the ssh pub key to remote server in $REGION"
}

connect_server_function() {
    read -ra public_ip_addrs <<< $(cat $PUBLIC_IP_TXT)   
    local server_ip=${public_ip_addrs[$1]}
    ssh -t -i $KEY_FILE $USER@$server_ip
}



if [ "$1" ]; then
    case "$1" in
        # Deploy machines with SEV protection
        deploy-sev)
            deploy_function enabled "$2"
            ;;
        # Deploy machines without SEV protection
        deploy)
            deploy_function disabled "$2"
            ;;
        # Terminate all the machines
        terminate)
            terminate_server_function
            ;;
        # Change ssh pub key
        ssh)
            change_ssh_function
            ;;

        # Connect to one of the server
        connect)
            connect_server_function $2
            ;;
        # Unknown parameter
        *)
            echo "Unknown paermeter: $1"
            sh server.sh
            ;;
    esac
else
    echo "User guide: $0"
    echo "--deploy-sev <instance-number>  |  deploy instances with sev protection     "
    echo "--deploy     <instance-number>  |  deploy instances without sev protection   "
    echo "--terminate                     |  Terminate all instances                "
fi