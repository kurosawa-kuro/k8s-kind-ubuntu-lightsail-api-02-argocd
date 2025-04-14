以下は **Helm チュートリアル完了後** に進める形の **Argo CD チュートリアル** です。  
対象環境は、Lightsail の Ubuntu 上で `kind` を使ったローカル Kubernetes クラスターを想定しています。  
Argo CD をインストールし、Gitリポジトリにある Helm Chart を GitOps で自動デプロイする流れを、**最小構成**＆**シンプルな手順**でまとめました。

---

# Argo CD チュートリアル

このドキュメントでは、**Helm** でデプロイ可能なアプリケーションを **Argo CD** により **GitOps** で自動同期（Sync）させる流れを解説します。

> **前提：**
> 
> - すでに Kind クラスター上で Helm チャートをローカルから手動デプロイできる状態
>     
> - Lightsail 上の Ubuntu に Docker / Kind / kubectl / helm などが導入済み
>     
> - 「Helm Chart チュートリアル（Ingress/HPA/ServiceAccount 無効化）」を完了している
>     

## 目次

1. [Argo CD の概要](https://chatgpt.com/c/67fcc1a8-197c-800e-bbce-23e54bd284fc#1-argo-cd-%E3%81%AE%E6%A6%82%E8%A6%81)
    
2. [Argo CD のインストール](https://chatgpt.com/c/67fcc1a8-197c-800e-bbce-23e54bd284fc#2-argo-cd-%E3%81%AE%E3%82%A4%E3%83%B3%E3%82%B9%E3%83%88%E3%83%BC%E3%83%AB)
    
3. [Argo CD へログイン](https://chatgpt.com/c/67fcc1a8-197c-800e-bbce-23e54bd284fc#3-argo-cd-%E3%81%B8%E3%83%AD%E3%82%B0%E3%82%A4%E3%83%B3)
    
4. [Application マニフェストの作成](https://chatgpt.com/c/67fcc1a8-197c-800e-bbce-23e54bd284fc#4-application-%E3%83%9E%E3%83%8B%E3%83%95%E3%82%A7%E3%82%B9%E3%83%88%E3%81%AE%E4%BD%9C%E6%88%90)
    
5. [Application のデプロイ（GitOps 運用）](https://chatgpt.com/c/67fcc1a8-197c-800e-bbce-23e54bd284fc#5-application-%E3%81%AE%E3%83%87%E3%83%97%E3%83%AD%E3%82%A4gitops-%E9%81%8B%E7%94%A8)
    
6. [動作確認](https://chatgpt.com/c/67fcc1a8-197c-800e-bbce-23e54bd284fc#6-%E5%8B%95%E4%BD%9C%E7%A2%BA%E8%AA%8D)
    
7. [トラブルシュート](https://chatgpt.com/c/67fcc1a8-197c-800e-bbce-23e54bd284fc#7-%E3%83%88%E3%83%A9%E3%83%96%E3%83%AB%E3%82%B7%E3%83%A5%E3%83%BC%E3%83%88)
    
8. [まとめ](https://chatgpt.com/c/67fcc1a8-197c-800e-bbce-23e54bd284fc#8-%E3%81%BE%E3%81%A8%E3%82%81)
    

---

## 1. Argo CD の概要

**Argo CD** は、Kubernetes 上で動作する **GitOps** ツールです。  
「指定した Git リポジトリ」と「実行中の Kubernetes リソース」とを比較し、差分があれば同期（Sync）してくれます。

- **GitOps**：アプリの宣言的マニフェスト（Helm Chart や K8s YAML）を**Git**で管理→Argo CD が定期的にチェック→自動/手動で同期
    
- **メリット**：
    
    - 手元で `helm install/upgrade` コマンドを叩かなくても、Gitリポジトリにプッシュすれば Argo CD が自動反映
        
    - 一貫性・再現性が高く、履歴管理も容易
        

---

## 2. Argo CD のインストール

### 2-1. ネームスペース作成

Argo CD は通常 `argocd` ネームスペースにインストールします。

```bash
kubectl create namespace argocd
```

### 2-2. 公式マニフェストでインストール

Argo CD 公式の **「Raw manifest」** を適用します。  
（[公式ドキュメント](https://argo-cd.readthedocs.io/en/stable/getting_started/#1-install-argo-cd) 参照）

```bash
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

適用が成功すると、以下のような Deployment / Service / ConfigMap などが `argocd` ネームスペースに作成されます。

```bash
kubectl get pods -n argocd
# argo-cd-application-controller-xxxx
# argo-cd-repo-server-xxxx
# argo-cd-server-xxxx
# argo-cd-dex-server-xxxx
```

- 全てが `Running` になるまで1~2分ほど待機してください。
    

---

## 3. Argo CD へログイン

### 3-1. Argo CD サーバーへのポートフォワード

インストール直後、まだ Ingress 等を作っていないので、`port-forward` で Argo CD にアクセスします。

```bash
# 注意: このポートフォワーディングは別のターミナルで実行してください
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

- ローカルホスト `https://localhost:8080` へアクセスすると、Argo CD のログイン画面が表示されます。
    
- **初期パスワード** は、`argocd-server` と同じ名前の Secret 内に格納されています。
    

### 3-2. 初期パスワードの確認

```bash
# admin アカウントの初期パスワード取得
kubectl get secret argocd-initial-admin-secret \
    -n argocd \
    -o jsonpath="{.data.password}" | base64 -d
```

表示された文字列をメモし、ブラウザの Argo CD ログイン画面で `admin` / `<上記パスワード>` を入力してください。  
初回ログイン時に任意のパスワードに変更するのがおすすめです。

---

## 4. Application マニフェストの作成

Argo CD では、Kubernetes 上で動作する Argo CD の「カスタムリソース」(**`Application`**) を作成し、Git リポジトリとの同期設定を行います。

### 4-1. Helm Chart 構成のリポジトリ

本チュートリアルの例では、リポジトリ構成を以下のように想定します。（既に作成済み）

```
~/dev/k8s-kind-ubuntu-lightsail-api-01-helm/
├── helm/
│   └── my-app-chart/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           └── ...
└── (その他ファイル)
```

ここでは `helm/my-app-chart` ディレクトリにある Helm Chart を、**リリース名 `container-api`** でデプロイしたいとします。

### 4-2. Application YAML の例

```yaml
# file: argocd-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: container-api         # Argo CD 上での Application 名
  namespace: argocd           # Argo CD がインストールされているネームスペース
spec:
  project: default

  source:
    repoURL: 'https://github.com/<YOUR-ACCOUNT>/<YOUR-REPO>.git'
    targetRevision: HEAD               # Git のブランチやタグ、コミットハッシュなど
    path: helm/my-app-chart            # Chart が存在するディレクトリ
    helm:
      releaseName: container-api       # helm install 時のリリース名
      # values ファイルを追加したい場合は以下のように
      # valueFiles:
      #   - values-production.yaml

  destination:
    server: 'https://kubernetes.default.svc'
    namespace: default                 # デプロイ先の Namespace

  syncPolicy:
    # 自動同期(プル)を有効化する場合
    automated:
      prune: true       # 差分があれば不要リソースを削除
      selfHeal: true    # 手動変更されたリソースを元に戻す
```

> - `repoURL` は **HTTPS でアクセス可能な Git リポジトリ** を指定
>     
> - `path` には Helm Chart を格納している相対パスを指定
>     
> - `releaseName` は Helm リリース名（`helm install <releaseName> <chartPath>` 相当）
>     
> - `destination.namespace` はデプロイ先の Kubernetes Namespace
>     

---

## 5. Application のデプロイ（GitOps 運用）

### 5-1. Application の適用

作成した `argocd-application.yaml` を `argocd` ネームスペースに適用します。

```bash
kubectl apply -f argocd-application.yaml -n argocd
```

### 5-2. Argo CD の UI で確認

- 再度 `kubectl port-forward svc/argocd-server -n argocd 8080:443` を実行し、  
    ブラウザの `https://localhost:8080` にアクセス
    
- 左メニューから `Applications` を選択
    
- `container-api` (先ほど定義した Application 名) が表示されればOK
    
- **SYNC STATUS** が `Synced` になれば、Kubernetes に Helm でデプロイが行われています。
    

### 5-3. CLI でも確認

```bash
# Pod が起動しているか確認
kubectl get pods -n default

# ArgoCDのアプリケーション状態を確認
kubectl get application -n argocd container-api

# 注意: ArgoCD経由でデプロイされた場合、helm listでは表示されない場合があります
# これは正常な動作です
```

Argo CD 経由で Helm リリースが作成されるため、`helm list` にも `container-api` が表示されます。

---

## 6. 動作確認

### 6-1. Pod 内で API 動作確認

本チュートリアルでは **Ingress** を使わず、**Pod 内部** で `curl localhost:8080` することがゴールです。

1. Pod を探す
    
    ```bash
    kubectl get pods -n default
    # => container-api-my-app-chart-xxxxx という名前があるはず
    ```
    
2. Pod 内に入って `curl`
    
    ```bash
    kubectl exec -it <pod名> -n default -- sh
    
    # コンテナのシェル内:
    # 注意: コンテナ内にcurlがインストールされていない場合は、
    # 以下のいずれかの方法で確認してください：
    
    # 方法1: 別のポートでポートフォワーディング
    # 別のターミナルで:
    kubectl port-forward pod/<pod名> -n default 8081:8080
    
    # ローカルマシンで:
    curl http://localhost:8081
    
    # 方法2: デバッグ用Podを作成
    kubectl run -it --rm debug --image=curlimages/curl -- sh
    curl http://<pod名>:8080
    ```
    

### 6-2. もし外部アクセスしたい場合

- 一番シンプルなのは `kubectl port-forward`
    
    ```bash
    kubectl port-forward svc/container-api-my-app-chart -n default 8080:8080
    # localhost:8080 へアクセス
    ```
    
- 本番運用で外部公開したい場合は、NodePort や Ingress を後で追加してください。
    

---

## 7. トラブルシュート

1. **Argo CD の Pod が起動しない**
    
    - `kubectl describe pod` 等でエラーを確認
        
    - version mismatch などの場合は Argo CD 公式リポジトリから最新の `install.yaml` を適用してください。
        
2. **Helm Chart の参照が失敗する**
    
    - `argocd-application.yaml` 内の `repoURL` や `path` が正しいか確認
        
    - **Git リポジトリが Private** の場合、Argo CD に SSH Key / HTTPS Credential の設定が必要です。
        
3. **アプリが Sync されない**
    
    - Argo CD UI 上で **Refresh** → **Sync** を手動実行してみる
        
    - `automated` が有効かどうかを確認する（有効でなければ手動 Sync が必要）
        
4. **ECR イメージ Pull 失敗**
    
    - 既に Helm チュートリアルで実施したように、Kind の `containerdConfigPatches` で ECR 認証設定を行っているか確認
        
    - あるいは `kubectl create secret docker-registry` で K8s の ImagePullSecrets を設定し、Helm values.yaml で参照
        
5. **ポートフォワーディングの競合**
    
    - ArgoCDサーバーとアプリケーションで同じポート（8080）を使用している場合、
      別のポート番号を使用してポートフォワーディングを行ってください。
    
    ```bash
    # ArgoCDサーバー
    kubectl port-forward svc/argocd-server -n argocd 8080:443
    
    # アプリケーション（別のターミナルで）
    kubectl port-forward pod/<pod名> -n default 8081:8080
    ```

---

## 8. まとめ

これで **Argo CD** を使った **GitOps** デプロイの基礎が完成です。

- Git リポジトリに `helm/my-app-chart` を置く
    
- Argo CD に `Application` リソースを作成し、Helm の `releaseName`・`path` を指定
    
- Git の更新 → Argo CD が差分検知 → 自動 or 手動で同期
    
- Pod 内部で `curl localhost:8080` して動作確認
    

### 次のステップ

- **Ingress** や **HPA** を Helm で有効化し、外部公開 & スケーリングを試す
    
- **複数の環境 (dev, staging, prod)** 用に Argo CD `ApplicationSet` を活用
    
- **自動テスト** や **CI/CD** との連携で、プルリクマージ → Argo CD デプロイをより堅牢に
    

GitOps による運用は最初こそ設定が多いですが、一度整うと極めて快適で、一貫性の高い Kubernetes デプロイを実現できます。ぜひ活用してみてください。