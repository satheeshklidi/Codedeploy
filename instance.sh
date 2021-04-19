#! /bin/bash

#OPENSWAN_EIP=$(aws ec2 allocate-address --domain vpc --query '{AllocationId:AllocationId}' --output text)
aws ec2 create-key-pair --key-name keypair2 --query 'KeyMaterial' --output text > keypair2.pem
VPN_SG=$(aws ec2 create-security-group --group-name VPN --description "This is to assign to Openswan instance" --vpc-id vpc-0bf297b68ccc4c490 --query '{GroupId:GroupId}' --output text)
echo "Security group created"
aws ec2 authorize-security-group-ingress --group-id $VPN_SG --protocol tcp --port 22 --cidr 15.207.20.244/32


OPENSWAN_ID=$(aws ec2 run-instances --image-id ami-0efbfb724e7dd9f77 --instance-type t2.micro --key-name keypair2 --security-group-ids $VPN_SG --subnet-id subnet-06b55c2f4150a7454 --query 'Instances[*].InstanceId' --output text)
echo "Launching Openswan instance with ID $OPENSWAN_ID"
FORMATTED_MSG="Launching Openswan. Please wait..."
printf " $FORMATTED_MSG:"
aws ec2 wait instance-status-ok --instance-ids $OPENSWAN_ID
echo "Openswan is now available"
EIP_OPENSWAN=$(aws ec2 allocate-address --domain vpc --query '{AllocationId:AllocationId}' --output text)
echo "Allocated elastic IP"
aws ec2 associate-address --instance-id $OPENSWAN_ID --allocation-id $EIP_OPENSWAN
echo "Associated elastic IP to Openswan instance"



