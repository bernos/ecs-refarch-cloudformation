#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# OUTPUTS=$(aws cloudformation describe-stacks --stack-name ca-profile-enhancement-worker-base-dev-LoggingStack-BIR72JXRUJU9 --region $AWS_REGION --query "Stacks[].Outputs[].{OutputKey:OutputKey,OutputValue:OutputValue}" --output text)

# while read line
# do
#     name=`echo $line | cut -d' ' -f1`
#     value=`echo $line | cut -d' ' -f2`

#     export $name=$value
# done <<< "$(echo -e "$OUTPUTS")"

aws cloudformation package \
    --template-file services/product-service/service.yaml \
    --s3-bucket $BUCKET \
    --s3-prefix $CLUSTER_NAME/services/product-service | \
    sed 's/s3:\/\//https:\/\/s3.amazonaws.com\//g' > /tmp/$CLUSTER_NAME-product-service.yaml

aws cloudformation deploy \
    --stack-name $CLUSTER_NAME-product-service \
    --parameter-overrides VPC=$VPC_ID Cluster=$CLUSTER_NAME Listener=arn:aws:elasticloadbalancing:ap-southeast-2:972133901078:listener/app/ecs-refarch-sandbox/e1b1804aa074c85f/9cb54a0b2592dfd5 DesiredCount=2 Path=/products \
    --template-file /tmp/$CLUSTER_NAME-product-service.yaml \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM \
    --region $AWS_REGION
