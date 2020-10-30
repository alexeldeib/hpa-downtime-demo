#!/usr/bin/env bash
set -o nounset
set -o errexit
set -o pipefail
# set -x

# Retries a command on failure.
# $1 - the max number of attempts
# $2... - the command to run
function retry() {
    local -r -i max_attempts="$1"; shift
    local -r cmd="$@"
    local -i attempt_num=1

    until $cmd
    do
        if (( attempt_num == max_attempts ))
        then
            echo "Attempt $attempt_num failed and there are no more attempts left!"
            return 1
        else
            echo "Attempt $attempt_num failed! Trying again in $attempt_num seconds..."
            sleep $(( attempt_num++ ))
        fi
    done
}

# roll a ds/deploy/whatever 
#
# $1 - string passed to kubectl to identify the resource. e.g. "-n hpa-demo deploy/hpa-demo"
#
# no quoting of positional parameters takes place, add flags for
# namespace as required
function roll() {
    export TAG="$(date -Ins | tr :+, -)"
    envsubst < patch-force-deploy.json > out.json
    kubectl patch $@ --type='json' -p="$(cat out.json | tr -d '\n')"
    kubectl rollout status $@
}

echo "creating namespace"
kubectl create ns hpa-demo --dry-run=client -o yaml | kubectl apply -f -

echo "applying initial manifests without replicas"
kubectl apply -f manifest.yaml

echo "waiting for rollout to settle"
kubectl -n hpa-demo rollout status deploy hpa-demo

echo "waiting for hpa to scale up"
max_attempts=10
attempts=0
available="$(kubectl get -n hpa-demo deploy hpa-demo -o jsonpath="{.status.availableReplicas}")"
while [ "$available" -lt "2" ]; do
    let attempts=attempts+1
    if [ "$attempts" -gt 10 ]; then
        "HPA failed to scale up initial pods"
        exit 1
    fi
    echo "$available available pods, sleeping $attempts seconds"
    available="$(kubectl get -n hpa-demo deploy hpa-demo -o jsonpath="{.status.availableReplicas}")"
    sleep "$attempts"
done

echo "$available available pods after $attempts seconds"
sleep 5

echo "rolling pods, should not violate maxUnavailable"
roll -n hpa-demo deploy/hpa-demo

sleep 5

echo "again, rolling pods, should not violate maxUnavailable"
roll -n hpa-demo deploy/hpa-demo

sleep 5

echo "adding replicas from original manifests and re-applying"
echo "***should violate maxUnavailable***"
kustomize build . | kubectl apply -f -

echo "waiting for hpa to scale up"
max_attempts=10
attempts=0
available="$(kubectl get -n hpa-demo deploy hpa-demo -o jsonpath="{.status.availableReplicas}")"
while [ "$available" -lt "2" ]; do
    let attempts=attempts+1
    if [ "$attempts" -gt 10 ]; then
        "HPA failed to scale up initial pods"
        exit 1
    fi
    echo "$available available pods, sleeping $attempts seconds"
    available="$(kubectl get -n hpa-demo deploy hpa-demo -o jsonpath="{.status.availableReplicas}")"
    sleep "$attempts"
done

sleep 5

echo "re-applying original manifests without replicas"
echo "***this will still violate maxUnavailable***"
echo "because the kubectl last-applied annotation knows about replicas"
kubectl apply -f manifest.yaml

echo "waiting for rollout to settle"
kubectl -n hpa-demo rollout status deploy hpa-demo

echo "waiting for hpa to scale up"
max_attempts=10
attempts=0
available="$(kubectl get -n hpa-demo deploy hpa-demo -o jsonpath="{.status.availableReplicas}")"
while [ "$available" -lt "2" ]; do
    let attempts=attempts+1
    if [ "$attempts" -gt 10 ]; then
        "HPA failed to scale up initial pods"
        exit 1
    fi
    echo "$available available pods, sleeping $attempts seconds"
    available="$(kubectl get -n hpa-demo deploy hpa-demo -o jsonpath="{.status.availableReplicas}")"
    sleep "$attempts"
done

sleep 5

echo "re-applying original manifests without replicas"
echo "***will not violate maxUnavailable***"
kubectl apply -f manifest.yaml

echo "waiting for rollout to settle"
kubectl -n hpa-demo rollout status deploy hpa-demo

sleep 5

echo "adding replicas from original manifests and re-applying"
echo "***should violate maxUnavailable***"
kustomize build . | kubectl apply -f -

echo "waiting for hpa to scale up"
max_attempts=10
attempts=0
available="$(kubectl get -n hpa-demo deploy hpa-demo -o jsonpath="{.status.availableReplicas}")"
while [ "$available" -lt "2" ]; do
    let attempts=attempts+1
    if [ "$attempts" -gt 10 ]; then
        "HPA failed to scale up initial pods"
        exit 1
    fi
    echo "$available available pods, sleeping $attempts seconds"
    available="$(kubectl get -n hpa-demo deploy hpa-demo -o jsonpath="{.status.availableReplicas}")"
    sleep "$attempts"
done

sleep 5

echo "removing kubectl annotations and re-applying manifest without replicas"
echo "***will not violate maxUnavailable***"
echo "since replicas is no longer known by kubectl"
kubectl patch -n hpa-demo deploy hpa-demo --type='json' -p="$(cat patch-remove-kubectl.json)"
kubectl apply -f manifest.yaml

echo "waiting for rollout to settle"
kubectl -n hpa-demo rollout status deploy hpa-demo

sleep 5

echo "cleaning up"
kubectl delete ns hpa-demo
sleep infinity
