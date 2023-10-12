regions=(
"us-east-1"
"us-west-2"
)


for region in ${regions[@]};
do
    echo "Region: ${region}"
    aws ec2 describe-images --region ${region} --owners self --filters Name="name",Values="ziti-tests-*" | jq '[.Images[] | { Id: .ImageId, Date: .CreationDate}] | sort_by(.Date)' | jq -r '.[] | (.Id + " " + .Date) ' 
done
