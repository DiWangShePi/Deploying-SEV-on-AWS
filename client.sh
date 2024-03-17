#!/bin/bash
# Client script
##################################################################################################
#
# 脚本路径
script_name="$0"
script_path=$(dirname "$script_name")
#
# 节点主机的配置
IMAGE_ID=ami-0cd3c7f72edd5b06d          #   选择的镜像，此处为 Amazon Linux 2023
USER=ec2-user                           #   亚马逊Linux默认用户为ec2-user
INSTANCE_TYPE=c6a.16xlarge              #   节点选择的实例
KEY_NAME=Mercury                        #   密钥组
KEY_FILE=Mercury.pem                    #   密钥文件
SECURITY=sg-0491bfb2d28087f26           #   安全分组，决定防火墙规则
REGION=us-east-2                        #   实例所处地区
#
PUBLIC_IP_TXT=client_public_ip.txt
INSTANCE_TXT=client_instance_id.txt

# deploy server and save their information
deploy_function() {
    local enable=$1
    local num=$2

    echo "Starting $num client in $REGION"

    new_instance_info=$(aws ec2 run-instances \
        --image-id $IMAGE_ID \
        --instance-type $INSTANCE_TYPE \
        --key-name $KEY_NAME \
        --security-group-ids $SECURITY \
        --associate-public-ip-address \
        --count $num \
        --region $REGION \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=\"Mercury-client\"}]" \
        --cpu-options AmdSevSnp=$enable \
        --output json)
    echo "$new_instance_info" | jq '.' > client.json
    rm client.json

    # Wait until all the instances are ready, although 30s may not be enough
    # You will need this, otherwise you may not get enough IP Address and Instance ID
    echo "Wait for 30s, until the server initalized"
    sleep 30

    # Get all the instance's public IP address
    public_ip=$(aws ec2 describe-instances   \
            --filters "Name=tag:Name,Values=Mercury-client" "Name=instance-state-name,Values=running" \
            --query "Reservations[*].Instances[*].PublicIpAddress"   \
            --region $REGION \
            --output=text)
    public_ip_arr=(`echo $public_ip | tr ',' ' '`)
    echo "${public_ip_arr[@]}" > $PUBLIC_IP_TXT 

    # Get all the instance's instanceID
    instance_id=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=Mercury-client" "Name=instance-state-name,Values=running" \
            --query "Reservations[*].Instances[*].InstanceId" \
            --region $REGION \
            --output=text)
    instance_id_num=(`echo $instance_id | tr ',' ' '`)
    echo "${instance_id_num[@]}" > $INSTANCE_TXT
}

# Terminate all instances
terminate_client_function() {    
    read -ra instance_ids <<< $(cat $INSTANCE_TXT)
    for instance_id in "${instance_ids[@]}"; do
        aws ec2 terminate-instances --instance-ids "$instance_id" --region $REGION >> west/terminateResult.json &
    done
    wait

    rm west/terminateResult.json
}

# Copy file to client
copy_file_function() {
    read -ra public_ip_addrs <<< $(cat $PUBLIC_IP_TXT)
    local client_ip=${public_ip_addrs[0]}
    scp -T -i $KEY_FILE -o StrictHostKeyChecking=no client config.json ips.txt $USER@$client_ip:~
}

# Start client
start_client_function () {
    read -ra public_ip_addrs <<< $(cat $PUBLIC_IP_TXT)
    local client_ip=${public_ip_addrs[0]}
    ssh -i $KEY_FILE $USER@$client_ip "chmod +x client; ./client" &
}

# Stop client
stop_client_function () {
    read -ra public_ip_addrs <<< $(cat $PUBLIC_IP_TXT)
    local client_ip=${public_ip_addrs[0]}
    ssh -T -i $KEY_FILE $USER@$client_ip -t 'bash -l -c "kill -9 \$(pgrep client)"'
}


if [ "$1" ]; then
    case "$1" in
        # Deploy machines without SEV protection
        deploy)
            deploy_function disabled 1
            ;;

        # Terminate all the machines
        terminate)
            terminate_client_function
            ;;

        # Copy all the file
        copy)
            copy_file_function
            ;;

        # Start client
        start)
            start_client_function
            ;;
        # Stop client
        stop)
            stop_client_function
            ;;
        # Unknown parameter
        *)
            echo "Unknown paermeter: $1"
            ;;
    esac
else
    echo "User guide: $0"
    echo "--deploy-sev <instance-number>  |  deploy instances with sev protection     "
    echo "--deploy     <instance-number>  |  deploy instances without sev protection   "
    echo "--terminate                     |  Terminate all instances                "
fi