# old string : postgresql://username:xxxxxxxxxxxxxxxxxx@db-endpoint-replica.randaccount.us-east-1.rds.amazonaws.com:5432/aggregator 
# new string : postgresql://username:xxxxxxxxxxxxxxxxxx@db-endpoint.randaccount.us-east-1.rds.amazonaws.com/aggregator
#
#use this to alter a value of a secret in k8s
#the commands will make a backup, change and upgrade then another copy to further check
kubedecode k8s-secret
kubectl get secret k8s-secret -o json > /tmp/prd.bkp.k8s-secret
kubectl get secret k8s-secret -o json |  jq --arg ENDPOINT_URL "$(echo -n postgresql://username:xxxxxxxxxxxxxxxxxx@db-endpoint.randaccount.us-east-1.rds.amazonaws.com:5432/aggregator | base64 -w 0)" '.data["ENDPOINT_URL"]=$ENDPOINT_URL' | kubectl apply -f -
kubectl get secret k8s-secret -o json > /tmp/prd.new.k8s-secret
kubedecode k8s-secret

