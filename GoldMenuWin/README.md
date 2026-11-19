# GoldMenu Windows 版

macOS 菜单栏金价小组件的 Windows 移植版。Windows 没有顶部菜单栏，改为**右下角系统托盘**：托盘图标显示金价和涨跌，单击弹出完整面板。

## 直接使用（绿色版，无需安装）

1. 解压 `dist/GoldMenu-Windows-x64.zip`
2. 进入 `win-unpacked` 文件夹，双击 `GoldMenu.exe`
3. 右下角托盘出现 `Au ¥xxx.x ↓x.xx%`，**单击图标**弹出面板；右键菜单可刷新、设开机自启、退出

> 首次运行若 Windows Defender/SmartScreen 提示"未知发布者"，选择"更多信息 → 仍要运行"即可（未购买代码签名证书，属正常现象）。
>
> 关闭面板 = 点面板右上角 ✕ 或点面板外空白处；程序仍在托盘后台运行。

## 面板内容

- 大号现价 + 涨跌额/涨跌幅（较昨收），涨红跌绿
- 日内分时走势图（优先上金所 Au99.99 人民币金价，失败自动回退伦敦金现货美元价，图上标注来源）
- 今开 / 最高 / 最低 / 昨收
- 阶段涨跌幅：今日 / 近一周 / 近一月 / 近一年（周月年为伦敦金现货历史基准）
- 更多报价：银行投资金条、品牌金饰金价（聚合站每日更新，仅供比价）
- 每 3 秒自动刷新；托盘右键"开机自启"可设为登录时启动

## 数据源

| 数据 | 来源 |
|---|---|
| 今日金价/开高低收 | 新浪上金所 Au99.99 |
| 分时图 | 上金所 quotations（被 WAF 拦时回退新浪 XAU） |
| 周/月/年涨跌 | 新浪伦敦金 XAU 历史日K |
| 银行金条/品牌金价 | v2.xxapi.cn 聚合接口 |

## 重新打包（在 Windows 或 Mac 上）

```bash
npm install          # 首次，下载 Electron
npm start            # 本地调试运行
npm run dist         # 打包 Windows exe（输出 dist/）
```

`npm run dist` 默认同时生成 NSIS 安装包和 portable 单文件 exe。若在 Mac 上打包，NSIS 步骤需下载 Wine（较慢）；可只保留 portable target 加快速度。国内网络建议设置镜像：

```bash
npm install --registry=https://registry.npmmirror.com
ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/ npm install
```

## 文件说明

- `main.js` — Electron 主进程：系统托盘、弹窗、定时刷新、托盘图标绘制
- `gold-service.js` — 四路数据抓取与解析（GBK 现货、JSON 聚合、jsonp 历史/分时）
- `index.html` / `renderer.js` — 弹出面板 UI 与分时图画布
- `icon.ico` — 应用图标
