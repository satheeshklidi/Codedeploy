#! /bin/bash

# Create keypair

aws ec2 create-key-pair --key-name keypair2 --query 'KeyMaterial' --output text > keypair2.pem
echo "Keypair created"

# Create Security groups

VPN_SG=$(aws ec2 create-security-group --group-name VPN --description "This is to assign to Openswan instance" --vpc-id vpc-0bf297b68ccc4c490 --query '{GroupId:GroupId}' --output text)
aws ec2 authorize-security-group-ingress --group-id $VPN_SG --protocol tcp --port 22 --cidr 49.206.51.181/32
echo "Security group VPN created and Ingress traffic allowed"

INOUT_SG=$(aws ec2 create-security-group --group-name Inbound_Outbound --description "This is to assign to Openswan instance" --vpc-id vpc-0bf297b68ccc4c490 --query '{GroupId:GroupId}' --output text)
aws ec2 authorize-security-group-ingress --group-id $INOUT_SG --ip-permissions IpProtocol=-1,IpRanges=[{CidrIp=10.12.0.0/16}] IpProtocol=-1,IpRanges=[{CidrIp=10.14.0.0/16}] IpProtocol=-1,IpRanges=[{CidrIp=192.168.0.0/16}] IpProtocol=-1,IpRanges=[{CidrIp=$CIDR}]
echo "Security group Inbound_Outbound created and ingress traffic allowed"

# Create openswan instance

OPENSWAN_ID=$(aws ec2 run-instances --image-id ami-0efbfb724e7dd9f77 --instance-type t2.micro --key-name keypair2 --security-group-ids $VPN_SG --subnet-id subnet-06b55c2f4150a7454 --query 'Instances[*].InstanceId' --output text)
echo "Launching Openswan instance with ID $OPENSWAN_ID"
FORMATTED_MSG="Launching Openswan. Please wait..."
printf " $FORMATTED_MSG:\n"
aws ec2 wait instance-status-ok --instance-ids $OPENSWAN_ID
echo "Openswan is now available"
EIP_OPENSWAN=$(aws ec2 allocate-address --domain vpc --query '{AllocationId:AllocationId}' --output text)
aws ec2 associate-address --instance-id $OPENSWAN_ID --allocation-id $EIP_OPENSWAN
echo "Openswan instance created and elastic IP assigned"

#Disable Source/Dest check

aws ec2 modify-instance-attribute --instance-id $OPENSWAN_ID --no-source-dest-check

# Add routes to route tables to target traffic from our internal subnets to Openswan

aws ec2 create-route --route-table-id $PRIVATERT_ID --destination-cidr-block 10.12.0.0/16 --instance-id $OPENSWAN_ID
aws ec2 create-route --route-table-id $PRIVATERT_ID --destination-cidr-block 10.14.0.0/16 --instance-id $OPENSWAN_ID
aws ec2 create-route --route-table-id $PRIVATERT_ID --destination-cidr-block 192.168.0.0/17 --instance-id $OPENSWAN_ID

aws ec2 create-route --route-table-id $PUBLICRT_ID --destination-cidr-block 10.12.0.0/16 --instance-id $OPENSWAN_ID
aws ec2 create-route --route-table-id $PUBLICRT_ID --destination-cidr-block 10.14.0.0/16 --instance-id $OPENSWAN_ID
aws ec2 create-route --route-table-id $PUBLICRT_ID --destination-cidr-block 192.168.0.0/17 --instance-id $OPENSWAN_ID
