const { ipcRenderer } = require('electron');

const content = document.getElementById('content');
document.getElementById('refreshBtn').onclick = () => ipcRenderer.send('manual-refresh');
document.getElementById('closeBtn').onclick = () => ipcRenderer.send('hide-panel');

const fmt = (n, d = 2) => (n || 0).toFixed(d);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function drawChart(intra, color) {
  const c = document.getElementById('chart');
  if (!c || !intra || !intra.prices || intra.prices.length < 2) return;
  const dpr = window.devicePixelRatio || 1;
  const w = c.clientWidth, h = 130;
  c.width = w * dpr; c.height = h * dpr;
  const x = c.getContext('2d');
  x.scale(dpr, dpr);
  x.clearRect(0, 0, w, h);
  const prices = intra.prices;
  const base = intra.prevClose || prices[0];
  const dev = Math.max(...prices.map((p) => Math.abs(p - base)), 0.01);
  const pad = Math.max(dev * 0.15, 0.01);
  const lo = base - dev - pad, hi = base + dev + pad;
  const px = (i) => (i / (prices.length - 1)) * w;
  const py = (p) => h - ((p - lo) / (hi - lo)) * h;

  // 昨收基准虚线
  x.strokeStyle = 'rgba(150,155,165,0.4)';
  x.lineWidth = 1; x.setLineDash([4, 3]);
  x.beginPath(); x.moveTo(0, py(base)); x.lineTo(w, py(base)); x.stroke();
  x.setLineDash([]);

  // 折线
  x.strokeStyle = color; x.lineWidth = 1.8;
  x.lineJoin = 'round'; x.lineCap = 'round';
  x.beginPath();
  x.moveTo(px(0), py(prices[0]));
  for (let i = 1; i < prices.length; i++) x.lineTo(px(i), py(prices[i]));
  x.stroke();

  // 渐变填充
  const grad = x.createLinearGradient(0, 0, 0, h);
  const rgb = color === '#e53935' ? '229,57,53' : '22,163,74';
  grad.addColorStop(0, `rgba(${rgb},0.28)`);
  grad.addColorStop(1, `rgba(${rgb},0)`);
  x.lineTo(w, h); x.lineTo(0, h); x.closePath();
  x.fillStyle = grad; x.fill();
}

function render(data) {
  if (!data) return;
  const s = data.spot;
  const dir = s ? (s.isUp ? 'up' : 'down') : '';
  const color = s ? (s.isUp ? '#e53935' : '#16a34a') : '#9ca3af';
  const sign = s ? (s.isUp ? '+' : '−') : '';
  const arrow = s ? (s.isUp ? '▲' : '▼') : '';

  let html = '';
  // 现货主区
  html += `<div class="spot">
    <div class="meta">上海金 · Au99.99${s && s.time ? ' · ' + esc(s.time) : ''}</div>
    <div class="price-row">
      <span class="price">${s ? fmt(s.price) : '--'}</span>
      <span class="unit">元/克</span>
    </div>
    <div class="change-row ${dir}">
      <span>${s ? arrow + ' ' + fmt(Math.abs(s.change)) : '--'}</span>
      <span class="badge ${dir}">${s ? sign + fmt(Math.abs(s.changePercent)) + '%' : '--'}</span>
      <span class="vs">较昨收</span>
    </div>
  </div>`;

  // 分时图
  if (data.intraday) {
    const srcLabel = data.intraday.source === 'xau' ? '伦敦金现货 · 美元/盎司' : '上海金 Au99.99 · 元/克';
    html += `<div class="chart-wrap">
      <canvas id="chart"></canvas>
      <div class="chart-axis">
        <span>${esc(data.intraday.times[0] || '')}</span>
        <span>${srcLabel}</span>
        <span>${esc(data.intraday.times[data.intraday.times.length - 1] || '')}</span>
      </div>
    </div>`;
  }

  // 四宫格
  if (s) {
    html += `<div class="grid">
      <div class="cell"><div class="k">今开</div><div class="v">${fmt(s.open)}</div></div>
      <div class="cell"><div class="k">最高</div><div class="v">${fmt(s.high)}</div></div>
      <div class="cell"><div class="k">最低</div><div class="v">${fmt(s.low)}</div></div>
      <div class="cell"><div class="k">昨收</div><div class="v">${fmt(s.prevClose)}</div></div>
    </div>`;
  }

  // 阶段涨跌
  if (data.periodChanges && data.periodChanges.length) {
    html += `<div class="section">
      <div class="section-title">阶段涨跌幅</div>
      <div class="periods">`;
    for (const p of data.periodChanges) {
      const d = p.percent >= 0 ? 'up' : 'down';
      const sg = p.percent >= 0 ? '+' : '−';
      html += `<div class="p"><div class="k">${esc(p.label)}</div><div class="v ${d}">${sg}${fmt(Math.abs(p.percent))}%</div></div>`;
    }
    html += `</div><div class="note">周/月/年为伦敦金现货历史基准价对比</div></div>`;
  }

  // 价格列表
  if (data.priceGroups && data.priceGroups.length) {
    const count = data.priceGroups.reduce((a, g) => a + g.items.length, 0);
    html += `<div class="section">
      <div class="section-title">更多黄金报价 <span class="count">${count} 项</span></div>`;
    for (const g of data.priceGroups) {
      html += `<div class="pgroup"><div class="t">${esc(g.title)}</div>`;
      for (const it of g.items) {
        html += `<div class="prow">
          <span class="name">${esc(it.name)}</span>
          ${it.note ? `<span class="note">${esc(it.note)}</span>` : ''}
          <span class="price">${it.price === '--' ? '--' : '¥' + esc(it.price)}</span>
        </div>`;
      }
      html += `</div>`;
    }
    html += `<div class="note">聚合站每日更新，仅供比价参考 · 与银行 App 实时成交价可能存在差异</div></div>`;
  }

  // 底部
  const t = data.fetchTime ? new Date(data.fetchTime).toLocaleTimeString('zh-CN', { hour12: false }) : '--';
  html += `<div class="footer"><span>更新于 ${t} · 每3秒自动刷新</span><span class="spacer"></span><button id="quitBtn">退出</button></div>`;

  content.innerHTML = html;
  document.getElementById('quitBtn').onclick = () => ipcRenderer.send('quit-app');

  if (data.intraday) drawChart(data.intraday, color);
}

ipcRenderer.on('gold-data', (_, data) => render(data));
