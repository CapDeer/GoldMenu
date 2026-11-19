const { app, BrowserWindow, Tray, Menu, nativeImage, ipcMain, screen } = require('electron');
const path = require('path');
const { fetchAll } = require('./gold-service');

let tray = null;
let panel = null;
let refreshTimer = null;
let latest = null;
let fetching = false;

const REFRESH_MS = 3000;

function isDev() {
  return process.env.NODE_ENV === 'development' || !app.isPackaged;
}

// 托盘图标：复用一个常驻离屏窗口画 canvas（价格白字 + 涨跌着色），避免每 3 秒建销窗口
let iconWin = null;
let iconResolve = null;

let iconReady = false;

function createIconWindow() {
  iconReady = false;
  iconWin = new BrowserWindow({
    width: 340, height: 32, show: false,
    webPreferences: { offscreen: true, nodeIntegration: true, contextIsolation: false },
  });
  const html = `<!DOCTYPE html><html><body style="margin:0;background:transparent">
    <canvas id="c" width="340" height="32"></canvas>
    <script>
      const {ipcRenderer}=require('electron');
      ipcRenderer.on('draw-icon',(_,s)=>{
        const c=document.getElementById('c'), x=c.getContext('2d');
        x.clearRect(0,0,340,32); x.textBaseline='middle';
        const up=s&&s.isUp;
        const head=s?('Au ¥'+s.price.toFixed(2)+'  '):'Au ¥--';
        const tail=s?((up?'↑':'↓')+Math.abs(s.changePercent).toFixed(2)+'%'):'';
        x.font='bold 15px Arial';
        const headW=x.measureText(head).width;
        x.shadowColor='rgba(0,0,0,0.85)'; x.shadowBlur=3;
        x.fillStyle='#ffffff'; x.fillText(head,0,16);
        if(s){ x.fillStyle=up?'#ef4444':'#22c55e'; x.fillText(tail,headW,16); }
        ipcRenderer.send('icon-data',c.toDataURL('image/png'));
      });
      ipcRenderer.send('icon-ready');
    </script></body></html>`;
  iconWin.loadURL('data:text/html;charset=utf-8,' + encodeURIComponent(html));
}

ipcMain.on('icon-ready', () => { iconReady = true; });
ipcMain.on('icon-data', (_, dataUrl) => {
  if (iconResolve) { iconResolve(nativeImage.createFromDataURL(dataUrl)); iconResolve = null; }
});

function createTrayIcon(spot) {
  return new Promise((resolve) => {
    if (!iconWin || iconWin.isDestroyed()) createIconWindow();
    iconResolve = resolve;
    const send = () => iconWin.webContents.send('draw-icon', spot);
    if (iconReady) send();
    else iconWin.webContents.once('did-finish-load', send);
  });
}

async function updateTray() {
  if (!tray) return;
  try {
    const img = await createTrayIcon(latest && latest.spot);
    tray.setImage(img);
    const price = latest && latest.spot ? `¥${latest.spot.price.toFixed(2)}` : '--';
    tray.setToolTip(`今日金价 ${price}\n点击查看详情`);
  } catch (e) { /* 图标更新失败不影响数据刷新 */ }
}

function positionPanel() {
  if (!panel || !tray) return;
  const bounds = tray.getBounds();
  const pBounds = panel.getBounds();
  const display = screen.getDisplayMatching(bounds);
  let x = bounds.x + bounds.width / 2 - pBounds.width / 2;
  let y = bounds.y - pBounds.height - 4;
  if (y < display.workArea.y) y = bounds.y + bounds.height + 4;
  x = Math.max(display.workArea.x, Math.min(x, display.workArea.x + display.workArea.width - pBounds.width));
  panel.setPosition(Math.round(x), Math.round(y));
}

function createPanel() {
  panel = new BrowserWindow({
    width: 340,
    height: 700,
    show: false,
    frame: false,
    resizable: false,
    skipTaskbar: true,
    transparent: false,
    webPreferences: { nodeIntegration: true, contextIsolation: false },
  });
  panel.loadFile(path.join(__dirname, 'index.html'));
  panel.on('blur', () => { if (panel && !panel.webContents.isDevToolsOpened()) panel.hide(); });
  panel.webContents.on('did-finish-load', () => pushData());
}

function pushData() {
  if (panel && panel.webContents && latest) {
    panel.webContents.send('gold-data', latest);
  }
}

async function refresh(silent = true) {
  if (fetching) return;
  fetching = true;
  try {
    const snap = await fetchAll();
    // 单项失败回退旧值
    if (latest) {
      if (!snap.spot) snap.spot = latest.spot;
      if (!snap.priceGroups.length) snap.priceGroups = latest.priceGroups;
      if (!snap.periodChanges.length) snap.periodChanges = latest.periodChanges;
      if (!snap.intraday) snap.intraday = latest.intraday;
    }
    latest = snap;
    pushData();
    await updateTray();
  } finally {
    fetching = false;
  }
}

function buildMenu() {
  return Menu.buildFromTemplate([
    { label: '刷新金价', click: () => refresh() },
    { type: 'separator' },
    { label: '开机自启', type: 'checkbox', checked: app.getLoginItemSettings().openAtLogin,
      click: (item) => app.setLoginItemSettings({ openAtLogin: item.checked }) },
    { label: '显示面板', click: () => { createPanelIfNeeded(); panel.show(); positionPanel(); } },
    { type: 'separator' },
    { label: '退出', click: () => app.quit() },
  ]);
}

function createPanelIfNeeded() {
  if (!panel || panel.isDestroyed()) createPanel();
}

function createTray() {
  const empty = nativeImage.createEmpty();
  tray = new Tray(empty);
  tray.setContextMenu(buildMenu());
  tray.on('click', () => {
    createPanelIfNeeded();
    if (panel.isVisible()) panel.hide();
    else { panel.show(); positionPanel(); pushData(); }
  });
  updateTray();
}

app.whenReady().then(() => {
  app.dock && app.dock.hide && app.dock.hide();
  createTray();
  createPanelIfNeeded();
  refresh();
  refreshTimer = setInterval(() => refresh(true), REFRESH_MS);
});

app.on('window-all-closed', (e) => { e.preventDefault(); });
app.on('before-quit', () => { if (refreshTimer) clearInterval(refreshTimer); });

ipcMain.on('manual-refresh', () => refresh());
ipcMain.on('quit-app', () => app.quit());
ipcMain.on('hide-panel', () => { if (panel) panel.hide(); });
