# BubiZ-2500

MZ-2500エミュレーターの開発です。

[Common Source Code Project](https://github.com/bubio/common_source_code_project)のEmuZ-2500のコアを使用します。
アプリケーション層は[Odin言語](Odin言語)で書き、マルチメディア層は[Sokol](https://github.com/floooh/sokol)の[Odinバインディング](https://github.com/floooh/sokol-odin)


## この文書について

- この文書は青写真（雑な要求仕様）としての入力文書になるため内容を編集してはいけません。
- 開発が進み事情が変化した場合、必ずしもこの文書の内容に従う必要はない。


## 対応プラットフォーム


#### サポートするOSバージョンと優先順位

1. Linux: Ubuntu 22.04以上 / amd64 / arm64
2. macOS: macOS 13以上 / Intel / Apple Silicon
3. Windows: Windows 11以上 / x86_64

Linuxでの開発が完了したのちに、他プラットフォームへ広げていきます。

#### 頒布方法と形式

GitHubのリリースで頒布します。

1. Linux: deb/rpm/appimage
2. macOS: dmg
3. Windows: zip


## 技術スタック

- エミュレーションコアはC言語
- アプリケーション層はOdin言語（[mise](https://github.com/jdx/mise)経由でインストールを想定）
- マルチメディア層はSokol。GUIはSokol imgui。

## 機能要件

- オリジナルが提供する機能をできる限り実装する。
- 設定ファイルなどの置き場所はOSの習慣に従うこと。
- まずはCLIアプリ、その後GUIアプリにします。
- CLIのコマンドフォーマットは[QUASI88](https://github.com/bubio/QUASI88/blob/main/doc/manual.txt)に準じます（QUASI88はPC88エミュレーターなので同じになるわけではない）。


## 非機能要件

- Git/GitHubでソースコードを管理する。
- GitHub Actionsを使用したCI/CDワークフローを実施する。
- GitHub Actionsはそのアクションに不要なファイルの変更で実行されないようにすること。
- ビルドはローカルとCIで同等となるようにする。ビルド手順が複雑な場合はスクリプトを用意する。
- mainブランチへ直接コミット、プッシュする。
- ソースコードのコメントは日本語で簡潔に記載すること。
- 技術ドキュメントは、docs/dev/フォルダの下に作成するものとし、Gitのサブモジュールとする。docs/dev/のリモートは、git@github.com:bubio/dev-docs.git に本プロジェクト用のブランチを作成して管理する（開発ドキュメントの隠蔽が目的）。



## 禁止事項

- 指示があるまではコミット、プッシュしてはならない。
- ユーザー名を暴露しないようにする。パスは~ /$HOMEなどを用いる。
- README.mdに開発関連の内容を書いてはいけません。



## バージョン番号

- セマンティックバージョニングにします。

- ビルド番号がある場合は1からの連番とします。


## 注意事項

- BIOS ROMファイル、市販ゲームの確認が必要になったら相談すること
