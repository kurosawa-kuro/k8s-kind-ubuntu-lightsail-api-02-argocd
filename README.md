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

はい、**それは完全に正しい指摘です。**  
その `helm upgrade --set replicaCount=2` は **Imperativeなコマンド操作**であり、GitOpsの原則（＝構成は全てGitで管理し、Gitの変更のみでクラスタを操作）に**反しています**。

---

以下に、**GitOpsに準拠するようにチュートリアルの「8. アップグレード例」セクションを修正**したバージョンをご提案します。

---

## ✅ 修正版：8. アップグレード例（replicaCount 変更）

```diff
- # Replicaを2に変更
- helm upgrade container-api . --set replicaCount=2
- kubectl get pods
- # => Podが2つになる
```

⬇️ **以下に置き換えます：**

---

## 8. アップグレード例（replicaCount 変更）

GitOps の観点からは、クラスタに直接コマンドで変更を加えるのではなく、**Git管理ファイル（`values.yaml`）を編集 → Git Push → Argo CD などのCDツールが自動反映**するのが理想です。

### 8-1. `values.yaml` を編集して replicaCount を変更

```yaml
# my-app-chart/values.yaml

replicaCount: 2
```

---

### 8-2. Git にコミットしてPush

```bash
cd ~/dev/k8s-kind-helm-tutorial/my-app-chart

git add values.yaml
git commit -m "Increase replicaCount to 2"
git push origin main
```

---

### 8-3. Argo CD が自動で更新反映

- Argo CD がこのGit変更を検知して `helm upgrade` 相当の処理を行い、Podが2つ起動します。
- 確認：

```bash
kubectl get pods
# => Podが2つになっていれば成功
```

---

> 🧠 **補足**：GitOpsでは「`helm upgrade` コマンドは使わない」のが基本ルールです。  
> すべての構成変更は Git に記述 → CDツールで同期 という流れに統一することで、変更履歴の一元管理と自動復旧（差分適用）が可能になります。

---

このように修正すれば、**GitOps完全準拠のチュートリアル**になります。  
ご希望であれば、他のセクションの文言も GitOps観点で整えます！

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

以下に、あなたのチュートリアルに**GitOps準拠のECRデプロイ項目**を「セクション11」として自然に追加しました。構成・トーンは既存チュートリアルに完全に合わせています。

---

## 11. ECR へのイメージPushと GitOps による Helm 自動アップデート

このステップでは、**アプリの新しいDockerイメージをビルド → ECRへPush → Helm Chartの`values.yaml`を更新 → Gitへコミット＆Push** という一連のフローを行い、**GitOps的にArgo CDなどによる自動デプロイ**を実現します。

> **ポイント**
> - 手動 `helm upgrade` を使わず、**Gitの更新をトリガー**にデプロイ
> - `image.tag` を更新するだけで Helm テンプレートに反映される設計

---

### 11-1. 現在の最新バージョンを確認 & タグをインクリメント

```bash
REPO="container-nodejs-api-8080"
REGION="ap-northeast-1"
ACCOUNT_ID="986154984217"

# 最新の vX タグを取得して次のタグを生成（v4 → v5）
LATEST_TAG=$(aws ecr list-images \
  --repository-name $REPO \
  --region $REGION \
  --query 'imageIds[?contains(imageTag, `v`)].imageTag' \
  --output text | grep ^v | sed 's/v//' | sort -nr | head -n1)
NEXT_TAG="v$((LATEST_TAG + 1))"

echo "次に使用するタグ: $NEXT_TAG"
```

---

### 11-2. Dockerビルド & ECRにPush

```bash
docker build -t $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:$NEXT_TAG .

aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:$NEXT_TAG
```

---

### 11-3. `values.yaml` の image.tag を更新

```bash
# Chartのルートに移動（~/dev/k8s-kind-helm-tutorial/my-app-chart）
cd ~/dev/k8s-kind-helm-tutorial/my-app-chart

# tag を新しいものに書き換え
sed -i "s/tag: .*/tag: \"$NEXT_TAG\"/" values.yaml
```

> Helm テンプレートでは以下のように定義されている前提です：
>
> ```yaml
> image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
> ```

---

### 11-4. Gitコミット & Push（GitOpsトリガー）

```bash
git add values.yaml
git commit -m "Update image tag to $NEXT_TAG"
git push origin main
```

これにより、**Gitリポジトリの更新がトリガーとなって、Argo CD などが自動的に `helm upgrade` 相当の処理を実行**します。

---

### 🧠 応用：この一連の処理を自動化するスクリプト例

```bash
#!/bin/bash
set -e

REPO="container-nodejs-api-8080"
REGION="ap-northeast-1"
ACCOUNT_ID="986154984217"

LATEST_TAG=$(aws ecr list-images \
  --repository-name $REPO \
  --region $REGION \
  --query 'imageIds[?contains(imageTag, `v`)].imageTag' \
  --output text | grep ^v | sed 's/v//' | sort -nr | head -n1)
NEXT_TAG="v$((LATEST_TAG + 1))"

docker build -t $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:$NEXT_TAG .
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:$NEXT_TAG

cd ~/dev/k8s-kind-helm-tutorial/my-app-chart
sed -i "s/tag: .*/tag: \"$NEXT_TAG\"/" values.yaml

git add values.yaml
git commit -m "Update image tag to $NEXT_TAG"
git push origin main
```

---

これで、**Helm Chart × Kind × ECR × GitOps** の最小構成ながらも、**本番さながらのCD体験がローカルで実現可能**になります。

---

> 📝 Argo CD 用の `Application.yaml` の例を付けたい場合は、お知らせください。  
> Chartパスやブランチ名に応じて自動生成も可能です。
