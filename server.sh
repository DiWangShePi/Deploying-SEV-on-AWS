#!/bin/bash
##################################################################################################
# 查找支持AMD SEV-SNP的实例类型
# M6a： | | | m6a.large m6a.xlarge m6a.2xlarge m6a.4xlarge m6a.8xlarge
# C6a： | | | c6a.large c6a.xlarge c6a.2xlarge c6a.4xlarge c6a.8xlarge c6a.12xlarge c6a.16xlarge
# R6a： | | | r6a.large r6a.xlarge r6a.2xlarge r6a.4xlarge
#
# 云服务器区域
# 目前仅支持美国东部（俄亥俄州）和欧洲地区（爱尔兰）区域
# 创建实例时的 --region 参数可以指定实例创建的区域
# 对应的aws configure中的设置为 us-east-2 和 eu-west-1。 目前的设置为us-west-2
#
# 操作系统类型
# AMD SEV-SNP 支持 Amazon Linux 2023 和 Ubuntu 23.04 (Ubuntu 这个镜像没有能用的实例)
#################################################################################################

# 管控东部节点
EAST_SCRIPT=east/instance.sh
EAST_PUBLIC_IP_TXT=east/public_ip.txt
EAST_INSTANCE_TXT=east/instance_id.txt

# 管控西部节点
WEST_SCRIPT=west/instance.sh
WEST_PUBLIC_IP_TXT=west/public_ip.txt
WEST_INSTANCE_TXT=west/instance_id.txt

# 节点所用的配置文件
IPS=ips.txt
PRIVATE_BAK_KEYS=resourses/privateKey-bak.txt
PRIVATE_KEYS=privateKey.txt
FILE_LIST="main ips.txt config.json privateKey.txt"
# 便于读取的配置文件，IP信息
PUBLIC_IP_TXT=public_ips.txt
KEY_FILE=Mercury.pem

generate_config_function() {
    local server_num=$1

    # Modify IP information
    read -ra east_public_ip_addrs <<< $(cat $EAST_PUBLIC_IP_TXT)
    read -ra west_public_ip_addrs <<< $(cat $WEST_PUBLIC_IP_TXT)

    rm $IPS
    for ip in "${east_public_ip_addrs[@]}" "${west_public_ip_addrs[@]}"; do
        echo "$ip" >> $IPS
    done

    rm $PUBLIC_IP_TXT
    echo "${east_public_ip_addrs[*]} ${west_public_ip_addrs[*]}" >> $PUBLIC_IP_TXT

    # Modify private key file
    rm $PRIVATE_KEYS
    read -ra private_keys <<< $(cat $PRIVATE_BAK_KEYS)
    for ((i = 0; i < $server_num; i++)); do
        echo ${private_keys[i]} >> $PRIVATE_KEYS
    done

    echo "Please manually modify the information in config.json before start copying files"
}

# Copy file to remote server host
copy_file_function() {
    read -ra public_ip_addrs <<< $(cat $PUBLIC_IP_TXT)
    for public_ip in "${public_ip_addrs[@]}"; do
        scp -T -i $KEY_FILE -o StrictHostKeyChecking=no $FILE_LIST $USER@$public_ip:~ &
    done
    wait

    echo ""
    echo "Finish copying all the files to all remote server"
}

# Change one file on remote server
change_file_function() {
    read -ra public_ip_addrs <<< $(cat $PUBLIC_IP_TXT)
    local source_file=$1

    for public_ip in "${public_ip_addrs[@]}"; do
        scp -T -i $KEY_FILE $source_file $USER@$public_ip:~ &
    done
    wait

    echo ""
    echo "Finish changing file on all remote server"
}

start_node_function() {
    read -ra public_ip_addrs <<< $(cat $PUBLIC_IP_TXT)
    local num=${#public_ip_addrs[@]}

    for (( j=0; j<$num; j++)) do
        local ip_address=${public_ip_addrs[j]}

        echo "Starting server, IP: $ip_address"
        ssh -i $KEY_FILE $USER@$ip_address "chmod +x main; ./main -id ${j+1} -log_dir=. -log_level=info -algorithm=hotstuff &" &
    done
    
    sleep 10
    # echo "If you did not see anything else, then we have succeeded in starting all nodes"
}

stop_node_function () {
    read -ra public_ip_addrs <<< $(cat $PUBLIC_IP_TXT)
    local num=${#public_ip_addrs[@]}

    for (( j=1; j<=$num; j++)) do
        ssh -T -i $KEY_FILE $USER@${public_ip_addrs[j-1]} -t 'bash -l -c "kill -9 \$(pgrep main)"' &
    done
    wait
}

# Connect to one of the remote server
connect_server_function() {
    read -ra public_ip_addrs <<< $(cat $PUBLIC_IP_TXT)   
    local server_ip=${public_ip_addrs[$1]}
    ssh -i $KEY_FILE -t $USER@$server_ip
}

# Getting server output
check_result_function() {
    read -ra public_ip_addrs <<< $(cat $PUBLIC_IP_TXT)
    local check_ip=${public_ip_addrs[0]}

    curl_output_file=$(mktemp)
    curl $check_ip:8070/query > $curl_output_file

    first_line=$(head -n 1 $curl_output_file)
    last_line=$(tail -n 1 $curl_output_file)

    echo $first_line
    echo $last_line
    rm $curl_output_file
}

restart_function () {
    stop_client_function
    stop_node_function
    change_file_function config.json
    start_node_function
    start_client_function
}


if [ "$1" ]; then
    case "$1" in
        restart)
                restart_function
            ;;

        # Deploy machines with SEV protection
        deploy-sev)
            assign_server=$(expr $2 / 2)
            
            bash $EAST_SCRIPT deploy-sev $assign_server
            bash $WEST_SCRIPT deploy-sev $assign_server
            
            generate_config_function $2
            # bash $0 ssh
            ;;
        # Deploy machines without SEV protection
        deploy)
            assign_server=$(expr $2 / 2)
            
            bash $EAST_SCRIPT deploy $assign_server
            bash $WEST_SCRIPT deploy $assign_server
            
            generate_config_function $2
            # bash $0 ssh
            ;;

        copy)
            copy_file_function
            ;;
        config)
            generate_config_function $2
            ;;

        # Terminate all the machines
        terminate)
            bash $EAST_SCRIPT terminate
            bash $WEST_SCRIPT terminate
            ;;

        connect)
            connect_server_function $2
            ;;
        # Copy files to all the machines
        ssh)
            bash $EAST_SCRIPT ssh
            bash $WEST_SCRIPT ssh
            ;;

        # Change one file on remote server
        change-file)
            change_file_function $2
            ;;

        # Check result
        check-result)
            check_result_function
            ;;

        # Start all server node
        start-node)
            start_node_function
            ;;
        # Stop all server node
        stop-node)
            stop_node_function
            ;;

        # Unknown parameter
        *)
            echo "Unknown parmeter"
            sh server.sh
            ;;
    esac
else
    echo "User guide: $0"
    echo "--deploy-sev <instance-number>  |  deploy instances with sev protection     "
    echo "--deploy     <instance-number>  |  deploy instances without sev protection   "
    echo "--terminate                     |  Terminate all instances                "
fi