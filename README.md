# Forcefield WiFi Motion Detector

PowerShell measures latency jitter and sends a score over WebSocket to Node.js.  
Node.js broadcasts to the browser, which renders geometric animation and voice alerts.

## GitHub Release Package

This folder is prepared as a standalone GitHub-ready project.

Quick publish:

```bash
git init
git add .
git commit -m "Initial release: forcefield detector"
```

---

## 日本語 (JA)

### 研究成果サマリー

今回の検証で、以下の条件を固定すると再現性高く動作することを確認しました。

1. WebSocket 接続先を `ws://127.0.0.1:8080` に固定する  
2. センサーターゲットを `127.0.0.1` に固定する（環境差の大きい WiFi ルータ依存を排除）  
3. 起動順序を自動化する（Server -> Browser -> Sensor）  
4. PowerShell は `ExecutionPolicy Bypass` で実行する  

これにより、`Latency/Score` が `--` のまま止まる問題と、接続先解決の環境差を大幅に低減できます。

### 再現可能な実験プロトコル

#### 最短（推奨）

```bat
start-forcefield.bat
```

このバッチは以下を自動実行します。

- 依存確認 (`npm install` 必要時のみ)
- 8080 のサーバー起動（使用中なら既存を利用）
- 8080 到達確認
- ブラウザ起動
- センサー起動 (`-Url ws://127.0.0.1:8080 -Target 127.0.0.1`)

#### 手動実行

```bash
npm install
node server.js
```

ブラウザで `http://localhost:8080` を開き、PowerShell で:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\powershell-sensor.ps1 -Url ws://127.0.0.1:8080 -Target 127.0.0.1
```

### 成功判定（検証指標）

- サーバーに `Client connected` が2回以上出る（Browser + Sensor）
- サーバーに `Score ... latency ... micro ...` が連続で出る
- 画面左上の `Latency` と `Score` が `--` から数値へ遷移する
- `Status` が `CALM/UNSTABLE/INTRUSION` に遷移する

### 一般環境への適用ガイド

- 実ネットワーク揺らぎで測る場合のみ `-Target` をゲートウェイIPに変更
- `EADDRINUSE` の場合は既存8080プロセスを利用するか停止して再起動
- `リモートサーバーに接続できません` は起動順序か接続先不一致が主因

---

## English (EN)

### Research Outcome Summary

This run identified a reproducible baseline that works across general Windows setups:

1. Fix WebSocket endpoint to `ws://127.0.0.1:8080`
2. Fix sensor target to `127.0.0.1` for baseline reproducibility
3. Enforce startup order (Server -> Browser -> Sensor)
4. Run PowerShell with `ExecutionPolicy Bypass`

This significantly reduces environment-specific failures where overlay values stay at `--`.

### Reproducible Protocol

#### One-click (recommended)

```bat
start-forcefield.bat
```

The batch script handles:

- dependency check/install (`npm install` if missing)
- server startup on port 8080 (or reuse if already active)
- port reachability wait
- browser launch
- sensor launch (`-Url ws://127.0.0.1:8080 -Target 127.0.0.1`)

#### Manual run

```bash
npm install
node server.js
```

Open `http://localhost:8080`, then in PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\powershell-sensor.ps1 -Url ws://127.0.0.1:8080 -Target 127.0.0.1
```

### Success Criteria

- Server shows at least two `Client connected` logs (browser + sensor)
- Server continuously logs `Score ... latency ... micro ...`
- Browser overlay values switch from `--` to numbers
- State transitions occur (`CALM`, `UNSTABLE`, `INTRUSION`)

### Portability Notes

- For real WiFi jitter experiments, replace `-Target 127.0.0.1` with your gateway/router IP
- If `EADDRINUSE` appears, reuse the current server or stop the existing process
- `Unable to connect to endpoint` typically means wrong startup order or wrong endpoint

---

## Files

- `server.js` - HTTP + WebSocket server on port 8080
- `index.html` - Canvas visualization and voice alert UI
- `powershell-sensor.ps1` - latency sensor and WebSocket sender
- `start-forcefield.bat` - one-click startup for Windows
- `package.json` - minimal Node.js dependency setup
