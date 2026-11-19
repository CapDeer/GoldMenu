// 金价数据抓取服务（复用 macOS 版验证过的全部数据源）
const https = require('https');

const URLS = {
  spot: 'https://hq.sinajs.cn/list=gds_AU9999',
  prices: 'https://v2.xxapi.cn/api/goldprice',
  xauHistory: 'https://stock2.finance.sina.com.cn/futures/api/jsonp.php/var%20t=/GlobalFuturesService.getGlobalFuturesDailyKLine?symbol=XAU',
  sgeIntraday: 'https://www.sge.com.cn/graph/quotations',
  xauIntraday: 'https://stock2.finance.sina.com.cn/futures/api/jsonp.php/var%20t=/GlobalFuturesService.getGlobalFuturesMinLine?symbol=XAU',
};

// 简单 GET，返回 Buffer（保留原始字节以处理 GBK）
function getBuffer(url, headers = {}, timeout = 12000) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        ...headers,
      },
      timeout,
    }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    });
    req.on('timeout', () => { req.destroy(new Error('timeout')); });
    req.on('error', reject);
  });
}

function getText(url, headers = {}, encoding = 'utf8') {
  return getBuffer(url, headers).then((buf) => {
    if (encoding.toLowerCase() === 'gbk') {
      try { return new TextDecoder('gbk').decode(buf); } catch (e) { return buf.toString('utf8'); }
    }
    return buf.toString(encoding);
  });
}

// 新浪 Au99.99 现货：GBK，逗号分隔
// 字段: 0现价 4最高 5最低 6时间 7昨收 8今开 12日期 13名称
async function fetchSpot() {
  const raw = await getText(URLS.spot, { Referer: 'https://finance.sina.com.cn' }, 'gbk');
  const m = raw.match(/"([^"]+)"/);
  if (!m) throw new Error('spot parse');
  const f = m[1].split(',');
  if (f.length < 9) throw new Error('spot fields');
  const price = parseFloat(f[0]);
  const prevClose = parseFloat(f[7]);
  if (!(price > 0)) throw new Error('spot price');
  return {
    price,
    open: parseFloat(f[8]) || 0,
    high: parseFloat(f[4]) || 0,
    low: parseFloat(f[5]) || 0,
    prevClose,
    time: f[6] || '',
    change: price - prevClose,
    changePercent: prevClose > 0 ? (price - prevClose) / prevClose * 100 : 0,
    isUp: price >= prevClose,
  };
}

// xxapi 聚合价格：银行金条 + 品牌金饰
async function fetchAllPrices() {
  const raw = await getText(URLS.prices);
  const json = JSON.parse(raw);
  const obj = json.data || {};
  const groups = [];
  const bank = obj.bank_gold_bar_price || [];
  if (bank.length) {
    groups.push({
      title: '银行投资金条',
      items: bank.map((x) => ({ name: x.bank || '', price: x.price || '--', note: '' })),
    });
  }
  const brand = obj.precious_metal_price || [];
  if (brand.length) {
    groups.push({
      title: '品牌金饰金价',
      items: brand.map((x) => ({ name: x.brand || '', price: x.gold_price || '--', note: x.updated_date || '' })),
    });
  }
  return groups;
}

// 伦敦金历史日K（jsonp），算近一周/一月/一年涨跌
let cachedPeriods = null;
let cachedDay = '';
async function fetchPeriodChanges() {
  const today = new Date().toISOString().slice(0, 10);
  if (cachedPeriods && cachedDay === today) return cachedPeriods;
  const raw = await getText(URLS.xauHistory, { Referer: 'https://finance.sina.com.cn' });
  const m = raw.match(/var t=\(([\s\S]*?)\);/);
  if (!m) throw new Error('history parse');
  const arr = JSON.parse(m[1]);
  if (!Array.isArray(arr) || arr.length < 3) throw new Error('history empty');
  const closeOf = (x) => parseFloat(x.close) || 0;
  const dateOf = (x) => new Date(x.date + 'T00:00:00Z');
  const last = arr[arr.length - 1];
  const current = closeOf(last);
  const lastDate = dateOf(last);
  if (!(current > 0) || isNaN(lastDate.getTime())) throw new Error('history last');

  function baseOf(daysAgo) {
    const target = new Date(lastDate.getTime() - daysAgo * 86400000);
    let best = null;
    for (const item of arr) {
      const d = dateOf(item);
      if (isNaN(d.getTime())) continue;
      if (d <= target) best = item; else break;
    }
    return best;
  }
  const specs = [
    { id: 'week', label: '近一周', days: 7 },
    { id: 'month', label: '近一月', days: 30 },
    { id: 'year', label: '近一年', days: 365 },
  ];
  const result = [];
  for (const s of specs) {
    const b = baseOf(s.days);
    if (!b || !(closeOf(b) > 0)) continue;
    result.push({
      id: s.id, label: s.label,
      percent: (current - closeOf(b)) / closeOf(b) * 100,
      baseDate: b.date || '',
    });
  }
  if (result.length) { cachedPeriods = result; cachedDay = today; }
  return result;
}

