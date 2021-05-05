#! /bin/bash
#AZ=ap-south-1a
#read -p "Enter the CIDR for VPC: " CIDR
#read -p "Enter VPC Name: " VPC_NAME
#read -p "Enter Public Subnet: " PUBLIC_SUBNET
#read -p "Enter Private Subnet: " PRIVATE_SUBNET
#read -p "Enter keypairname: " KEYPAIR
#read -p "Enter Availability Zone: " AZ

CIDR="10.200.0.0/16"
VPC_NAME="SatheeshVPC"
PUBLIC_SUBNET="10.200.1.0/24"
PRIVATE_SUBNET="10.200.2.0/24"
KEYPAIR="Satheesh"
AZ="ap-northeast-1a"
#=============================================================================
# create VPC
#=============================================================================

VPC_ID=$(aws ec2 create-vpc --cidr-block $CIDR --query 'Vpc.{VpcId:VpcId}' --output text --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]")
echo "VPC with ID $VPC_ID created successfully"
#aws ec2 create-tags --resources $VPC_ID --tags "Key=Name,Value=$VPC_NAME"
echo "VPC ID $VPC_ID named as $VPC_NAME"

DHCP_ID=$(aws ec2 create-dhcp-options --dhcp-configuration "Key=domain-name-servers,Values=10.14.1.21,10.14.1.22,10.12.1.2,10.12.1.107" "Key=domain-name,Values=internal.rsi" --query DhcpOptions.{DhcpOptionsId:DhcpOptionsId} --output text --tag-specifications 'ResourceType=dhcp-options,Tags=[{Key=Name,Value=Rimini_DHCP}]')
aws ec2 associate-dhcp-options --dhcp-options-id $DHCP_ID --vpc-id $VPC_ID

#=============================================================================
#Create public and private subnets
#=============================================================================

PUBLIC_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET --availability-zone $AZ --query 'Subnet.{SubnetId:SubnetId}' --output text --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=PUBLIC_SUBNET}]')
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET --availability-zone $AZ --query 'Subnet.{SubnetId:SubnetId}' --output text --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=PRIVATE_SUBNET}]')
echo "Created Public subnet $PUBLIC_SUBNET and private subnet $PRIVATE_SUBNET successfully"
#aws ec2 create-tags --resources $PUBLIC_SUBNET_ID --tags "Key=Name,Value=Public_Subnet"
#aws ec2 create-tags --resources $PRIVATE_SUBNET_ID --tags "Key=Name,Value=Private_Subnet"
echo "Named $PUBLIC_SUBNET as Public Subnet and $PRIVATE_SUBNET as Private Subnet"

#=============================================================================
# Create Internet gateway and attach to VPC
#=============================================================================

IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.{InternetGatewayId:InternetGatewayId}' --output text --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=Internet_Gateway}]')
echo "Internet gateway created successfully"
#aws ec2 create-tags --resources $IGW_ID --tags "Key=Name,Value=Internet_Gateway"

#==============================================================================
#Attach Internet gateway to the VPC
#==============================================================================

aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
echo "Internet gateway attached to VPC"

#==============================================================================
#Allocate Elastic IP for NAT Gateway
#==============================================================================

ELASTICIP_ID=$(aws ec2 allocate-address --domain vpc --query '{AllocationId:AllocationId}' --output text --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=NatGatewayIP}]')
#aws ec2 create-tags --resources $ELASTICIP_ID --tags "Key=Name,Value=NAT_Gateway_IP"
echo "Elastic IP allocated"

#==============================================================================
#Create NAT Gateway
#==============================================================================

NATGW_ID=$(aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUBNET_ID --allocation-id $ELASTICIP_ID --query 'NatGateway.{NatGatewayId:NatGatewayId}' --output text --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=NAT_Gateway}]')
FORMATTED_MSG="Creating NAT Gateway ID '$NATGW_ID' and waiting for it to become available "
FORMATTED_MSG+="\n Please BE PATIENT as this can take some "
FORMATTED_MSG+="time to complete.\n......\n"
printf " $FORMATTED_MSG"
FORMATTED_MSG="STATUS: %s - %02dh:%02dm:%02ds elapsed while waiting for NAT " 
FORMATTED_MSG+="Gateway to become available..."
SECONDS=0
LAST_CHECK=0
STATE='PENDING'
until [[ $STATE == 'AVAILABLE' ]]; do
  INTERVAL=$SECONDS-$LAST_CHECK
  if [[ $INTERVAL -ge $CHECK_FREQUENCY ]]; then
    STATE=$(aws ec2 describe-nat-gateways \
      --nat-gateway-ids $NATGW_ID \
      --query 'NatGateways[*].{State:State}' \
      --output text) \
      STATE=$(echo $STATE | tr '[:lower:]' '[:upper:]')
    LAST_CHECK=$SECONDS
  fi
  SECS=$SECONDS
  STATUS_MSG=$(printf "$FORMATTED_MSG" \
    $STATE $(($SECS/3600)) $(($SECS%3600/60)) $(($SECS%60)))
  printf " $STATUS_MSG\033[0K\r"
  sleep 1
