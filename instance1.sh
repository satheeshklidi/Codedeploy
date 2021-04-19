#! /bin/bash

OPENSWAN_ID=$(aws ec2 run-instances --image-id ami-0bcf5425cdc1d8a85 --instance-type t2.micro --key-name keypair1 --security-group-ids sg-0237218727bf65bf6 --subnet-id subnet-066b2450fbca616db --query 'Instances[*].InstanceId' --output text)
echo "Launching Openswan instance with ID $OPENSWAN_ID"
FORMATTED_MSG="Launching Openswan. Please wait..."
printf " $FORMATTED_MSG:"
aws ec2 wait instance-status-ok --instance-ids $OPENSWAN_ID
echo "Openswan is now available"
EIP_OPENSWAN=$(aws ec2 allocate-address --domain vpc --query '{AllocationId:AllocationId}' --output text)
echo "Allocated elastic IP"
aws ec2 associate-address --instance-id $OPENSWAN_ID --allocation-id $EIP_OPENSWAN
echo "Associated elastic IP to Openswan instance"


