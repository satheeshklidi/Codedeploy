#! /bin/bash


AZ=ap-south-1a
echo -e "Enter the CIDR for VPC: \c"
read CIDR
echo "The CIDR entered is $CIDR"
echo -e "Enter the VPC Name: \c"
read VPC_NAME
# create VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block $CIDR --query 'Vpc.{VpcId:VpcId}' --output text)
echo "VPC ID $VPC_ID created successfully"
#Add tags to the created VPC
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME
echo "VPC ID $VPC_ID named as $VPC_NAME"
#Create public and private subnets
echo -e "Enter Public Subnet: \c"
read PUBLIC_SUBNET
echo -e "Enter private Subnet: \c"
read PRIVATE_SUBNET
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET --availability-zone $AZ --query 'Subnet.{SubnetId:SubnetId}' --output text)
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET --availability-zone $AZ --query 'Subnet.{SubnetId:SubnetId}' --output text)
echo "Created Public subnet $PUBLIC_SUBNET and private subnet $PRIVATE_SUBNET successfully"
aws ec2 create-tags --resources $PUBLIC_SUBNET_ID --tags "Key=Name,Value=Public_Subnet"
aws ec2 create-tags --resources $PRIVATE_SUBNET_ID --tags "Key=Name,Value=Private_Subnet"
echo "Named $PUBLIC_SUBNET as Public Subnet and $PRIVATE_SUBNET as Private Subnet"

#Create Internet gateway
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.{InternetGatewayId:InternetGatewayId}' --output text)
echo "Internet gateway created successfully"
aws ec2 create-tags --resources $IGW_ID --tags "Key=Name,Value=Internet_Gateway"

#Attach Internet gateway to the VPC
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
echo "Internet gateway attached to VPC"

#Allocate Elastic IP for NAT Gateway

ELASTICIP_ID=$(aws ec2 allocate-address --domain vpc --query '{AllocationId:AllocationId}' --output text)
aws ec2 create-tags --resources $ELASTICIP_ID --tags "Key=Name,Value=NAT_Gateway_IP"
echo "Elastic IP allocated"

#Create NAT Gateway

NATGW_ID=$(aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUBNET_ID --allocation-id $ELASTICIP_ID --query 'NatGateway.{NatGatewayId:NatGatewayId}' --output text)

FORMATTED_MSG="Creating NAT Gateway ID '$NATGW_ID' and waiting for it to become available "
FORMATTED_MSG+="become available.\n    Please BE PATIENT as this can take some "
FORMATTED_MSG+="time to complete.\n    ......\n"
printf "  $FORMATTED_MSG"
FORMATTED_MSG="STATUS: %s  -  %02dh:%02dm:%02ds elapsed while waiting for NAT "
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
  printf "    $STATUS_MSG\033[0K\r"
  sleep 1
done
printf "\n    ......\n  NAT Gateway ID '$NATGW_ID' is now AVAILABLE.\n"

aws ec2 create-tags --resources $NATGW_ID --tags "Key=Name,Value=NAT_Gateway"

#Create Private route table

PRIVATERT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.{RouteTableId:RouteTableId}' --output text)
aws ec2 create-tags --resources $PRIVATERT_ID --tags "Key=Name,Value=Private_table"
echo "Private route table created"

#Add route to private route table

aws ec2 create-route --route-table-id $PRIVATERT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $NATGW_ID

echo "routed 0.0.0.0/0 to NAT Gateway" 

#Associate Private route table to private subnet

aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_ID --route-table-id $PRIVATERT_ID
echo "private route table associated to private subnet"

#Create Public route table

PUBLICRT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.{RouteTableId:RouteTableId}' --output text)
aws ec2 create-tags --resources $PUBLICRT_ID --tags "Key=Name,Value=Public_table"
echo "Public route table created"

#Add route to public route table

aws ec2 create-route --route-table-id $PUBLICRT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

echo "routed 0.0.0.0/0 to Internet Gateway"

#Associate public route table to public subnet

aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_ID --route-table-id $PUBLICRT_ID
echo "public route table associated to Public subnet"
