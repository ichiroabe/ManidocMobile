# manidocMobile

デスクトップ版 [manidoc](https://fusion.upper.jp/manidoc.html) のワークスペースを、Android から閲覧・編集するアプリです。

ノードで構成された知識ベースを外出先で読み返し、その場で追記できます。追記した内容はデスクトップ側にそのまま反映されます。

## ダウンロード

[GitHub Releases](https://github.com/ichiroabe/ManidocMobile/releases/latest) から APK を取得してください。Google Play では配布していないため、インストール時に「提供元不明のアプリ」の許可が必要です。

## 仕組み

**Google アカウントでのログインは不要です。**

起動後にワークスペースのフォルダを1回選ぶと、以降アプリはそのフォルダだけを読み書きします。フォルダの選択には Android 標準の仕組み（Storage Access Framework）を使っており、アクセス権を発行しているのは端末の OS です。Google のサーバーに認証を求めることはありません。

選べる場所は、

- **Google ドライブ**のフォルダ（デスクトップ版と同期する場合はこちら）
- 端末内のフォルダや SD カード

のどちらでも構いません。デスクトップ版が Google Drive デスクトップ経由で書き込んでいるフォルダをそのまま選べば、同じワークスペースを共有できます。

フォルダ構成はデスクトップ版と共通です。

```
ワークスペース/
  {UUID}.json      ← プロジェクト本体
  {UUID}/
    images/
    output/
  _android/        ← このアプリが書き込む場所
```

AI 機能（Gemini）を使う場合は、設定画面でご自身の API キーを入力してください。キーは端末内にのみ保存され、外部に送信されるのは Gemini API への問い合わせのときだけです。

## 自分でビルドする

```bash
git clone https://github.com/ichiroabe/ManidocMobile.git
cd ManidocMobile
flutter pub get
flutter build apk --release
```

必要なもの:

- Flutter 3.44.6 以降（開発は 3.44.6、Dart 3.12 系）
- Android SDK と JDK 17

署名について: `android/key.properties`（gitignore 済み）に署名情報を書くと、そのキーストアで署名されます。書かなければ debug キーで署名されるので、手元で動かすだけなら設定は不要です。

```properties
storeFile=/path/to/your.jks
storePassword=***
keyAlias=***
keyPassword=***
```

CI（GitHub Actions）では同じ値を Secret から環境変数（`ANDROID_KEYSTORE_PATH` ほか）で渡しています。

## リリース

リリースの起点は `pubspec.yaml` の `version` です。master に push すると、その version に対応する `v` タグが未作成なら CI が自動でタグを切って Releases に APK を公開します。配布したい変更があるときは version を上げてください。

## 使用しているもの

- [Tiptap](https://tiptap.dev/) / [ProseMirror](https://prosemirror.net/) — エディタ（MIT License）。`assets/tiptap/` に同梱

## ライセンス

[GNU General Public License v3.0](LICENSE)
