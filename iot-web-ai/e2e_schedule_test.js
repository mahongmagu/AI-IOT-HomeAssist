const fs = require('fs');
const path = require('path');

function pad(n){ return String(n).padStart(2,'0'); }
function formatLocalDateTime(date){
  return `${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}
function getNextOccurrenceForTime(hour, minute, startDate = new Date()){
  const now = new Date(startDate);
  const target = new Date(now);
  target.setHours(hour, minute, 0, 0);
  if (target.getTime() <= now.getTime()) target.setDate(target.getDate()+1);
  return target;
}
function parseRecurringTimePoint(timeValue){
  if (!timeValue) return null;
  const parsed = new Date(timeValue);
  if (!isNaN(parsed.getTime())) return parsed;
  const str = String(timeValue);
  const match = str.match(/T(\d{2}):(\d{2})/);
  if (match){
    const now = new Date();
    const point = new Date(now);
    point.setHours(Number(match[1]), Number(match[2]), 0, 0);
    return point;
  }
  return null;
}

(async function(){
  const desired = '18:45';
  const [h,m] = desired.split(':').map(Number);

  console.log('现在本地时间:', new Date().toString());

  // 前端：计算下次本地时间并用本地格式发送
  const next = getNextOccurrenceForTime(h,m);
  const localStr = formatLocalDateTime(next);
  console.log('前端计算并发送本地时间字符串:', localStr);

  // 后端：接收 local string 并保存为 UTC ISO
  const savedISO = new Date(localStr).toISOString();
  console.log('后端保存为 UTC ISO:', savedISO);

  // 写入 schedules.json（备份原文件后添加条目）
  const file = path.join(__dirname,'data','schedules.json');
  let data = {};
  try { data = JSON.parse(fs.readFileSync(file,'utf8')); } catch(e){ console.error('无法读取 schedules.json', e); return; }
  const id = 'e2e-test-' + Date.now();
  data[id] = {
    id,
    name: 'E2E 测试任务',
    unitId: 'test-unit',
    cmd: 'ON',
    interval: 86400000,
    time: savedISO,
    enabled: true,
    createdAt: new Date().toISOString(),
    recurring: true
  };
  fs.writeFileSync(file, JSON.stringify(data,null,2),'utf8');
  console.log('已写入 schedules.json 条目 id=', id);

  // 模拟恢复：parse 存储的 ISO 并检查本地时刻
  const read = data[id];
  const parsed = parseRecurringTimePoint(read.time);
  console.log('恢复解析得到本地 Date:', parsed && parsed.toString());
  if (parsed){
    console.log('恢复后的本地时分:', pad(parsed.getHours())+':'+pad(parsed.getMinutes()));
    const delayMs = parsed.getTime() - Date.now();
    console.log('到下一次执行的延迟(秒):', Math.round(delayMs/1000));
  }

  // 输出样例 schedules.json 中前 5 项 time 字段
  console.log('\nsample entries:');
  const keys = Object.keys(data).slice(0,5);
  for(const k of keys){ console.log(k, '=>', data[k].time); }

})();
