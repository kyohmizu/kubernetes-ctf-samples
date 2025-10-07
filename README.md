# Kubernetes CTF Samples

Kubernetes CTF（Capture The Flag）のサンプル問題集です。

## 環境準備

Killercoda などの Playground サービスを使用することを推奨します。

- [Killercoda](https://killercoda.com/)
- [iximiuz Labs](https://labs.iximiuz.com/playgrounds?category=kubernetes&filter=all)
- [KodeKloud](https://kodekloud.com/public-playgrounds)

また、ローカル環境でも以下のようなツールを使用して実行できます。

- [kind](https://github.com/kubernetes-sigs/kind)
- [minikube](https://github.com/kubernetes/minikube)

## 前提条件

- `kubectl` コマンドがインストールされている
- Kubernetes クラスタへの管理者権限
- 基本的な Kubernetes の知識（Pod、Service、Deployment 等）

## ルールと注意事項

- フラグは `CTF{...}` の形式で記載されています
- 与えられた権限の範囲で、フラグの文字列を取得してください
- コードを見ながら解くこともできますが、問題の難易度は下がります

## 実施方法

| Title | Level |
|:-----:|:---------:|
| Challenge 01 | ⭐️ |
| Challenge 02 | ⭐️ |
| Challenge 03 | ⭐️⭐️ |

### Challenge 01

```bash
chmod +x challenge01_setup.sh
./challenge01_setup.sh
```

<details><summary>クリーンアップ</summary>

```bash
kubectl delete ns ctf-1 --ignore-not-found=true
```

</details>

### Challenge 02

```bash
chmod +x challenge02_setup.sh
./challenge02_setup.sh
```

<details><summary>クリーンアップ</summary>

```bash
kubectl delete ns ctf-2 --ignore-not-found=true
```

</details>

### Challenge 03

```bash
chmod +x challenge03_setup.sh
./challenge03_setup.sh
```

<details><summary>クリーンアップ</summary>

```bash
kubectl delete ns ctf-3 --ignore-not-found=true
```

</details>

## Tips & Tricks

<details><summary>便利なコマンド一覧</summary>

```bash
# 自身の持っている権限を確認
kubectl auth can-i --list

# 特定リソースを一覧取得
# kubectl get [resourceType]
kubectl get po
kubectl get deploy
kubectl get events

# リソースのマニフェスト情報を取得
# kubectl get [resourceType] [resourceName] -o yaml
kubectl get po pod01 -o yaml

# 主要なリソースを一覧取得
kubectl get all

# リソースの詳細やイベント情報を取得
# kubectl describe [resourceType] [resourceName]
kubectl describe po pod01

# Pod に入って操作
# kubectl exec -it [podName] -- sh
kubectl exec -it pod01 -- sh

# ログの確認
# kubectl logs [podName]
kubectl logs pod01
```

</details>

---

## License

Apache License Version 2.0
