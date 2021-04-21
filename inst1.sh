#! /bin/bash

CIDR=10.0.0.0/16

aws ec2 authorize-security-group-ingress --group-id sg-062215ded54d1fc80 --ip-permissions IpProtocol=-1,IpRanges=[{CidrIp=10.12.0.0/16}] IpProtocol=-1,IpRanges=[{CidrIp=10.14.0.0/16}] IpProtocol=-1,IpRanges=[{CidrIp=192.168.0.0/16}] IpProtocol=-1,IpRanges=[{CidrIp=$CIDR}]