// 上金所 Au99.99 日内分时（人民币/克，口径与主区一致）
async function fetchSgeIntraday() {
  const raw = await getText(URLS.sgeIntraday, { Referer: 'https://www.sge.com.cn/' });
  const json = JSON.parse(raw);
  const times = json.times || [];
  const rawPrices = json.data || [];
  if (!times.length || times.length !== rawPrices.length) throw new Error('sge fields');
  const prices = rawPrices.map((x) => parseFloat(x));
  if (prices.some((x) => isNaN(x)) || !(prices[0] > 0)) throw new Error('sge prices');
  return {
    times, prices,
    prevClose: prices[0],
    high: json.max || Math.max(...prices),
    low: json.min || Math.min(...prices),
    updateTime: json.delaystr || json.now || '',
    source: 'sge',
  };
}

// 新浪 XAU 伦敦金分时（美元/盎司）——上金所被 WAF 拦时的兜底
// 首行: [日期,昨收,交易所,'',时间,首价,0,0,均价,完整时间]（10字段）
// 后续: [时间,价格,0,0,均价,完整时间]（6字段）
async function fetchXauIntraday() {
  const raw = await getText(URLS.xauIntraday, { Referer: 'https://finance.sina.com.cn' });
  const m = raw.match(/var t=\(([\s\S]*?)\);/);
  if (!m) throw new Error('xau minLine parse');
  const obj = JSON.parse(m[1]);
  const rows = obj.minLine_1d || [];
  if (rows.length < 2) throw new Error('xau minLine empty');
  const times = [];
  const prices = [];
  let prevClose = 0;
  rows.forEach((row, i) => {
    const isFirst = row.length >= 10;
    const time = isFirst ? row[4] : row[0];
    const price = parseFloat(isFirst ? row[5] : row[1]);
    if (isFirst) prevClose = parseFloat(row[1]) || 0;
    if (time && price > 0) { times.push(time); prices.push(price); }
  });
  if (prices.length < 2) throw new Error('xau minLine prices');
  return {
    times, prices,
    prevClose: prevClose || prices[0],
    high: Math.max(...prices),
    low: Math.min(...prices),
    updateTime: times[times.length - 1] || '',
    source: 'xau',
  };
}

// 分时数据：优先上金所，失败回退伦敦金，再失败回退缓存
let cachedIntraday = null;
let intradayCacheTime = 0;
async function fetchIntraday() {
  if (cachedIntraday && Date.now() - intradayCacheTime < 3000) return cachedIntraday;
  let intra = null;
  try {
    intra = await fetchSgeIntraday();
  } catch (e) {
    try { intra = await fetchXauIntraday(); } catch (e2) { intra = cachedIntraday; }
  }
  if (intra) { cachedIntraday = intra; intradayCacheTime = Date.now(); }
  return intra;
}

// 汇总：并发抓全部，单项失败不影响其他
async function fetchAll() {
  const [spot, prices, periods, intraday] = await Promise.all([
    fetchSpot().catch(() => null),
    fetchAllPrices().catch(() => []),
    fetchPeriodChanges().catch(() => []),
    fetchIntraday(),
  ]);
  const periodChanges = [...periods];
  if (spot) {
    periodChanges.unshift({
      id: 'today', label: '今日',
      percent: spot.changePercent, baseDate: '昨收',
    });
  }
  return {
    spot,
    priceGroups: prices,
    periodChanges,
    intraday,
    fetchTime: new Date().toISOString(),
  };
}

module.exports = { fetchAll, fetchSpot, fetchIntraday };
