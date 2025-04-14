#!/bin/bash

# エラー発生時にスクリプトを終了
set -e

# AWS/ECR設定
readonly AWS_REGION="ap-northeast-1"
readonly AWS_ACCOUNT_ID="986154984217"
readonly ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
readonly ECR_REPOSITORY_NAME="container-nodejs-api-8080"
readonly ECR_IMAGE_TAG="latest"

# フルイメージパス
readonly ECR_IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY_NAME}:${ECR_IMAGE_TAG}"

# 色付きログ出力用の関数
log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1" >&2
}

# 前提条件チェック
check_prerequisites() {
    log_info "前提条件をチェックしています..."
    
    # kindコマンドの存在確認
    if ! command -v kind &> /dev/null; then
        log_error "kindがインストールされていません"
        exit 1
    fi

    # AWS CLIの存在確認
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLIがインストールされていません"
        exit 1
    fi

    # kubectlの存在確認
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectlがインストールされていません"
        exit 1
    fi

    log_success "前提条件のチェックが完了しました"
}

# AWS認証情報の確認
check_aws_credentials() {
    log_info "AWS認証情報を確認しています..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS認証情報が無効です"
        exit 1
    fi
    
    # ECRリポジトリへのアクセス確認
    if ! aws ecr describe-repositories --repository-names "${ECR_REPOSITORY_NAME}" --region "${AWS_REGION}" &> /dev/null; then
        log_error "ECRリポジトリ ${ECR_REPOSITORY_NAME} にアクセスできません"
        exit 1
    fi
    
    log_success "AWS認証情報の確認が完了しました"
}

# 既存クラスターの削除
cleanup_existing_cluster() {
    log_info "既存のkindクラスターを確認しています..."
    
    if kind get clusters | grep -q "^kind$"; then
        log_info "既存のkindクラスターを削除します..."
        kind delete cluster
        log_success "既存のkindクラスターを削除しました"
    else
        log_info "削除が必要な既存クラスターはありません"
    fi
}

# kindクラスター設定ファイルの生成
create_cluster_config() {
    log_info "クラスター設定ファイルを生成しています..."
    
    # ECRトークンの取得
    local ECR_TOKEN
    ECR_TOKEN=$(aws ecr get-login-password --region "${AWS_REGION}")
    
    # 設定ファイルの生成
    cat > kind-cluster.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
containerdConfigPatches:
- |-
    [plugins."io.containerd.grpc.v1.cri".registry]
      [plugins."io.containerd.grpc.v1.cri".registry.auths."${ECR_REGISTRY}"]
        username = "AWS"
        password = "${ECR_TOKEN}"
EOF
    
    log_success "クラスター設定ファイルを生成しました"
}

# kindクラスターの作成
create_cluster() {
    log_info "kindクラスターを作成しています..."
    
    if ! kind create cluster --config kind-cluster.yaml; then
        log_error "クラスターの作成に失敗しました"
        exit 1
    fi
    
    log_success "kindクラスターを作成しました"
}

# クラスターの状態確認
verify_cluster() {
    log_info "クラスターの状態を確認しています..."
    
    # クラスターの状態確認
    if ! kubectl cluster-info &> /dev/null; then
        log_error "クラスターが正常に動作していません"
        exit 1
    fi
    
    # ノードの状態確認
    if ! kubectl get nodes | grep -q "Ready"; then
        log_error "ノードが準備できていません"
        exit 1
    fi
    
    log_success "クラスターが正常に動作しています"
}

# クリーンアップ処理
cleanup() {
    log_info "クリーンアップを実行します..."
    rm -f kind-cluster.yaml
    log_success "クリーンアップが完了しました"
}

# メイン処理
main() {
    log_info "kindクラスターのセットアップを開始します..."
    
    log_info "使用するECR設定:"
    echo "リージョン: ${AWS_REGION}"
    echo "アカウントID: ${AWS_ACCOUNT_ID}"
    echo "ECRレジストリ: ${ECR_REGISTRY}"
    echo "リポジトリ名: ${ECR_REPOSITORY_NAME}"
    echo "イメージURI: ${ECR_IMAGE_URI}"
    
    check_prerequisites
    check_aws_credentials
    cleanup_existing_cluster
    create_cluster_config
    create_cluster
    verify_cluster
    cleanup
    
    log_success "kindクラスターのセットアップが完了しました"
    
    # 最終的なクラスター情報の表示
    echo -e "\n=== クラスター情報 ==="
    kubectl cluster-info
    echo -e "\n=== ノード状態 ==="
    kubectl get nodes
}

# スクリプトの実行
main "$@"