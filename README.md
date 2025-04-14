以下に **Helm 入門者**が高い成功確率・再現性で学習できるように、**Kind クラスター**を使って **Ingress/HPA/ServiceAccount を無効化**した最小構成の Helm Chart をデプロイする手順を **README形式** でまとめています。  
「とりあえずこの手順を順番にコピペ・実行すれば同じ状態になる」ことを目標に、詳細説明を交えました。

---

# Helm Chart 最小構成チュートリアル（Ingress/HPA/ServiceAccount 無効化）

本チュートリアルでは、**Helm** の標準雛形をベースに **Ingress/HPA/ServiceAccount** を「削除」ではなく「設定で無効化」しつつ、**Kubernetes** 上に **Deployment/Service** のみをデプロイします。  
**Kind** を使ってローカルクラスターを簡単に立ち上げ、AWS ECR に置いたイメージ (`986154984217.dkr.ecr.ap-northeast-1.amazonaws.com/container-nodejs-api-8080:latest`) を Pull するところまで含めた手順です。

> **ポイント**  
> - **テンプレートファイルはできるだけ削除/改変せず**、将来拡張しやすい構成  
> - NodePort や Ingress を使わず、内部 ClusterIP + `port-forward` でアクセス確認  
> - **Kind** でコンテナ内から ECR のイメージを取得するための設定を付与

---

## 目次

1. [事前準備](#1-事前準備)  
2. [Kind クラスターを作成](#2-kind-クラスターを作成)  
3. [Helm Chart 雛形を作成](#3-helm-chart-雛形を作成)  
4. [values.yaml で Ingress/HPA/ServiceAccount 無効化設定](#4-valuesyaml-で-ingresshpaserviceaccount-無効化設定)  
5. [テンプレートの確認 (helm template)](#5-テンプレートの確認-helm-template)  
6. [インストール (helm install)](#6-インストール-helm-install)  
7. [動作確認 (port-forward)](#7-動作確認-port-forward)  
8. [アップグレード例（replicaCount 変更）](#8-アップグレード例replicacount-変更)  
9. [アンインストール](#9-アンインストール)  
10. [まとめ](#10-まとめ)  

---

## 1. 事前準備

- **Docker** がインストール済み & `docker ps` 実行可能
- **Kind** (Kubernetes in Docker) がインストール済み
- **Helm** がインストール済み  
- **AWS CLI** で `aws ecr get-login-password` が使える (ECR へのログイン)
- `kubectl` で Kubernetes にアクセスできる状態

---

## 2. Kind クラスターを作成

### 2-1. AWS ECR へのログイン用トークンを取得

```bash
ECR_TOKEN=$(aws ecr get-login-password --region ap-northeast-1)
```

### 2-2. Kind 用の設定ファイル (kind-cluster.yaml)

```bash
cat <<EOF > kind-cluster.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry]
      [plugins."io.containerd.grpc.v1.cri".registry.auths."986154984217.dkr.ecr.ap-northeast-1.amazonaws.com"]
        username = "AWS"
        password = "$ECR_TOKEN"
EOF
```

### 2-3. Kind クラスター起動

```bash
# クラスターを削除
kind delete cluster

kind create cluster --config kind-cluster.yaml
kind get clusters
# => "kind" が表示されればOK
```

これでローカル上に Kind クラスターが立ち上がり、**ECR** からのイメージ Pull に対応できるようになります。

---

## 3. Helm Chart 雛形を作成

```bash
mkdir -p ~/dev/k8s-kind-helm-tutorial
cd ~/dev/k8s-kind-helm-tutorial

# Chart名: my-app-chart
helm create my-app-chart
```

すると以下のフォルダ構成が生成されます。

```
my-app-chart/
├── Chart.yaml
├── values.yaml
├── charts/
├── templates/
│   ├── _helpers.tpl
│   ├── deployment.yaml
│   ├── hpa.yaml
│   ├── ingress.yaml
│   ├── service.yaml
│   ├── serviceaccount.yaml
│   └── tests/
└── .helmignore
```

---

## 4. values.yaml で Ingress/HPA/ServiceAccount 無効化設定

`my-app-chart/values.yaml` を開き、下記のように設定します。  
特に **`ingress.enabled = false` / `autoscaling.enabled = false` / `serviceAccount.create = false`** が重要です。

```yaml
replicaCount: 1

image:
  repository: 986154984217.dkr.ecr.ap-northeast-1.amazonaws.com/container-nodejs-api-8080
  tag: "latest"
  pullPolicy: Always

containerPort: 8080

service:
  type: ClusterIP
  port: 8080

serviceAccount:
  create: false
  name: ""
  annotations: {}

ingress:
  enabled: false
  className: ""
  annotations: {}
  hosts: []
  tls: []

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 3
  targetCPUUtilizationPercentage: 80

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

> - **Ingress, HPA, ServiceAccount** を「削除せず、設定で無効化」  
> - イメージを **`986154984217.dkr.ecr.ap-northeast-1.amazonaws.com/container-nodejs-api-8080:latest`** に変更  
> - **ポート番号は 8080** に統一  

---

## 5. テンプレートの確認 (helm template)

```bash
cd my-app-chart
helm template . --values values.yaml
```

- `ingress.yaml`, `hpa.yaml`, `serviceaccount.yaml` に **if 分岐** があるため、`enabled: false` / `create: false` のときはリソースが出力されません。  
- 出力されるのは **Deployment** と **Service** のみであれば成功です。

---

## 6. インストール (helm install)

```bash
# リリース名を "container-api" にする例
helm install container-api . --values values.yaml

# Pod/Service確認
kubectl get pods
kubectl get svc
helm list
```

- Pod が `Running` & `READY 1/1` になればOK

---

## 7. 動作確認 (port-forward)

Ingress, NodePort を使わないため、`port-forward` でアクセスします。

```bash
kubectl port-forward service/container-api-my-app-chart 8080:8080
# => コンソールに "Forwarding from 127.0.0.1:8080 -> 8080" 等が表示

# 別ターミナルで
curl -v http://localhost:8080/
# => {"status":"ok", "timestamp":"..."} 等のレスポンスが返れば成功
```

> **Service名** はデフォルトで `リリース名-チャート名` の形式になり、  
> 今回は `container-api-my-app-chart` と推定されます。  
> `kubectl get svc` で正確な名前を確認してください。

---

## 8. アップグレード例（replicaCount 変更）

```bash
# Replicaを2に変更
helm upgrade container-api . --set replicaCount=2
kubectl get pods
# => Podが2つになる
```

---

## 9. アンインストール

```bash
helm uninstall container-api
```

これで作成された Kubernetes リソース（Deployment, Serviceなど）がすべて削除されます。

---

## 10. まとめ

- **Kind** + **Helm** + **AWS ECR** で最小構成のアプリを簡単デプロイ  
- **Ingress/HPA/ServiceAccount** はテンプレートを**削除せず**、`values.yaml` の `enabled` / `create` フラグで無効化  
- NodePort / Ingress を使わず、`port-forward` で内部アクセスのみ確認  
- 後から `enabled: true` にするだけで機能拡張可能  

これにより、Helm 入門者でも **高い再現性**・**成功率** で Kubernetes デプロイを体験できます。テンプレートファイルの改変を最小限にとどめるため、今後の拡張や修正も簡単です。  


admin
v1G9e1ziJN7aQAGn