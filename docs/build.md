# ビルド手順

ビルドは、ローカルと CI(GitHub Actions)で同じスクリプトを使います。

## 構成

| 部分 | 内容 | ビルド |
|------|------|--------|
| `core/` | エミュレーションコア(C++)と imgui のラッパー | CMake(静的ライブラリ) |
| `app/` | アプリケーション層 | Odin |
| `gui/` | imgui 連携の C コード | `core/` の CMake がビルド |
| `.tools/` | Sokol の Odin バインディング、dcimgui、(必要なら)Odin | `scripts/setup.sh` が取得 |

## 必要なもの

共通: Git、CMake、C/C++ コンパイラ、[mise](https://mise.jdx.dev)(Odin の導入に使います。使わない場合は、`mise.toml` に書かれたバージョンの Odin を自分で用意してください)

### Linux(Ubuntu 22.04 以上)

```bash
sudo apt-get install build-essential cmake git libgl-dev libasound2-dev libx11-dev libxi-dev libxcursor-dev
```

Odin のビルドには LLVM 17 以上が必要です。Ubuntu 22.04 の標準パッケージは古いため、[apt.llvm.org](https://apt.llvm.org) から入れてください。

### macOS(14 以上)

```bash
xcode-select --install
brew install cmake
```

### Windows(11 以上)

- Visual Studio 2022 以降(「C++ によるデスクトップ開発」)と CMake、Ninja
- Git for Windows(Git Bash を使います)
- ビルドは、MSVC の環境(vcvars)を有効にした Git Bash から実行します。

## 手順

```bash
git clone https://github.com/bubio/BubiZ-2500.git
cd BubiZ-2500
scripts/setup.sh          # 開発ツールの取得とライブラリのビルド(初回のみ)
scripts/build.sh release  # ビルド(debug も指定可)
```

成功すると、`build/bin/BubiZ-2500`(Windows は `BubiZ-2500.exe`)ができます。

### `scripts/setup.sh` がすること

1. mise で、`mise.toml` に固定したバージョンの Odin を導入します。
2. CMake が無ければ導入します。
3. [sokol-odin](https://github.com/floooh/sokol-odin) を固定のリビジョンで取得し、Sokol の C ライブラリをビルドします。
4. [dcimgui](https://github.com/floooh/dcimgui) を固定のリビジョンで取得し、`sokol_imgui` のライブラリをビルドします。

### Odin を自分でビルドする場合

配布されている Odin のバイナリがお使いの OS で動かない場合は、固定バージョンをソースからビルドできます(LLVM 17 以上が必要)。

```bash
# macOS の例
brew install llvm@18
scripts/build-odin.sh
```

ビルドした Odin(`.tools/odin/odin`)は、`scripts/build.sh` が自動的に使います。別の Odin を使う場合は、環境変数 `ODIN` でパスを指定します。

### 環境変数

| 変数 | 説明 |
|------|------|
| `ODIN` | Odin コンパイラのパス |
| `SOKOL_DIR` | sokol-odin の `sokol` ディレクトリ(既定: `.tools/sokol-odin/sokol`) |
| `BUILD_DIR` | 出力先(既定: `build`) |

## テスト

```bash
# アプリ層の単体テスト
odin test app -collection:sokol=.tools/sokol-odin/sokol -extra-linker-flags:"-Lbuild/core" -out:build/apptest

# ウィンドウなしの動作確認(60フレーム実行)
build/bin/BubiZ-2500 -headless 60 -nosound

# コアの煙テスト
build/core/bubiz_smoke "$TMPDIR/"
```

BIOS ROM が無くても、ここまでの確認は実行できます。

## 配布物の作成

`scripts/build.sh release` のあとに、各 OS のスクリプトを実行します。成果物は `dist/` にできます。

| OS | コマンド | 成果物 |
|----|----------|--------|
| Linux | `scripts/package-linux.sh [deb\|rpm\|appimage\|all]` | `.deb` / `.rpm` / `.AppImage`(rpm の作成には `rpmbuild` が必要) |
| macOS | `scripts/package-macos.sh` | `.dmg`(アドホック署名) |
| Windows | `scripts/package-windows.sh` | `.zip` |

- ファイル名は `BubiZ-2500-<バージョン>-<プラットフォーム>-<アーキテクチャ>` の形式です(`scripts/artifact-name.sh`)。
- ビルド番号は環境変数 `BUILD_NUMBER`(既定: 1)で指定します。

## バージョン

バージョンは `app/version.odin` の `VERSION` で管理します(セマンティックバージョニング)。

## CI とリリース

| ワークフロー | 内容 |
|--------------|------|
| `ci-linux.yml` | Ubuntu 22.04(amd64 / arm64)でビルド、テスト、配布物の作成 |
| `ci-macos.yml` | macOS(Apple Silicon / Intel)でビルド、テスト、配布物の作成 |
| `ci-windows.yml` | Windows でビルド、テスト、配布物の作成 |
| `release.yml` | `v1.0.0` のようなタグを push すると、各 OS の配布物を作り、GitHub のリリースに公開 |

- CI は、`core/`、`gui/`、`app/`、`scripts/`、`packaging/`、`mise.toml`、各ワークフロー自身の変更でだけ動きます。
- リリースのタグ名は、`app/version.odin` の `VERSION` と一致している必要があります。`-` を含むタグ(例: `v1.1.0-rc.1`)は、プレリリースとして公開します。
- リリースには、各ファイルが個別に添付され、`SHA256SUMS` も付きます。
