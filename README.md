# RecApp

Macのディスプレイ映像とシステム音声をMP4へ録画したり、システム音声だけをM4AまたはWAVへ録音したりできるネイティブmacOSアプリです。

## 機能

- 画面とシステム音声をMP4へ録画
- システム音声のみをM4AまたはWAVへ録音
- メニューバーから録画開始・停止
- 常に前面に表示しながら、録画映像からRecApp自身を除外

## 起動

```sh
swift run RecApp
```

初回の録画時は、macOSから求められる「画面収録とシステムオーディオ」の権限を許可してください。許可後にアプリの再起動が必要な場合があります。

Xcodeで開く場合は `Package.swift` を開き、`RecApp` スキームを実行します。

## ダブルクリックできるアプリを作る

```sh
./scripts/build-app.sh
```

生成された `dist/RecApp.app` をFinderから開けます。

## 署名・公証済みインストーラ

Developer ID証明書とnotarytoolのKeychainプロファイルがある環境で実行します。

```sh
NOTARY_PROFILE=Aureline-notary ./scripts/build-installer.sh
```

`dist/RecApp-1.0-macOS.pkg` が生成され、Appleへの公証、staple、Gatekeeper検証まで自動実行されます。

## 動作環境

- macOS 14以降
- Xcode 16以降
