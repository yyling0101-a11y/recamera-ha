# reCamera for Home Assistant

[![HACS Action](https://github.com/yyling0101-a11y/recamera-ha/actions/workflows/hacs.yml/badge.svg)](https://github.com/yyling0101-a11y/recamera-ha/actions/workflows/hacs.yml)
[![Hassfest](https://github.com/yyling0101-a11y/recamera-ha/actions/workflows/hassfest.yml/badge.svg)](https://github.com/yyling0101-a11y/recamera-ha/actions/workflows/hassfest.yml)
[![HACS](https://img.shields.io/badge/HACS-Custom-41BDF5.svg)](https://github.com/hacs/integration)

把 Seeed **reCamera**（SG2002）的**选区运动检测**搬进 Home Assistant：在 HA 侧边栏看实时画面、直接在画面上画检测区域、运动时收到通知并自动保留当时那一帧。

Brings the Seeed **reCamera** (SG2002) **region motion detection** into Home Assistant: live view in the sidebar, draw detection regions directly on the video, get notified on motion with the exact frame kept for you.

- [Wiki: reCamera Motion Detection](https://wiki.seeedstudio.com/recamera_motion_detection/)
- 设备端程序 / device program: [`recamera_motion_detection`](https://github.com/yyling0101-a11y/recamera_motion_detection)

---

## 它解决什么问题 / Why this exists

原厂的选区运动检测只能在 **Windows 客户端**里画区域、看告警，告警不出设备，也没法接入任何自动化。

The stock region motion detection can only be driven from a **Windows client**: regions are drawn there, alerts stay on the device, and nothing can be automated.

本仓库把它拆成两半：

This repository splits that into two halves:

| 组成 / Part | 位置 / Lives on | 作用 / Does |
| --- | --- | --- |
| 改造后的 `motion_detection` | reCamera 设备上 / the camera | 视频管线 + ROI 检测 + RTSP 推流 + JPEG 抓拍 + HTTP API + 主动向 HA 推送告警 / video pipeline, ROI detection, RTSP, JPEG snapshots, HTTP API, webhook push to HA |
| `recamera` 自定义集成 | Home Assistant | 侧边栏面板、区域编辑器、摄像机/传感器/事件实体、通知、抓拍归档 / sidebar panel, region editor, entities, notifications, snapshot archive |

告警最终会落到三个地方，用户任选：**HA 通知中心**、**`recamera_motion` 事件总线**（自动化/蓝图）、**实体状态变化**（`binary_sensor`、`event`、`image`）。手机推送由用户自己用蓝图或自动化决定发给谁。

Alerts land in three places, pick any: the **HA notification centre**, the **`recamera_motion` event bus** (automations/blueprints), and **entity state changes**. Phone push is yours to wire up via the bundled blueprints.

## 架构 / How it works

```
┌──────────────── reCamera (SG2002) ────────────────┐
│  motion_detection  (/opt/recamera-motion)         │
│                                                   │
│   VI/VPSS ─┬─► VENC H.264 ──► RTSP  :8554/live0 ──┼──┐
│            └─► VENC JPEG ──► 环形缓冲(16帧)        │  │
│                     │                             │  │
│   motion_detector ◄─┘  (320x180 灰度差分 + ROI)    │  │
│        │  motion_start / motion_end               │  │
│        ├──────────────► HTTP API :8080            │  │
│        └──────────────► notifier ── webhook ──────┼──┤  POST /api/webhook/recamera-<entry>
└───────────────────────────────────────────────────┘  │  (含 base64 抓拍图)
                                                        │
┌────────────────────── Home Assistant ─────────────┐  │
│  recamera integration                             │◄─┘
│    coordinator ──► 事件总线 recamera_motion        │
│                 ──► persistent_notification       │
│                 ──► www/recamera/<host>_<port>/   │──► /local/recamera/...jpg
│                 ──► camera / binary_sensor /      │
│                     event / image / sensor /      │
│                     switch 实体                    │
│    sidebar panel ──► camera_proxy_stream (MJPEG)  │◄─── RTSP + JPEG 通道
│                 ──► WebSocket recamera/*          │
└───────────────────────────────────────────────────┘
```

设备**主动推送**（webhook）时延迟约几十毫秒；如果 HA 没有可用地址，集成会自动退化为 **0.4 s 轮询**，功能不丢，只是稍慢。

Push mode (webhook) delivers in tens of milliseconds. When HA has no reachable URL the integration falls back to **0.4 s polling** — same features, slightly slower.

## 功能 / Features

- **侧边栏面板 `reCamera`**：设备卡片 → 实时画面 → 区域编辑器。
- **在画面上直接画多边形**：左键加点、右键撤销、支持多个「检测区域」和「白名单（忽略）区域」。
- **实时画面**：走 HA 的 `camera_proxy_stream`（MJPEG），不需要暴露设备地址，预览帧率可调（1–25 fps）。
- **灵敏度可调**：像素阈值、最小运动像素、最小连通块、触发帧数、恢复帧数、预热帧数、背景/前景更新速度。
- **告警保留当前帧**：自动存到 `config/www/recamera/<host>_<port>/`，环形清理（默认保留 100 张），可在通知里直接看到。
- **通知中心**：每次告警一条带图通知，跟随 HA 语言自动中英文。
- **事件总线 + 蓝图**：`recamera_motion` 事件带上 `image_url`、`bbox`、`motion_pixels` 等，配套两个蓝图（手机推送 / 任意联动）。
- **完整实体**：`camera`（含 RTSP，可用于录制）、`binary_sensor`、`event`、`image`、`sensor` ×3、`switch`。
- **多设备**：一个 HA 可以加多台 reCamera。

## 前置条件 / Requirements

- Home Assistant **2025.1** 或更新（已在 **2026.9** 上验证），管理员账号（面板 `require_admin`）。
- 一台 Seeed **reCamera**（SG2002，riscv64），与 HA 同一局域网，能 SSH 上去（默认 `root` / `123123`）。
- 交叉编译设备端程序需要：
  - `sscma-example-sg200x` 检出（提供 `cmake/` 与 `components/`）
  - reCamera-OS SDK 产物目录（提供 `cvi_mpi`、`cvi_rtsp`）
  - `riscv64-unknown-linux-musl` 工具链

- Home Assistant **2025.1** or newer (verified on **2026.9**), admin account.
- A Seeed **reCamera** (SG2002, riscv64) on the same LAN, reachable over SSH (`root` / `123123` by default).
- To cross-compile the device program you need the `sscma-example-sg200x` checkout, a reCamera-OS SDK output tree, and the `riscv64-unknown-linux-musl` toolchain.

> ⚠️ 摄像头是**单占用**设备：运动检测程序启动时会先停掉原厂 `recamera-onvif` 和 `sscma-node`。要恢复原厂行为见 [恢复出厂](#恢复出厂--restore-stock-firmware)。
>
> The camera pipeline has a **single owner**: the motion program stops the stock `recamera-onvif` and `sscma-node` services at boot. See [Restore stock firmware](#恢复出厂--restore-stock-firmware).

---

## 第一步：刷设备端程序 / Step 1: flash the device program

设备端代码在 [`recamera_motion_detection`](https://github.com/yyling0101-a11y/recamera_motion_detection)。克隆后：

The device side lives in [`recamera_motion_detection`](https://github.com/yyling0101-a11y/recamera_motion_detection). After cloning:

```bash
# 按需覆盖这三个路径 / override these three paths if yours differ
export SSCMA_EXAMPLE_PATH=$HOME/work/sscma-example-sg200x
export SG200X_SDK_PATH=$HOME/work/sdk_dl/sg2002_recamera_emmc
export HOST_TOOLS_PATH=$HOME/work/host-tools

ssh-copy-id root@192.168.42.1        # 免密，deploy.sh 依赖它 / deploy.sh needs key auth
./scripts/build.sh                   # 交叉编译 → build/motion_detection
./scripts/deploy.sh                  # 装到 /opt/recamera-motion 并注册开机服务
./scripts/deploy.sh --host root@192.168.4.5   # 换地址 / other address
./scripts/deploy.sh --uninstall      # 卸载并恢复原厂 onvif 服务 / uninstall
```

部署完成后自检 / sanity-check afterwards:

```bash
curl http://192.168.42.1:8080/api/health      # 快照通道 + RTSP 地址 / snapshot channel + RTSP URL
curl http://192.168.42.1:8080/api/status      # 实时运动状态 / live motion state
ffprobe rtsp://192.168.42.1:8554/live0        # H.264 1920x1080@30
```

> `deploy.sh` 会一并推送**普通版 `libcvi_rtsp.so`**。固件自带的 `/usr/local/lib/recamera-onvif/libcvi_rtsp.so` 是厂商改版，对 `DESCRIBE` 一律回 401 Digest 认证，HA 拉不到流；启动脚本用 `LD_LIBRARY_PATH` 保证我们这份优先。
>
> `deploy.sh` also installs the **plain `libcvi_rtsp.so`**. The firmware copy under `/usr/local/lib/recamera-onvif/` is a vendor variant that always answers `DESCRIBE` with 401 Digest auth, which HA cannot handle; the launcher puts ours first via `LD_LIBRARY_PATH`.

## 第二步：安装集成 / Step 2: install the integration

### 方式一：HACS 自定义仓库（推荐）

1. HACS → 右上角 **⋮** → **Custom repositories**（自定义仓库）。
2. 地址填 `https://github.com/yyling0101-a11y/recamera-ha`，**Category 选 Integration**，保存。
3. 搜索 **reCamera** → **Download** → 重启 Home Assistant。

1. HACS → **⋮** → **Custom repositories**.
2. Add `https://github.com/yyling0101-a11y/recamera-ha`, **Category: Integration**, save.
3. Search **reCamera** → **Download** → restart Home Assistant.

### 方式二：手动 / Manual

```bash
cd custom_components/            # 你的 HA 配置目录 / your HA config dir
git clone https://github.com/yyling0101-a11y/recamera-ha /tmp/recamera-ha
cp -a /tmp/recamera-ha/custom_components/recamera ./recamera
# 重启 HA / restart HA
```

## 第三步：配置 / Step 3: configure

1. **设置 → 设备与服务 → 添加集成 → reCamera**，填设备 IP（默认 `192.168.42.1`）。
   **Settings → Devices & Services → Add integration → reCamera**, enter the camera IP.
2. **设置 → 系统 → 网络**，把 **本地访问地址 / Internal URL** 填成 HA 实际地址（例如 `http://192.168.3.205:8123`）。
   设备靠这个地址回推告警。**不填也能用**，会自动退化为轮询。
   Set **Settings → System → Network → Internal URL** so the camera can push alerts back. Skipping it still works — the integration falls back to polling.
3. 侧边栏出现 **reCamera**，点进去就是设备卡片 → **选区运动检测**。

## 使用面板 / Using the panel

1. 打开侧边栏 **reCamera**，点设备卡片上的 **打开选区编辑**。
2. 实时画面上**左键**依次点顶点，**右键**撤销；至少 3 个点后点 **完成当前多边形**。
3. 区域类型可选 **检测区域**（触发告警）或 **白名单（忽略）**（区域内不触发），并给区域起名。
4. 点 **保存选区** 写入设备（掉电保留在 `/userdata/motion_roi.json`）。
5. 需要重新学习背景（例如挪动了机位）时点 **重建背景**。
6. 下方 **灵敏度** 滑块实时改阈值；**通知与推送** 里可开关 HA 通知、设备主动推送，并 **发送测试告警** 验证链路。

1. Open **reCamera** in the sidebar, then **Open region editor** on the device card.
2. **Left-click** to add vertices on the live image, **right-click** to undo; finish with **Finish polygon** once you have 3+ points.
3. Choose **Detection zone** (alerts) or **Whitelist / ignore** (never alerts) and name it.
4. **Save regions** writes to the camera (persisted in `/userdata/motion_roi.json`).
5. **Rebuild background** after moving the camera.
6. The **Sensitivity** sliders apply live; **Notifications** toggles the HA notification and device push, and **Send test alert** verifies the whole chain.

## 告警去了哪里 / Where alerts go

| 出口 / Sink | 怎么用 / How |
| --- | --- |
| HA 通知中心 / notification centre | 自动，带抓拍图；可在面板或集成选项里关掉 / automatic, with snapshot; can be turned off |
| `recamera_motion` 事件 / event bus | 自动化里用「触发器 → 事件」，或用仓库蓝图 / trigger type *Event* in an automation, or use a blueprint |
| `binary_sensor.recamera_motion` | 状态触发器，最简单的联动方式 / plain state trigger, the simplest wiring |
| `event.recamera_motion_event` | 带属性的事件实体，进日志、也能在 App 里看 / event entity, shows in the logbook |
| `image.recamera_last_motion` | 最近一次告警帧，可直接放进仪表盘 / last alert frame, dashboard-ready |
| `camera.recamera` | RTSP 实体，可接 HA 录制 / RTSP entity, usable with HA recording |

### 蓝图 / Blueprints

`blueprints/automation/recamera/` 下有两个蓝图，导入方式：**设置 → 自动化 → 新建 → 从蓝图创建**，或直接打开链接（把仓库地址换成你的 fork）：

Two blueprints ship in `blueprints/automation/recamera/`. Import them via **Settings → Automations → Create automation → Use blueprint**, or open the import link (swap in your fork's URL):

- **`motion_snapshot_notify.yaml`** — 运动时通过任意 notify 服务推送（手机 App、Telegram、Pushover…），附抓拍图，点通知直接跳到面板，带静默期防刷屏。
  Pushes through any notify service with the snapshot attached; tapping opens the panel; has a quiet period.
- **`motion_actions.yaml`** — 运动时/恢复安静时执行任意动作（开灯、拉警报、播 TTS、调其它设备）。
  Runs any actions on motion start / motion end (lights, sirens, TTS, other devices).

```text
https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2Fyyling0101-a11y%2Frecamera-ha%2Fblob%2Fmain%2Fblueprints%2Fautomation%2Frecamera%2Fmotion_snapshot_notify.yaml
```

自己写自动化时，事件负载长这样 / the event payload looks like this:

```yaml
trigger:
  - platform: event
    event_type: recamera_motion
condition:
  - condition: template
    value_template: "{{ trigger.event.data.event == 'motion_start' }}"
action:
  - service: notify.mobile_app_pixel
    data:
      title: "{{ trigger.event.data.device }} 有动静"
      message: "{{ trigger.event.data.motion_pixels }} 个运动像素"
      data:
        image: "{{ trigger.event.data.image_url }}"   # /local/recamera/...jpg
        attachment: { content-type: jpeg }
        clickUrl: /recamera
```

字段 / fields：`device`、`device_id`、`ha_device_id`、`entry_id`、`host`、`event`（`motion_start` / `motion_end`）、`event_id`、`motion`、`captured_at`、`timestamp`、`motion_pixels`、`largest_blob_pixels`、`motion_ratio`、`bbox`（归一化 `[x, y, w, h]`）、`analysis_width`、`analysis_height`、`image_url`。

> 手机 App 要能看到 `/local/...` 图片，需要在 **设置 → 系统 → 网络** 配好内部/外部地址。
> The companion app needs **Settings → System → Network** URLs configured to resolve `/local/...` images.

## 实体 / Entities

| 实体 / Entity | 说明 / Purpose |
| --- | --- |
| `camera.*` | RTSP 直播 + JPEG 抓拍；面板预览走它 / RTSP stream + JPEG stills |
| `binary_sensor.*_motion` | 选区内是否有运动 / motion inside the zones |
| `binary_sensor.*_no_detection_zone` | 一个区域都没画时变 on（问题提示） / on when no region is drawn |
| `event.*_motion_event` | 每次告警，属性带 `image_url` / one per alert, carries `image_url` |
| `image.*_last_motion` | 最近一次告警帧 / last alert frame |
| `sensor.*_last_motion` | 最近告警时间戳 / last alert timestamp |
| `sensor.*_motion_pixels` | 实时运动像素（诊断） / live motion pixels (diagnostic) |
| `sensor.*_zones` | 区域数量（诊断） / region count (diagnostic) |
| `switch.*_motion_detection` | 暂停/恢复检测，保留已画区域 / pause detection, keeps regions |

## 服务 / Services

```yaml
service: recamera.reset_background     # 重建背景模型 / rebuild the background model
data: { device_id: <HA device id> }

service: recamera.test_push            # 让设备回推一条测试告警 / make the camera push a test alert
data: { device_id: <HA device id> }
```

## API 参考 / API reference

### 设备 HTTP API（`:8080`）/ device HTTP API

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/health` | 快照通道与 RTSP 地址 / snapshot channel + RTSP URL |
| GET | `/api/version` | 程序版本 / program version |
| GET | `/api/status` | 实时状态（运动、像素、bbox、预热…） / live status |
| GET/POST | `/api/config` | 读取/写入区域与灵敏度 / read-write regions and sensitivity |
| POST | `/api/background/reset` | 重建背景 / rebuild background |
| GET | `/api/snapshot.jpg` | 当前帧，`?event_id=N` 或 `?at=MS` 取历史帧 / current or historical frame |
| GET | `/api/events` | 事件列表，`?after_id=&limit=` / event list |
| GET | `/api/frames` | 已缓冲帧的序号 / buffered frame ids |
| GET/POST | `/api/notify` | 读取/写入推送配置（HA 会自动下发） / read-write push config |
| POST | `/api/notify/test` | 立即推一条测试事件 / push a test event now |

区域坐标一律是 **归一化 0–1**，与分辨率无关。
Region coordinates are **normalised 0–1**, resolution independent.

设备推送的 webhook 负载 / webhook payload pushed by the camera:

```json
{
  "source": "recamera_motion_detection",
  "schema": 2,
  "event": "motion_start",
  "event_id": 12,
  "device_ip": "192.168.42.1",
  "snapshot_url": "http://192.168.42.1:8080/api/snapshot.jpg?event_id=12",
  "unix_ms": 1791796312140,
  "capture_unix_ms": 1791796312080,
  "frame_id": "20269",
  "motion_pixels": 4297,
  "largest_blob_pixels": 3344,
  "motion_ratio": 0.1166,
  "analysis_width": 320,
  "analysis_height": 180,
  "bbox": [0.606, 0.439, 0.294, 0.461],
  "image": { "encoding": "base64", "content_type": "image/jpeg", "width": 1280,
             "height": 720, "capture_unix_ms": 1791796312080, "bytes": 42897,
             "data": "<base64>" }
}
```

### HA WebSocket API（面板在用）/ HA WebSocket API (used by the panel)

`recamera/devices`、`recamera/state`、`recamera/refresh`、`recamera/save_config`、`recamera/set_enabled`、`recamera/reset_background`、`recamera/notify`、`recamera/test_push`、`recamera/snapshot`、`recamera/set_options`。

## 恢复出厂 / Restore stock firmware

```bash
./scripts/deploy.sh --uninstall
```

会停掉运动检测服务、删除 `/opt/recamera-motion` 与 `/etc/init.d/S96recamera-motion`，并重新启动原厂 `recamera-onvif`。
Stops the service, removes `/opt/recamera-motion` and the init script, then restarts stock `recamera-onvif`.

## 常见问题 / Troubleshooting

**侧边栏没有 reCamera** — 集成是否已添加？面板是管理员可见的，普通账号看不到。改完代码要重启 HA，浏览器强刷（Ctrl+F5）。
*No sidebar entry* — is the integration added? The panel is admin-only. Restart HA after code changes and hard-refresh the browser.

**实时画面黑屏 / 转圈** — 先 `ffprobe rtsp://<ip>:8554/live0`。若返回 401，说明加载到了厂商版 `libcvi_rtsp.so`，重新跑一次 `./scripts/deploy.sh`（它会重装启动脚本里的 `LD_LIBRARY_PATH`）。
*Black live view* — run `ffprobe rtsp://<ip>:8554/live0`. A 401 means the vendor `libcvi_rtsp.so` won; re-run `./scripts/deploy.sh`.

**能轮询但没有主动推送** — 面板「通知与推送」里看 `push_url` 是否为空。为空就去 **设置 → 系统 → 网络** 填内部地址，然后在面板点一次 **发送测试告警**。
*Polling works but no push* — check `push_url` in the panel. If empty, set **Settings → System → Network → Internal URL**, then hit **Send test alert**.

**告警过于频繁 / 完全不告警** — 调 **像素阈值**、**最小运动像素**、**最小连通块**；画面有持续小幅变化（风扇、屏幕、树叶）时调高 **触发帧数**，并把易动区域画成 **白名单**。
*Too many / no alerts* — tune pixel threshold, min motion pixels and min blob; raise **trigger frames** for scenes with constant small motion (fans, screens, foliage) and whitelist the noisy parts.

**通知里没有图片** — 确认 `config/www/` 存在且 HA 进程可写；`/local/recamera/<host>_<port>/` 下应能看到 jpg。
*No image in the notification* — make sure `config/www/` exists and is writable; jpgs should appear under `/local/recamera/<host>_<port>/`.

**改完区域不生效** — 一定要点 **保存选区**；挪动过机位再点 **重建背景**，等预热结束（面板会显示「背景预热中」）。
*Region changes not applied* — press **Save regions**; after moving the camera press **Rebuild background** and wait for warm-up.

**设备端进程卡死** — 不要 `kill -9`，会把 VPSS 管线搞挂。用 `/etc/init.d/S96recamera-motion restart`，实在不行重启设备。
*Device process wedged* — never `kill -9`, it wedges the VPSS pipeline. Use `/etc/init.d/S96recamera-motion restart`, or reboot.

## 许可 / License

Apache-2.0，见 [LICENSE](LICENSE)。设备端程序沿用其上游仓库的 MIT 许可。
Apache-2.0, see [LICENSE](LICENSE). The device program keeps its upstream MIT licence.
