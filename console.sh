#!/bin/bash

echo "Creating new instance"
aws ec2 run-instances \
    --image-id ami-0cd3c7f72edd5b06d \
    --count 1 \
    --instance-type c6a.large \
    --key-name Mercury-east \
    --region us-east-2  \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=\"Mercury-console\"}]" \
    --security-group-ids sg-0491bfb2d28087f26 \
    --subnet vpc-0c1a22b0ddc4908d1 \
    --associate-public-ip-address \
    --output json > create.json

echo "Wait until server initialize"
sleep 30

echo "Getting server ip address"
server_ip=$(aws ec2 describe-instances   \
            --filters "Name=tag:Name,Values=Mercury-console" "Name=instance-state-name,Values=running" \
            --query "Reservations[*].Instances[*].PublicIpAddress"   \
            --region ap-southeast-1 \
            --output=text)
echo "Server IP address: $server_ip"

# echo "Copying file to remote server"
# scp -T -i ../../aws/Mercury.pem -o StrictHostKeyChecking=no main ec2-user@$server_ip:~ 
# scp -T -i ../../aws/Mercury.pem -o StrictHostKeyChecking=no client ec2-user@$server_ip:~ 
# scp -T -i ../../aws/Mercury.pem -o StrictHostKeyChecking=no config.json ec2-user@$server_ip:~ 
# scp -T -i ../../aws/Mercury.pem -o StrictHostKeyChecking=no resourses/privateKey-bak.txt ec2-user@$server_ip:~ 
# scp -T -i ../../aws/Mercury.pem -o StrictHostKeyChecking=no east/Mercury-east.pem east/instance.sh ec2-user@$server_ip:~ 
# scp -T -i ../../aws/Mercury.pem -o StrictHostKeyChecking=no west/Mercury-west.pem west/instance.sh ec2-user@$server_ip:~ 
# scp -T -i ../../aws/Mercury.pem -o StrictHostKeyChecking=no server.sh ec2-user@$server_ip:~ 

# scp -o StrictHostKeyChecking=no -i ../../aws/Mercury.pem -r ./* ec2-user@$server_ip:~ 

echo "Connecting to remote server"
ssh -t -i ./east/Mercury-east.pem ec2-user@$server_ip
