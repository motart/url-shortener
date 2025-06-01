#!/bin/bash

# List all S3 buckets (optionally filter with a prefix)
buckets=$(aws s3api list-buckets --query "Buckets[].Name" --output text)

for bucket in $buckets; do
  echo "Deleting contents of bucket: $bucket"

  # Delete all objects (recursive delete)
  aws s3 rm s3://$bucket --recursive

  echo "Deleting bucket: $bucket"
  aws s3api delete-bucket --bucket $bucket
done