done
printf "\n ......\n NAT Gateway ID '$NATGW_ID' is now AVAILABLE.\n"
#aws ec2 create-tags --resources $NATGW_ID --tags "Key=Name,Value=NAT_Gateway"

#==============================================================================
#Create Private route table
#==============================================================================

PRIVATERT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.{RouteTableId:RouteTableId}' --output text --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Private}]')
#aws ec2 create-tags --resources $PRIVATERT_ID --tags "Key=Name,Value=Private_table"
echo "Private route table created"
#Add route to private route table
aws ec2 create-route --route-table-id $PRIVATERT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $NATGW_ID
echo "routed 0.0.0.0/0 to NAT Gateway"
#Associate Private route table to private subnet
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_ID --route-table-id $PRIVATERT_ID
echo "private route table associated to private subnet"

#==============================================================================
#Create Public route table
#==============================================================================

PUBLICRT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.{RouteTableId:RouteTableId}' --output text --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Public}]')
#aws ec2 create-tags --resources $PUBLICRT_ID --tags "Key=Name,Value=Public_table"
echo "Public route table created"
#Add route to public route table
aws ec2 create-route --route-table-id $PUBLICRT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
echo "routed 0.0.0.0/0 to Internet Gateway"
#Associate public route table to public subnet
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_ID --route-table-id $PUBLICRT_ID
echo "public route table associated to Public subnet"

#==============================================================================
# Create keypair
#==============================================================================

aws ec2 create-key-pair --key-name $KEYPAIR --query 'KeyMaterial' --output text > $KEYPAIR.pem
echo "Keypair created"

#==============================================================================
# Create Security groups
#==============================================================================

VPN_SG=$(aws ec2 create-security-group --group-name VPN --description "This is to assign to Openswan instance" --vpc-id $VPC_ID --query '{GroupId:GroupId}' --output text)
aws ec2 authorize-security-group-ingress --group-id $VPN_SG --protocol tcp --port 22 --cidr 136.179.14.36/32
echo "Security group VPN created and Ingress traffic allowed"

INOUT_SG=$(aws ec2 create-security-group --group-name Inbound_Outbound --description "This is to for Inbound Outbound traffic" --vpc-id $VPC_ID --query '{GroupId:GroupId}' --output text)
aws ec2 authorize-security-group-ingress --group-id $INOUT_SG --ip-permissions IpProtocol=-1,IpRanges=[{CidrIp=10.12.0.0/16}] IpProtocol=-1,IpRanges=[{CidrIp=10.14.0.0/16}] IpProtocol=-1,IpRanges=[{CidrIp=192.168.0.0/16}] IpProtocol=-1,IpRanges=[{CidrIp=$CIDR}]
echo "Security group Inbound_Outbound created and ingress traffic allowed"

#==============================================================================
# Create openswan instance
#==============================================================================

OPENSWAN_ID=$(aws ec2 run-instances --image-id $(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 --query 'Parameters[0].[Value]' --output text) --count 1 --key-name $KEYPAIR --instance-type t2.micro --subnet-id $PUBLIC_SUBNET_ID --query 'Instances[*].InstanceId' --output text)
#(aws ec2 run-instances --image-id ami-0efbfb724e7dd9f77 --instance-type t2.micro --key-name keypair3 --security-group-ids $VPN_SG --subnet-id $PUBLIC_SUBNET_ID --query 'Instances[*].InstanceId' --output text)
echo "Launching Openswan instance with ID $OPENSWAN_ID"
FORMATTED_MSG="Launching Openswan. Please wait..."
printf " $FORMATTED_MSG:"
aws ec2 wait instance-status-ok --instance-ids $OPENSWAN_ID
echo "Openswan is now available"
aws ec2 create-tags --resources $OPENSWAN_ID --tags "Key=Name,Value=Openswan"
EIP_OPENSWAN=$(aws ec2 allocate-address --domain vpc --query '{AllocationId:AllocationId}' --output text)
aws ec2 create-tags --resources $EIP_OPENSWAN --tags "Key=Name,Value=OpenswanIP"
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

echo "Added routes to route tables to target traffic from our subnets to openswan"

aws ec2 run-instances --image-id $(aws ssm get-parameters --names /aws/service/ami-windows-latest/Windows_Server-2016-English-Full-Base --query 'Parameters[0].[Value]' --output text) --count 1 --key-name $KEYPAIR --instance-type t2.micro --subnet-id $PRIVATE_SUBNET_ID --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=FSR-01}]' --user-data file://software.txt
aws ec2 run-instances --image-id $(aws ssm get-parameters --names /aws/service/ami-windows-latest/Windows_Server-2016-English-Full-Base --query 'Parameters[0].[Value]' --output text) --count 1 --key-name $KEYPAIR --instance-type t2.micro --subnet-id $PRIVATE_SUBNET_ID --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=XTR-02}]' --user-data file://software.txt
aws ec2 run-instances --image-id $(aws ssm get-parameters --names /aws/service/ami-windows-latest/Windows_Server-2016-English-Full-Base --query 'Parameters[0].[Value]' --output text) --count 1 --key-name $KEYPAIR --instance-type t2.micro --subnet-id $$PRIVATE_SUBNET_ID --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=XTR-03}]' --user-data file://software.txt

echo "created one FSR and 2 extract machines"
