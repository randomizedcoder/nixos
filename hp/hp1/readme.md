

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sudo chown root:wheel /etc/rancher/k3s/k3s.yaml && sudo chmod 640 /etc/rancher/k3s/k3s.yaml

export KUBECONFIG=./k3s.yaml
kubectl --namespace pyroscope-test port-forward svc/pyroscope 4040:4040


http://pyroscope.pyroscope-test.svc.cluster.local.:4040