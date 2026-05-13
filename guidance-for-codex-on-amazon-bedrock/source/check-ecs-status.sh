#!/bin/bash
# Helper script to check ECS service status
# Usage: ./check-ecs-status.sh

set -e

export AWS_PROFILE=dinsajwa
export AWS_REGION=us-west-2

CLUSTER_NAME="codex-litellm-gateway"

echo "═══════════════════════════════════════════════════════════════"
echo "🔍 ECS SERVICE STATUS CHECK"
echo "═══════════════════════════════════════════════════════════════"
echo "Profile: $AWS_PROFILE"
echo "Region: $AWS_REGION"
echo "Cluster: $CLUSTER_NAME"
echo ""

# Check if cluster exists
echo "Checking if cluster exists..."
if ! aws ecs describe-clusters --clusters $CLUSTER_NAME --region $AWS_REGION --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
    echo "❌ Cluster '$CLUSTER_NAME' not found or not active"
    echo ""
    echo "This means the gateway stack hasn't been deployed yet."
    echo ""
    echo "To deploy:"
    echo "  cd guidance-for-codex-on-amazon-bedrock/source"
    echo "  uv run cxwb build --profile codex-bedrock-gw"
    echo "  uv run cxwb deploy --profile codex-bedrock-gw"
    exit 1
fi

echo "✓ Cluster is ACTIVE"
echo ""

# List services
echo "Finding services..."
SERVICES=$(aws ecs list-services --cluster $CLUSTER_NAME --region $AWS_REGION --query 'serviceArns' --output text)

if [ -z "$SERVICES" ]; then
    echo "❌ No services found in cluster"
    exit 1
fi

SERVICE_NAME=$(echo $SERVICES | awk '{print $1}' | rev | cut -d'/' -f1 | rev)
echo "✓ Found service: $SERVICE_NAME"
echo ""

# Get service details
echo "Service Status:"
echo "───────────────────────────────────────────────────────────────"
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $AWS_REGION \
    --query 'services[0].{Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount}' \
    --output table

echo ""
echo "Recent Service Events:"
echo "───────────────────────────────────────────────────────────────"
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $AWS_REGION \
    --query 'services[0].events[0:5].[createdAt,message]' \
    --output table

echo ""
echo "Tasks:"
echo "───────────────────────────────────────────────────────────────"
TASKS=$(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME --region $AWS_REGION --query 'taskArns' --output text)

if [ -z "$TASKS" ]; then
    echo "❌ No tasks found"
    echo ""
    echo "Check CloudFormation events:"
    echo "  aws cloudformation describe-stack-events --stack-name codex-litellm-gateway --region $AWS_REGION --max-items 10"
    exit 1
fi

for TASK_ARN in $TASKS; do
    TASK_ID=$(echo $TASK_ARN | rev | cut -d'/' -f1 | rev)
    echo ""
    echo "Task: $TASK_ID"
    aws ecs describe-tasks \
        --cluster $CLUSTER_NAME \
        --tasks $TASK_ARN \
        --region $AWS_REGION \
        --query 'tasks[0].{LastStatus:lastStatus,DesiredStatus:desiredStatus,HealthStatus:healthStatus,StartedAt:startedAt,StoppedReason:stoppedReason}' \
        --output table

    # Check for specific errors in stopped reason
    STOPPED_REASON=$(aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN --region $AWS_REGION --query 'tasks[0].stoppedReason' --output text 2>/dev/null || echo "")
    if [[ -n "$STOPPED_REASON" && "$STOPPED_REASON" != "None" ]]; then
        echo ""
        echo "❌ Task stopped reason:"
        echo "$STOPPED_REASON"

        # Check for common errors
        if echo "$STOPPED_REASON" | grep -q "exec format error"; then
            echo ""
            echo "🔴 ARCHITECTURE MISMATCH DETECTED"
            echo "   Your Docker image was built for the wrong architecture."
            echo "   Rebuild with: uv run cxwb build --profile codex-bedrock-gw"
        fi

        if echo "$STOPPED_REASON" | grep -q "unable to pull secrets"; then
            echo ""
            echo "🔴 SECRETS MANAGER ACCESS ISSUE"
            echo "   Task can't reach AWS Secrets Manager."
            echo "   Check VPC endpoints or network configuration."
        fi
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "To view live CloudWatch logs:"
echo "  aws logs tail /ecs/litellm --follow --region $AWS_REGION --profile $AWS_PROFILE"
echo ""
echo "To check in AWS Console:"
echo "  https://us-west-2.console.aws.amazon.com/ecs/v2/clusters/$CLUSTER_NAME/services"
echo ""
echo "═══════════════════════════════════════════════════════════════"
