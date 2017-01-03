#!/usr/bin/env bash
aws cloudformation package \
    --template-file stack.yaml \
    --s3-bucket $BUCKET \
    --s3-prefix $CLUSTER_NAME/infrastructure | \
    sed 's/s3:\/\//https:\/\/s3.amazonaws.com\//g' > /tmp/$CLUSTER_NAME-infrastructure.yaml

aws cloudformation deploy \
    --stack-name $CLUSTER_NAME \
    --parameter-overrides VPC=$VPC_ID Subnets=$SUBNETS \
    --template-file /tmp/$CLUSTER_NAME-infrastructure.yaml \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM \
    --region $AWS_REGION
